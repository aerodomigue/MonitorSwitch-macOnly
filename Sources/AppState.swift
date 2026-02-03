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
    @Published var isMonitorOn: Bool = true
    @Published var isAutoStartEnabled: Bool = false
    @Published var startMinimized: Bool = false
    @Published var screenOffDelay: Int = 10
    @Published var statusMessage: String = "Ready"
    @Published var isMonitoring: Bool = false
    
    private let usbService = USBService()
    private let displayService = DisplayService()
    private let settingsService = SettingsService()
    private let autostartService = AutostartService()
    
    private var cancellables = Set<AnyCancellable>()
    private var autoTurnOnTask: Task<Void, Never>? // Task for auto turn-on after delay
    
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
        
        // Subscribe to display state changes
        displayService.displayStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.isMonitorOn, on: self)
            .store(in: &cancellables)
    }
    
    func selectDevice(_ device: USBDevice) {
        selectedDevice = device
        // Save stableID (vendorID:productID) to handle devices reconnecting on different ports
        settingsService.selectedDeviceID = device.stableID
        saveSettings()
        updateStatusMessage("Selected device: \(device.name)")

        // Start monitoring if device is connected
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
    
    func updateScreenDelay(_ delay: Int) {
        screenOffDelay = delay
        settingsService.screenOffDelay = delay
        saveSettings()
    }
    
    func testScreenControl() {
        Task {
            updateStatusMessage("Testing screen control...")
            displayService.test()
            updateStatusMessage("Screen control test completed - check console for details")
        }
    }
    
    func refreshDevices() {
        Task {
            await usbService.refreshDevices()
            updateStatusMessage("Device list refreshed")
        }
    }
    
    private func handleDeviceConnected(_ device: USBDevice) {
        updateStatusMessage("Device connected: \(device.name)")

        // Compare by stableID to handle devices reconnecting on different ports (KVM switches)
        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            // Cancel any pending auto turn-on timer since device is back
            autoTurnOnTask?.cancel()
            autoTurnOnTask = nil

            startMonitoring()
        }
    }
    
    private func handleDeviceDisconnected(_ device: USBDevice) {
        updateStatusMessage("Device disconnected: \(device.name)")

        // Compare by stableID to handle devices reconnecting on different ports (KVM switches)
        if let selectedDevice = selectedDevice,
           selectedDevice.stableID == device.stableID {
            stopMonitoring()

            // Turn off monitor IMMEDIATELY
            displayService.turnOff()
            updateStatusMessage("Display turned off - will auto turn on in \(screenOffDelay)s")

            // Start timer to turn back on after delay
            autoTurnOnTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(screenOffDelay) * 1_000_000_000)

                    // Only turn on if task wasn't cancelled (device didn't reconnect)
                    if !Task.isCancelled {
                        displayService.turnOn()
                        updateStatusMessage("Display auto turned on after \(screenOffDelay)s")
                    }
                } catch {
                    // Task was cancelled (device reconnected)
                    print("Auto turn-on cancelled - device reconnected")
                }
            }
        }
    }
    
    private func startMonitoring() {
        isMonitoring = true
        Task {
            displayService.turnOn()
        }
        updateStatusMessage("Monitoring started")
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        updateStatusMessage("Monitoring stopped")
    }
    
    private func startServices() {
        Task {
            await usbService.startMonitoring()
        }
    }
    
    private func loadSettings() {
        let settings = settingsService.loadSettings()
        isAutoStartEnabled = settings.autoStartEnabled
        startMinimized = settings.startMinimized
        screenOffDelay = settings.screenOffDelay
        
        // The saved device will be loaded when devices are discovered
        // via the checkForSavedDevice() method called from setupBindings
    }
    
    private func checkForSavedDevice() {
        // Only try to load saved device if no device is currently selected
        guard selectedDevice == nil else { return }

        let savedID = settingsService.selectedDeviceID
        guard !savedID.isEmpty else { return }

        // Extract stableID from saved ID (handles old format "vendor:product:location" and new format "vendor:product")
        let savedStableID: String
        let parts = savedID.split(separator: ":")
        if parts.count >= 2 {
            savedStableID = "\(parts[0]):\(parts[1])"
        } else {
            savedStableID = savedID
        }

        // Find the saved device by stableID (handles port changes)
        if let device = connectedDevices.first(where: { $0.stableID == savedStableID }) {
            selectedDevice = device
            // Update saved ID to new stableID format
            settingsService.selectedDeviceID = device.stableID
            updateStatusMessage("Restored saved device: \(device.displayName)")

            // Start monitoring if device is connected
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
        
        // Auto-clear status message after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusMessage == message {
                statusMessage = "Ready"
            }
        }
    }
}