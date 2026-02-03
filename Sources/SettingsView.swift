//
//  SettingsView.swift
//  MonitorSwitchUI
//
//  Settings and preferences interface
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    let initialTab: SettingsTab
    @State private var selectedTab: SettingsTab
    
    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                if let iconImage = NSImage(named: "MonitorSwitch") {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text("MonitorSwitch Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            
            // Tabs
            TabView(selection: $selectedTab) {
                GeneralSettingsView()
                    .environmentObject(appState)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(SettingsTab.general)
                
                DeviceSettingsView()
                    .environmentObject(appState)
                    .tabItem {
                        Label("Devices", systemImage: "usb")
                    }
                    .tag(SettingsTab.devices)
                
                AboutView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(SettingsTab.about)
            }
        }
        .frame(width: 900, height: 700)
    }
}

enum SettingsTab: CaseIterable {
    case general
    case devices
    case about
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tempScreenDelay: Double = 10
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start automatically at login", isOn: Binding(
                    get: { appState.isAutoStartEnabled },
                    set: { _ in appState.toggleAutoStart() }
                ))
                .help("Launch MonitorSwitch automatically when you log in")
                
                Toggle("Start minimized", isOn: Binding(
                    get: { appState.startMinimized },
                    set: { _ in appState.toggleStartMinimized() }
                ))
                .help("Start the app in the menu bar without showing the device selection window")
            }
            
            Section("Display Control") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Screen off delay:")
                        Spacer()
                        Text("\(Int(tempScreenDelay)) seconds")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $tempScreenDelay, in: 1...60, step: 1) {
                        Text("Screen off delay")
                    }
                    .onChange(of: tempScreenDelay) { _, newValue in
                        appState.updateScreenDelay(Int(newValue))
                    }
                    
                    Text("Time to wait before turning off the screen when the selected device is disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Test Screen Control") {
                        appState.testScreenControl()
                    }
                    .help("Turn the screen off for 1 second, then back on")
                    
                    Spacer()
                    
                    Text(appState.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            tempScreenDelay = Double(appState.screenOffDelay)
        }
        .padding()
    }
}

struct DeviceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    
    var filteredDevices: [USBDevice] {
        if searchText.isEmpty {
            return appState.connectedDevices
        } else {
            return appState.connectedDevices.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.deviceID.localizedCaseInsensitiveContains(searchText) ||
                device.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // TOP ZONE: Currently Selected Device
            VStack(alignment: .leading, spacing: 0) {
                GroupBox("Currently Selected Device") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selectedDevice = appState.selectedDevice {
                            HStack(spacing: 16) {
                                // Device icon
                                VStack {
                                    Image(systemName: "usb")
                                        .font(.largeTitle)
                                        .foregroundColor(selectedDevice.isConnected ? .blue : .gray)
                                        .frame(width: 60, height: 60)
                                        .background(
                                            Circle()
                                                .fill(selectedDevice.isConnected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                        )
                                }
                                
                                // Device information
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selectedDevice.displayName)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("Device ID: \(selectedDevice.deviceID)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    if !selectedDevice.vendorID.isEmpty || !selectedDevice.productID.isEmpty {
                                        Text("Vendor: \(selectedDevice.vendorID.uppercased()) • Product: \(selectedDevice.productID.uppercased())")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(selectedDevice.isConnected ? .green : .red)
                                            .frame(width: 10, height: 10)
                                        Text(selectedDevice.isConnected ? "Connected" : "Disconnected")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .fontWeight(.medium)
                                    }
                                }
                                
                                Spacer()
                                
                                // Status indicator
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title)
                                    Text("Active Device")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                        } else {
                            HStack {
                                VStack {
                                    Image(systemName: "usb")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                        .frame(width: 60, height: 60)
                                        .background(
                                            Circle()
                                                .fill(Color.gray.opacity(0.1))
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No device selected")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Select a device from the list below to start monitoring")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            
            Divider()
            
            // BOTTOM ZONE: Device Selection (Available USB Devices)
            VStack(alignment: .leading, spacing: 16) {
                // Header with title and refresh button
                HStack {
                    Text("Device Selection")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Refresh") {
                        appState.refreshDevices()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Filter bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Filter devices...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    Text("\(filteredDevices.count) device(s)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
                
                // Device list - fills remaining space
                if filteredDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: appState.connectedDevices.isEmpty ? "usb" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        if appState.connectedDevices.isEmpty {
                            Text("No USB devices found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Connect a USB device to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No devices match your filter")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Try adjusting your search terms")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredDevices) { device in
                                DeviceListRowView(
                                    device: device, 
                                    isSelected: appState.selectedDevice?.deviceID == device.deviceID
                                ) {
                                    appState.selectDevice(device)
                                }
                                
                                if device.id != filteredDevices.last?.id {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DeviceListRowView: View {
    let device: USBDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            VStack {
                Image(systemName: "usb")
                    .font(.title2)
                    .foregroundColor(device.isConnected ? .blue : .gray)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(device.isConnected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    )
            }
            
            // Device information
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(device.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(device.isConnected ? "Connected" : "Disconnected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Device ID: \(device.deviceID)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if !device.vendorID.isEmpty || !device.productID.isEmpty {
                    Text("Vendor: \(device.vendorID.uppercased()) • Product: \(device.productID.uppercased())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Selection indicator/button
            VStack {
                if isSelected {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("Selected")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                } else {
                    Button("Select Device") {
                        onSelect()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .frame(width: 120)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelected {
                onSelect()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("MonitorSwitch")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 2.1")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("SwiftUI Edition")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Automatically control your monitor based on USB device connections.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("© 2026 aerodomigue")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Link("GitHub", destination: URL(string: "https://github.com/aerodomigue/MonitorSwitch-macOnly")!)
                        .font(.caption)
                    
                    Link("Issues", destination: URL(string: "https://github.com/aerodomigue/MonitorSwitch-macOnly/issues")!)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}