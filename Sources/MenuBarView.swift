//
//  MenuBarView.swift
//  MonitorSwitchUI
//
//  Menu bar interface for MonitorSwitch
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var windowManager: WindowManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if let iconImage = NSImage(named: "MonitorSwitch") {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "display")
                        .foregroundColor(.blue)
                }
                Text("MonitorSwitch")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Status section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(appState.isMonitoring ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(appState.isMonitoring ? "Monitoring" : "Not Monitoring")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let selectedDevice = appState.selectedDevice {
                    Text("Device: \(selectedDevice.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("No device selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Status: \(appState.statusMessage)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Divider()
            
            // Device management
            Button("Manage Devices") {
                windowManager.openDeviceSettings(appState: appState)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            
            Button("Settings") {
                windowManager.openSettings(appState: appState)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            
            Divider()
            
            // Quick actions
            if appState.selectedDevice != nil {
                Button("Test Screen Control") {
                    appState.testScreenControl()
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
            }
            
            Divider()
            
            // Quit button
            Button("Quit MonitorSwitch") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(12)
        .frame(width: 280)
    }
}