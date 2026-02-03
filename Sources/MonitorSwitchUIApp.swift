//
//  MonitorSwitchUIApp.swift
//  MonitorSwitchUI
//
//  Created by MonitorSwitch Converter
//

import SwiftUI
import Cocoa

@main
struct MonitorSwitchUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState = AppState()
    private var windowManager = WindowManager()
    private var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Try to load custom icon, fallback to system icon
            if let customIcon = loadAppIcon() {
                button.image = customIcon
            } else {
                button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "MonitorSwitch")
            }
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
                .environmentObject(windowManager)
        )
        popover?.behavior = .transient
        
        // Set up event monitor to detect clicks outside the popover
        setupEventMonitor()
    }
    
    private func loadAppIcon() -> NSImage? {
        // Try to load from bundle resources
        if let bundle = Bundle.main.path(forResource: "MonitorSwitch", ofType: "png") {
            return NSImage(contentsOfFile: bundle)
        }
        
        // Try to load from main bundle
        if let iconImage = NSImage(named: "MonitorSwitch") {
            // Resize for menu bar (typically 16x16 or 18x18)
            let resizedImage = NSImage(size: NSSize(width: 16, height: 16))
            resizedImage.lockFocus()
            iconImage.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            resizedImage.unlockFocus()
            return resizedImage
        }
        
        return nil
    }
    
    @objc func statusItemClicked() {
        guard let popover = popover else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                startEventMonitor()
            }
        }
    }
    
    private func setupEventMonitor() {
        // We'll set up the event monitor when needed
    }
    
    private func startEventMonitor() {
        // Stop any existing monitor
        stopEventMonitor()
        
        // Create a new event monitor for left mouse clicks
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self = self, let popover = self.popover, popover.isShown {
                // Check if the click is outside the popover
                let clickLocation = event.locationInWindow
                let popoverWindow = popover.contentViewController?.view.window
                
                if let window = popoverWindow {
                    let windowFrame = window.frame
                    if !windowFrame.contains(clickLocation) {
                        // Click is outside the popover, close it
                        DispatchQueue.main.async {
                            self.closePopover()
                        }
                    }
                }
            }
        }
    }
    
    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        stopEventMonitor()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running as menu bar app
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitor()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Don't do anything special when reopening - let the menu bar handle it
        return false
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Don't automatically show any windows when app becomes active
        // User interaction via menu bar should control window visibility
    }
}
