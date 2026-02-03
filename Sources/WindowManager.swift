//
//  WindowManager.swift
//  MonitorSwitchUI
//
//  Window management for opening device selection and settings windows
//

import SwiftUI
import Cocoa

@MainActor
class WindowManager: NSObject, ObservableObject {
    private var settingsWindow: NSWindow?
    private var isDockVisible = false
    
    func openSettings(appState: AppState, initialTab: SettingsTab = .general) {
        // If window already exists and is visible, update its content with new tab
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            // Create new content view with the requested tab
            let contentView = SettingsView(initialTab: initialTab)
                .environmentObject(appState)
            
            // Update the existing window's content
            let hostingController = NSHostingController(rootView: contentView)
            
            // Set proper frame size for the hosting controller
            hostingController.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            
            // Update window's content and ensure proper sizing
            existingWindow.contentViewController = hostingController
            existingWindow.setContentSize(NSSize(width: 900, height: 700))
            
            // Bring window to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Close and clean up any existing window
        closeSettings()
        
        // Show app in dock when opening settings
        showInDock()
        
        // Create content view with specified initial tab
        let contentView = SettingsView(initialTab: initialTab)
            .environmentObject(appState)
        
        // Create hosting controller
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        
        // Create window (no miniaturizable - menu bar app should just close)
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        guard let window = settingsWindow else { return }
        
        window.title = "MonitorSwitch Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false // Important: prevent automatic release
        
        // Set up window delegate to handle close events
        window.delegate = self
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openDeviceSettings(appState: AppState) {
        // Open settings window with devices tab selected
        openSettings(appState: appState, initialTab: .devices)
    }
    
    func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
        
        // Hide from dock when closing settings
        hideFromDock()
    }
    
    func closeAllWindows() {
        closeSettings()
    }
    
    private func showInDock() {
        if !isDockVisible {
            NSApp.setActivationPolicy(.regular)
            isDockVisible = true
            print("App now visible in dock")
        }
    }
    
    private func hideFromDock() {
        if isDockVisible {
            NSApp.setActivationPolicy(.accessory)
            isDockVisible = false
            print("App hidden from dock")
        }
    }
}

// MARK: - NSWindowDelegate
extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            settingsWindow = nil
            hideFromDock()
            print("Settings window closed, app hidden from dock")
        }
    }

}