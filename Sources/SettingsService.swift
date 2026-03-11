//
//  SettingsService.swift
//  MonitorSwitchUI
//
//  Settings management and persistence
//

import Foundation

struct AppSettings: Codable {
    var selectedDeviceID: String = ""
    var autoStartEnabled: Bool = false
    var startMinimized: Bool = false
    var monitorInputSource: UInt8 = 0x0F  // Default: DisplayPort-1
    var selectedMonitorID: String = ""    // Empty = auto (first found)
    var switchMode: String = "connect"       // "connect", "disconnect", "both"
    var disconnectInputSource: UInt8 = 0x11  // Default: HDMI-1

    static let `default` = AppSettings()
}

class SettingsService: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "MonitorSwitchUISettings"

    @Published var selectedDeviceID: String = "" {
        didSet { saveSettings() }
    }

    @Published var autoStartEnabled: Bool = false {
        didSet { saveSettings() }
    }

    @Published var startMinimized: Bool = false {
        didSet { saveSettings() }
    }

    @Published var monitorInputSource: UInt8 = 0x0F {
        didSet { saveSettings() }
    }

    @Published var selectedMonitorID: String = "" {
        didSet { saveSettings() }
    }

    @Published var switchMode: String = "connect" {
        didSet { saveSettings() }
    }

    @Published var disconnectInputSource: UInt8 = 0x11 {
        didSet { saveSettings() }
    }

    init() {
        _ = loadSettings()
    }

    func loadSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            let defaultSettings = AppSettings.default
            saveSettings(defaultSettings)
            return defaultSettings
        }

        // Update published properties
        selectedDeviceID = settings.selectedDeviceID
        autoStartEnabled = settings.autoStartEnabled
        startMinimized = settings.startMinimized
        monitorInputSource = settings.monitorInputSource
        selectedMonitorID = settings.selectedMonitorID
        switchMode = settings.switchMode
        disconnectInputSource = settings.disconnectInputSource

        return settings
    }

    func saveSettings() {
        let settings = AppSettings(
            selectedDeviceID: selectedDeviceID,
            autoStartEnabled: autoStartEnabled,
            startMinimized: startMinimized,
            monitorInputSource: monitorInputSource,
            selectedMonitorID: selectedMonitorID,
            switchMode: switchMode,
            disconnectInputSource: disconnectInputSource
        )
        saveSettings(settings)
    }

    private func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            LogService.shared.log("Failed to encode settings")
            return
        }

        userDefaults.set(data, forKey: settingsKey)
        userDefaults.synchronize()
    }

    func resetToDefaults() {
        let defaultSettings = AppSettings.default
        selectedDeviceID = defaultSettings.selectedDeviceID
        autoStartEnabled = defaultSettings.autoStartEnabled
        startMinimized = defaultSettings.startMinimized
        monitorInputSource = defaultSettings.monitorInputSource
        selectedMonitorID = defaultSettings.selectedMonitorID
        switchMode = defaultSettings.switchMode
        disconnectInputSource = defaultSettings.disconnectInputSource

        saveSettings(defaultSettings)
    }
}
