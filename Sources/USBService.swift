//
//  USBService.swift
//  MonitorSwitchUI
//
//  USB device monitoring service for macOS
//

import Foundation
import IOKit
import IOKit.usb
import Combine

@MainActor
class USBService: ObservableObject {
    @Published private(set) var devices: [USBDevice] = []
    
    private let devicesSubject = CurrentValueSubject<[USBDevice], Never>([])
    private var deviceConnectedSubject = PassthroughSubject<USBDevice, Never>()
    private var deviceDisconnectedSubject = PassthroughSubject<USBDevice, Never>()
    private var monitoringTimer: Timer?
    
    var devicesPublisher: AnyPublisher<[USBDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }
    
    var deviceConnectedPublisher: AnyPublisher<USBDevice, Never> {
        deviceConnectedSubject.eraseToAnyPublisher()
    }
    
    var deviceDisconnectedPublisher: AnyPublisher<USBDevice, Never> {
        deviceDisconnectedSubject.eraseToAnyPublisher()
    }
    
    private var previousDevices: Set<String> = []
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() async {
        // Stop any existing timer first
        await MainActor.run {
            stopMonitoring()
        }
        
        await refreshDevices()
        
        // Start a timer to periodically check for device changes
        await MainActor.run {
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshDevices()
                }
            }
        }
    }
    
    nonisolated func stopMonitoring() {
        Task { @MainActor in
            monitoringTimer?.invalidate()
            monitoringTimer = nil
        }
    }
    
    @MainActor
    func refreshDevices() async {
        let discoveredDevices = discoverUSBDevices()
        let currentDeviceIDs = Set(discoveredDevices.map { $0.deviceID })
        
        // Find newly connected devices
        let newDevices = discoveredDevices.filter { !previousDevices.contains($0.deviceID) }
        for device in newDevices {
            deviceConnectedSubject.send(device)
        }
        
        // Find disconnected devices
        let disconnectedDeviceIDs = previousDevices.subtracting(currentDeviceIDs)
        for deviceID in disconnectedDeviceIDs {
            if let disconnectedDevice = devices.first(where: { $0.deviceID == deviceID }) {
                var updatedDevice = disconnectedDevice
                updatedDevice.isConnected = false
                deviceDisconnectedSubject.send(updatedDevice)
            }
        }
        
        devices = discoveredDevices
        devicesSubject.send(devices)
        previousDevices = currentDeviceIDs
    }
    
    private func discoverUSBDevices() -> [USBDevice] {
        var devices: [USBDevice] = []
        
        // Create a matching dictionary for USB devices
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            print("Failed to create matching dictionary")
            return devices
        }
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            print("Failed to get matching services")
            return devices
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service: io_service_t = 0
        while case let nextService = IOIteratorNext(iterator), nextService != 0 {
            service = nextService
            defer { IOObjectRelease(service) }
            
            if let device = createUSBDevice(from: service) {
                devices.append(device)
            }
        }
        
        return devices
    }
    
    private func createUSBDevice(from service: io_service_t) -> USBDevice? {
        // Get device properties
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