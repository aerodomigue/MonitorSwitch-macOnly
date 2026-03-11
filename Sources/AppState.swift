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
        Task.detached { [ddcService] in
            let monitors = ddcService.listExternalMonitors()
            await MainActor.run { [self] in
                availableMonitors = monitors
            }
        }
    }
    #endif

    func detectCurrentInput() {
        updateStatusMessage("Detecting current input...")
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        Task.detached { [ddcService] in
            let input = ddcService.readCurrentInput(monitorID: monitorID)
            await MainActor.run { [self] in
                if let input {
                    currentDetectedInput = input
                    updateMonitorInputSource(input)
                    updateStatusMessage("Detected: \(DDCService.inputName(for: input))")
                } else {
                    updateStatusMessage("Could not read input (select it manually below)")
                }
            }
        }
    }

    func testInputSwitch() {
        let input = monitorInputSource
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        updateStatusMessage("Testing input switch...")
        Task.detached { [ddcService] in
            let success = ddcService.switchInput(to: input, monitorID: monitorID)
            await MainActor.run { [self] in
                if success {
                    updateStatusMessage("Input switch sent: \(DDCService.inputName(for: input))")
                } else {
                    updateStatusMessage("Input switch failed (DDC-CI not supported?)")
                }
            }
        }
    }

    func scanInputs() {
        let inputs = DDCService.sortedInputs
        guard !inputs.isEmpty else { return }
        isScanning = true
        scanningInputIndex = 0
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        scanTask = Task { [ddcService] in
            var index = 0
            while !Task.isCancelled {
                await MainActor.run { [self] in
                    scanningInputIndex = index
                }
                let input = inputs[index]
                _ = await Task.detached {
                    ddcService.switchInput(to: input.value, monitorID: monitorID)
                }.value
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
        updateStatusMessage("Device connected: \(device.name)")

        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            startMonitoring()
        }
    }

    private func handleDeviceDisconnected(_ device: USBDevice) {
        updateStatusMessage("Device disconnected: \(device.name)")

        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        isMonitoring = true
        guard startupReady else { return }
        guard switchMode == "connect" || switchMode == "both" else { return }
        let input = monitorInputSource
        let monitorID = selectedMonitorID.isEmpty ? nil : selectedMonitorID
        Task.detached { [ddcService] in
            let success = ddcService.switchInput(to: input, monitorID: monitorID)
            await MainActor.run { [self] in
                if success {
                    updateStatusMessage("Switched to \(DDCService.inputName(for: input))")
                } else {
                    updateStatusMessage("Monitoring started (input switch failed)")
                }
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
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
        Task.detached { [ddcService] in
            let success = ddcService.switchInput(to: input, monitorID: monitorID)
            await MainActor.run { [self] in
                if success {
                    updateStatusMessage("Switched to \(DDCService.inputName(for: input)) (disconnect)")
                } else {
                    updateStatusMessage("Device disconnected (input switch failed)")
                }
            }
        }
    }

    private func startServices() {
        Task {
            await usbService.startMonitoring()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            startupReady = true
        }
    }

    private func loadSettings() {
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
