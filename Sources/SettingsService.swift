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
    var screenOffDelay: Int = 10
    
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
    
    @Published var screenOffDelay: Int = 10 {
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
        screenOffDelay = settings.screenOffDelay
        
        return settings
    }
    
    func saveSettings() {
        let settings = AppSettings(
            selectedDeviceID: selectedDeviceID,
            autoStartEnabled: autoStartEnabled,
            startMinimized: startMinimized,
            screenOffDelay: screenOffDelay
        )
        saveSettings(settings)
    }
    
    private func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            print("Failed to encode settings")
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
        screenOffDelay = defaultSettings.screenOffDelay
        
        saveSettings(defaultSettings)
    }
}