//
//  USBService.swift
//  MonitorSwitchUI
//
//  USB device monitoring service for macOS using IOKit notifications
//

import Foundation
import IOKit
import IOKit.usb
import Combine

// Global weak reference for IOKit callbacks (C callbacks can't capture Swift context)
@MainActor private weak var sharedUSBService: USBService?

@MainActor
class USBService: ObservableObject {
    @Published private(set) var devices: [USBDevice] = []

    private let devicesSubject = CurrentValueSubject<[USBDevice], Never>([])
    private var deviceConnectedSubject = PassthroughSubject<USBDevice, Never>()
    private var deviceDisconnectedSubject = PassthroughSubject<USBDevice, Never>()

    // IOKit notification objects
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    var devicesPublisher: AnyPublisher<[USBDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    var deviceConnectedPublisher: AnyPublisher<USBDevice, Never> {
        deviceConnectedSubject.eraseToAnyPublisher()
    }

    var deviceDisconnectedPublisher: AnyPublisher<USBDevice, Never> {
        deviceDisconnectedSubject.eraseToAnyPublisher()
    }

    /// Track devices by stableID (vendorID:productID) to handle port changes (e.g., KVM switches)
    private var previousDeviceStableIDs: Set<String> = []

    init() {
        sharedUSBService = self
    }

    func startMonitoring() async {
        // Clean up any existing notifications
        cleanupNotifications()

        // Initial device discovery
        await refreshDevices()

        // Set up IOKit notifications for instant device detection
        setupIOKitNotifications()
    }

    private func setupIOKitNotifications() {
        // Create notification port
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            print("USBService: Failed to create notification port")
            return
        }
        notificationPort = port

        // Add the notification port to the main run loop
        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Set up device ADDED notification
        if let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) {
            let result = IOServiceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                matchingDict,
                usbDeviceCallback,
                nil,
                &addedIterator
            )

            if result == KERN_SUCCESS {
                // Drain iterator to arm the notification
                drainIterator(addedIterator)
            } else {
                print("USBService: Failed to add device added notification: \(result)")
            }
        }

        // Set up device REMOVED notification
        if let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) {
            let result = IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                matchingDict,
                usbDeviceCallback,
                nil,
                &removedIterator
            )

            if result == KERN_SUCCESS {
                // Drain iterator to arm the notification
                drainIterator(removedIterator)
            } else {
                print("USBService: Failed to add device removed notification: \(result)")
            }
        }

        print("USBService: IOKit notifications active (instant device detection)")
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    private func cleanupNotifications() {
        if let port = notificationPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            IONotificationPortDestroy(port)
            notificationPort = nil
        }

        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }

        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
    }

    nonisolated func stopMonitoring() {
        Task { @MainActor in
            cleanupNotifications()
            sharedUSBService = nil
        }
    }

    @MainActor
    func refreshDevices() async {
        let discoveredDevices = discoverUSBDevices()
        let currentStableIDs = Set(discoveredDevices.map { $0.stableID })

        // Find newly connected devices (by stableID to handle port changes)
        let newDevices = discoveredDevices.filter { !previousDeviceStableIDs.contains($0.stableID) }
        for device in newDevices {
            deviceConnectedSubject.send(device)
        }

        // Find disconnected devices (by stableID)
        let disconnectedStableIDs = previousDeviceStableIDs.subtracting(currentStableIDs)
        for stableID in disconnectedStableIDs {
            if let disconnectedDevice = devices.first(where: { $0.stableID == stableID }) {
                var updatedDevice = disconnectedDevice
                updatedDevice.isConnected = false
                deviceDisconnectedSubject.send(updatedDevice)
            }
        }

        devices = discoveredDevices
        devicesSubject.send(devices)
        previousDeviceStableIDs = currentStableIDs
    }

    private func discoverUSBDevices() -> [USBDevice] {
        var devices: [USBDevice] = []

        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            print("USBService: Failed to create matching dictionary")
            return devices
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

        guard result == KERN_SUCCESS else {
            print("USBService: Failed to get matching services")
            return devices
        }

        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            if let device = createUSBDevice(from: service) {
                devices.append(device)
            }
        }

        return devices
    }

    private func createUSBDevice(from service: io_service_t) -> USBDevice? {
        guard let vendorID = getUSBProperty(service: service, key: "idVendor") as? NSNumber,
              let productID = getUSBProperty(service: service, key: "idProduct") as? NSNumber else {
            return nil
        }

        let deviceName = getUSBProperty(service: service, key: "USB Product Name") as? String ?? ""
        let locationID = getUSBProperty(service: service, key: "locationID") as? NSNumber ?? NSNumber(value: 0)

        let vendorIDString = String(format: "%04x", vendorID.uint16Value)
        let productIDString = String(format: "%04x", productID.uint16Value)
        let deviceID = "\(vendorIDString):\(productIDString):\(locationID.uint32Value)"

        return USBDevice(
            deviceID: deviceID,
            name: deviceName,
            vendorID: vendorIDString,
            productID: productIDString,
            isConnected: true
        )
    }

    private func getUSBProperty(service: io_service_t, key: String) -> Any? {
        let cfKey = key as CFString
        return IORegistryEntryCreateCFProperty(service, cfKey, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - IOKit C Callback

private func usbDeviceCallback(_: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    // Drain iterator to re-arm notification
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }

    // Refresh devices on main thread via global reference
    Task { @MainActor in
        await sharedUSBService?.refreshDevices()
    }
}
