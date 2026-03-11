//
//  AppState.swift
//  MonitorSwitchUI
//
//  Application state management
//

import SwiftUI
import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var connectedDevices: [USBDevice] = []
    @Published var selectedDevice: USBDevice?
    @Published var isAutoStartEnabled: Bool = false
    @Published var startMinimized: Bool = false
    @Published var monitorInputSource: UInt8 = 0x0F
    @Published var currentDetectedInput: UInt8? = nil
    @Published var selectedMonitorID: String = ""
    @Published var switchMode: String = "connect"
    @Published var disconnectInputSource: UInt8 = 0x11
    #if arch(arm64)
    @Published var availableMonitors: [ExternalMonitor] = []
    #endif
    @Published var statusMessage: String = "Ready"
    @Published var isMonitoring: Bool = false
    @Published var isScanning: Bool = false
    @Published var scanningInputIndex: Int = 0
    private var scanTask: Task<Void, Never>?

    private let usbService = USBService()
    private let ddcService = DDCService()
    private let settingsService = SettingsService()
    private let autostartService = AutostartService()

    private var startupReady = false
    private var cancellables = Set<AnyCancellable>()
    private var lastDDCTask: Task<Void, Never>?

    init() {
        setupBindings()
        loadSettings()
        startServices()
    }

    deinit {
        usbService.stopMonitoring()
    }

    private func setupBindings() {
        // Subscribe to USB device changes
        usbService.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.connectedDevices = devices
                self?.checkForSavedDevice()
            }
            .store(in: &cancellables)

        // Subscribe to device connection/disconnection events
        usbService.deviceConnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.handleDeviceConnected(device)
            }
            .store(in: &cancellables)

        usbService.deviceDisconnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.handleDeviceDisconnected(device)
            }
            .store(in: &cancellables)
    }

    func selectDevice(_ device: USBDevice) {
        LogService.shared.log("Device selected: \(device.displayName) (\(device.stableID))")
        selectedDevice = device
        settingsService.selectedDeviceID = device.stableID
        saveSettings()
        updateStatusMessage("Selected device: \(device.name)")

        if device.isConnected {
            startMonitoring()
        }
    }

    func toggleAutoStart() {
        isAutoStartEnabled.toggle()
        autostartService.setAutostart(enabled: isAutoStartEnabled)
        settingsService.autoStartEnabled = isAutoStartEnabled
        saveSettings()
    }

    func toggleStartMinimized() {
        startMinimized.toggle()
        settingsService.startMinimized = startMinimized
        saveSettings()
    }

    func updateMonitorInputSource(_ input: UInt8) {
        monitorInputSource = input
        settingsService.monitorInputSource = input
        saveSettings()
    }

    func updateSelectedMonitorID(_ id: String) {
        selectedMonitorID = id
        settingsService.selectedMonitorID = id
        saveSettings()
    }

    func updateSwitchMode(_ mode: String) {
        switchMode = mode
        settingsService.switchMode = mode
        saveSettings()
    }

    func updateDisconnectInputSource(_ input: UInt8) {
        disconnectInputSource = input
        settingsService.disconnectInputSource = input
        saveSettings()
    }

    #if arch(arm64)
    func refreshMonitors() {
        let ddc = ddcService
        let previous = lastDDCTask
        lastDDCTask = Task.detached { [weak self] in
            await previous?.value
            let monitors: [ExternalMonitor]? = await withTaskGroup(of: [ExternalMonitor]?.self) { group in
                group.addTask {
                    return ddc.listExternalMonitors()
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                if let first = await group.next(), let value = first {
                    group.cancelAll()
                    return value
                }
                group.cancelAll()
                LogService.shared.log("DDC timeout: refreshMonitors")
                return nil
            }
            if let monitors {
                await MainActor.run { [weak self] in
                    self?.availableMonitors = monitors
                }
            }
        }
    }
    #endif

    func detectCurrentInput() {
        updateStatusMessage("Detecting current input...")
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        Task {
            let input: UInt8? = await enqueueDDCResult("detectCurrentInput") { ddc in
                ddc.readCurrentInput(monitorID: monitorID) ?? 0
            }
            if let input, input != 0 {
                currentDetectedInput = input
                updateMonitorInputSource(input)
                updateStatusMessage("Detected: \(DDCService.inputName(for: input))")
            } else {
                updateStatusMessage("Could not read input (select it manually below)")
            }
        }
    }

    func testInputSwitch() {
        let input = monitorInputSource
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        updateStatusMessage("Testing input switch...")
        Task {
            let success: Bool = await enqueueDDCResult("testInputSwitch") { ddc in
                ddc.switchInput(to: input, monitorID: monitorID)
            } ?? false
            if success {
                updateStatusMessage("Input switch sent: \(DDCService.inputName(for: input))")
            } else {
                updateStatusMessage("Input switch failed (DDC-CI not supported?)")
            }
        }
    }

    func scanInputs() {
        let inputs = DDCService.sortedInputs
        guard !inputs.isEmpty else { return }
        isScanning = true
        scanningInputIndex = 0
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        scanTask = Task {
            var index = 0
            while !Task.isCancelled {
                await MainActor.run { [self] in
                    scanningInputIndex = index
                }
                let input = inputs[index]
                let _: Bool? = await enqueueDDCResult("scanInputs[\(input.value)]") { ddc in
                    ddc.switchInput(to: input.value, monitorID: monitorID)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                index = (index + 1) % inputs.count
            }
        }
    }

    func confirmScannedInput() {
        let inputs = DDCService.sortedInputs
        guard scanningInputIndex < inputs.count else { return }
        let value = inputs[scanningInputIndex].value
        updateMonitorInputSource(value)
        stopScanningInputs()
        updateStatusMessage("Input set to \(DDCService.inputName(for: value))")
    }

    func stopScanningInputs() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func refreshDevices() {
        Task {
            await usbService.refreshDevices()
            updateStatusMessage("Device list refreshed")
        }
    }

    private func handleDeviceConnected(_ device: USBDevice) {
        LogService.shared.log("Device connected: \(device.displayName) (\(device.stableID))")
        updateStatusMessage("Device connected: \(device.name)")

        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            startMonitoring()
        }
    }

    private func handleDeviceDisconnected(_ device: USBDevice) {
        LogService.shared.log("Device disconnected: \(device.displayName) (\(device.stableID))")
        updateStatusMessage("Device disconnected: \(device.name)")

        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        isMonitoring = true
        LogService.shared.log("Start monitoring (mode: \(switchMode), startupReady: \(startupReady))")
        guard startupReady else { return }
        guard switchMode == "connect" || switchMode == "both" else { return }
        let input = monitorInputSource
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        Task {
            let success: Bool = await enqueueDDCResult("startMonitoring") { ddc in
                ddc.switchInput(to: input, monitorID: monitorID)
            } ?? false
            if success {
                updateStatusMessage("Switched to \(DDCService.inputName(for: input))")
            } else {
                updateStatusMessage("Monitoring started (input switch failed)")
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        LogService.shared.log("Stop monitoring (mode: \(switchMode), startupReady: \(startupReady))")
        guard startupReady else {
            updateStatusMessage("Device disconnected")
            return
        }
        guard switchMode == "disconnect" || switchMode == "both" else {
            updateStatusMessage("Device disconnected")
            return
        }
        let input = disconnectInputSource
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        Task {
            let success: Bool = await enqueueDDCResult("stopMonitoring") { ddc in
                ddc.switchInput(to: input, monitorID: monitorID)
            } ?? false
            if success {
                updateStatusMessage("Switched to \(DDCService.inputName(for: input)) (disconnect)")
            } else {
                updateStatusMessage("Device disconnected (input switch failed)")
            }
        }
    }

    /// Fire-and-forget DDC operation with serialization and 5s timeout.
    private func enqueueDDC(_ label: String, operation: @escaping @Sendable (DDCService) -> Void) {
        let ddc = ddcService
        let previous = lastDDCTask
        lastDDCTask = Task.detached {
            await previous?.value
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    operation(ddc)
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return false
                }
                if let completed = await group.next() {
                    if !completed {
                        LogService.shared.log("DDC timeout: \(label)")
                    }
                }
                group.cancelAll()
            }
        }
    }

    /// DDC operation with serialization, 5s timeout, and a return value.
    private func enqueueDDCResult<T: Sendable>(_ label: String, operation: @escaping @Sendable (DDCService) -> T) async -> T? {
        let ddc = ddcService
        let previous = lastDDCTask
        var result: T?
        let task: Task<Void, Never> = Task.detached {
            await previous?.value
            await withTaskGroup(of: T?.self) { group in
                group.addTask {
                    return operation(ddc)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                if let first = await group.next() {
                    if let value = first {
                        result = value
                    } else {
                        LogService.shared.log("DDC timeout: \(label)")
                    }
                }
                group.cancelAll()
            }
        }
        lastDDCTask = task
        await task.value
        return result
    }

    private func startServices() {
        Task {
            await usbService.startMonitoring()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            startupReady = true
        }
    }

    private func loadSettings() {
        LogService.shared.log("Loading settings...")
        let settings = settingsService.loadSettings()
        isAutoStartEnabled = settings.autoStartEnabled
        startMinimized = settings.startMinimized
        monitorInputSource = settings.monitorInputSource
        selectedMonitorID = settings.selectedMonitorID
        switchMode = settings.switchMode
        disconnectInputSource = settings.disconnectInputSource
        #if arch(arm64)
        refreshMonitors()
        #endif
    }

    private func checkForSavedDevice() {
        guard selectedDevice == nil else { return }

        let savedID = settingsService.selectedDeviceID
        guard !savedID.isEmpty else { return }

        let savedStableID: String
        let parts = savedID.split(separator: ":")
        if parts.count >= 2 {
            savedStableID = "\(parts[0]):\(parts[1])"
        } else {
            savedStableID = savedID
        }

        if let device = connectedDevices.first(where: { $0.stableID == savedStableID }) {
            selectedDevice = device
            settingsService.selectedDeviceID = device.stableID
            updateStatusMessage("Restored saved device: \(device.displayName)")

            if device.isConnected {
                startMonitoring()
            }
        }
    }

    private func saveSettings() {
        settingsService.saveSettings()
    }

    private func updateStatusMessage(_ message: String) {
        statusMessage = message

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusMessage == message {
                statusMessage = "Ready"
            }
        }
    }
}
