//
//  AutostartService.swift
//  MonitorSwitchUI
//
//  Autostart management for macOS
//

import Foundation
import ServiceManagement

class AutostartService: ObservableObject {
    private let bundleIdentifier = "com.aerodomigue.MonitorSwitchUI"
    
    func setAutostart(enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Use the new SMAppService API for macOS 13+
            let service = SMAppService.mainApp
            
            do {
                if enabled {
                    try service.register()
                    print("Successfully registered app for autostart")
                } else {
                    try service.unregister()
                    print("Successfully unregistered app from autostart")
                }
            } catch {
                print("Failed to \(enabled ? "register" : "unregister") autostart: \(error)")
            }
        } else {
            // Fallback for older macOS versions using deprecated API
            setAutostartLegacy(enabled: enabled)
        }
    }
    
    func isAutostartEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            return service.status == .enabled
        } else {
            return isAutostartEnabledLegacy()
        }
    }
    
    // Legacy implementation for macOS < 13
    private func setAutostartLegacy(enabled: Bool) {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        
        let plistPath = launchAgentsPath.appendingPathComponent("\(bundleIdentifier).plist")
        
        if enabled {
            // Create the launch agent plist
            createLaunchAgentPlist(at: plistPath)
        } else {
            // Remove the launch agent plist
            try? FileManager.default.removeItem(at: plistPath)
        }
    }
    
    private func isAutostartEnabledLegacy() -> Bool {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        
        let plistPath = launchAgentsPath.appendingPathComponent("\(bundleIdentifier).plist")
        return FileManager.default.fileExists(atPath: plistPath.path)
    }
    
    private func createLaunchAgentPlist(at url: URL) {
        guard let executablePath = Bundle.main.executablePath else {
            print("Failed to get executable path")
            return
        }
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleIdentifier)</string>
            <key>Program</key>
            <string>\(executablePath)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LaunchOnlyOnce</key>
            <true/>
        </dict>
        </plist>
        """
        
        do {
            // Ensure the LaunchAgents directory exists
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Write the plist file
            try plistContent.write(to: url, atomically: true, encoding: .utf8)
            print("Successfully created launch agent plist at: \(url.path)")
        } catch {
            print("Failed to create launch agent plist: \(error)")
        }
    }
}