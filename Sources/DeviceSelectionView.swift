//
//  DeviceSelectionView.swift
//  MonitorSwitchUI
//
//  Device selection and management interface
//

import SwiftUI

struct DeviceSelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    
    var filteredDevices: [USBDevice] {
        if searchText.isEmpty {
            return appState.connectedDevices
        } else {
            return appState.connectedDevices.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.deviceID.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and buttons
            HStack {
                Text("Select USB Device")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Refresh") {
                    appState.refreshDevices()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search devices...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal)
            
            // Device list
            if filteredDevices.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "usb")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "No USB devices found" : "No devices match search")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("Make sure your USB devices are connected and try refreshing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Refresh Devices") {
                            appState.refreshDevices()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredDevices) { device in
                    DeviceRowView(device: device, isSelected: appState.selectedDevice?.deviceID == device.deviceID) {
                        appState.selectDevice(device)
                        // Don't close window immediately - let user decide
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct DeviceRowView: View {
    let device: USBDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(device.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("ID: \(device.deviceID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text("Vendor: \(device.vendorID.uppercased()) • Product: \(device.productID.uppercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else {
                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelected {
                onSelect()
            }
        }
    }
}

#Preview {
    DeviceSelectionView()
        .environmentObject(AppState())
}