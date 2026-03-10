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
    @State private var isCustomInput: Bool = false
    @State private var customHexString: String = ""

    private var isKnownInput: Bool {
        DDCService.knownInputs[appState.monitorInputSource] != nil
    }

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

            Section("Monitor Input (DDC-CI)") {
                VStack(alignment: .leading, spacing: 12) {
                    #if arch(arm64)
                    HStack {
                        Text("Target monitor:")
                        Picker("", selection: Binding(
                            get: { appState.selectedMonitorID },
                            set: { appState.updateSelectedMonitorID($0) }
                        )) {
                            Text("Auto (first found)").tag("")
                            ForEach(appState.availableMonitors) { monitor in
                                Text(monitor.name).tag(monitor.id)
                            }
                        }
                        .frame(width: 250)

                        Button(action: { appState.refreshMonitors() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh the list of external monitors")
                    }
                    #endif

                    HStack {
                        Text("Target input:")
                        // Use Int16 so we can represent known values + a sentinel for "Custom"
                        let customSentinel: Int16 = -1
                        Picker("", selection: Binding<Int16>(
                            get: {
                                if isCustomInput || !isKnownInput {
                                    return customSentinel
                                }
                                return Int16(appState.monitorInputSource)
                            },
                            set: { newValue in
                                if newValue == customSentinel {
                                    isCustomInput = true
                                    customHexString = String(format: "%02X", appState.monitorInputSource)
                                } else {
                                    isCustomInput = false
                                    appState.updateMonitorInputSource(UInt8(newValue))
                                }
                            }
                        )) {
                            ForEach(DDCService.sortedInputs, id: \.value) { input in
                                Text("\(input.name)  (0x\(String(format: "%02X", input.value)))")
                                    .tag(Int16(input.value))
                            }
                            Divider()
                            Text("Custom…").tag(customSentinel)
                        }
                        .frame(width: 220)
                    }
                    .onAppear {
                        if !isKnownInput {
                            isCustomInput = true
                            customHexString = String(format: "%02X", appState.monitorInputSource)
                        }
                    }

                    if isCustomInput || !isKnownInput {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Custom input value:  0x")
                                .foregroundColor(.secondary)
                            TextField("", text: $customHexString)
                                .frame(width: 20)
                                .padding(4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                                .onSubmit {
                                    if let val = UInt8(customHexString, radix: 16) {
                                        appState.updateMonitorInputSource(val)
                                    }
                                }
                                .onChange(of: customHexString) { _, newValue in
                                    let filtered = String(newValue.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(3))
                                    if filtered != customHexString {
                                        customHexString = filtered
                                    }
                                    if let val = UInt8(filtered, radix: 16) {
                                        appState.updateMonitorInputSource(val)
                                    }
                                }
                        }
                    }

                    if let detected = appState.currentDetectedInput {
                        HStack {
                            Text("Last detected:")
                            Spacer()
                            Text(DDCService.inputName(for: detected))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Detect Current Input") {
                            appState.detectCurrentInput()
                        }
                        .help("Read the active video input from the monitor via DDC-CI and save it as the target input")

                        Button("Test Input Switch") {
                            appState.testInputSwitch()
                        }
                        .help("Send a DDC-CI command to switch the monitor to the configured input")

                        Button("Scan Inputs") {
                            appState.scanInputs()
                        }
                        .help("Cycle through all inputs so you can identify which one your Mac is connected to")

                        Spacer()

                        Text(appState.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .sheet(isPresented: $appState.isScanning, onDismiss: {
                        appState.stopScanningInputs()
                    }) {
                        InputScannerSheet()
                            .environmentObject(appState)
                    }

                    Text("Select the input your Mac is connected to, or press Detect to read it from the monitor. When your USB device connects, the monitor will automatically switch to this input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
                
                Text("Version 2.2")
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

struct InputScannerSheet: View {
    @EnvironmentObject var appState: AppState

    private var inputs: [MonitorInput] { DDCService.sortedInputs }

    var body: some View {
        VStack(spacing: 24) {
            Text("Scanning Inputs")
                .font(.title2)
                .fontWeight(.semibold)

            if appState.scanningInputIndex < inputs.count {
                let current = inputs[appState.scanningInputIndex]
                VStack(spacing: 8) {
                    Text(current.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("\(appState.scanningInputIndex + 1) of \(inputs.count)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }

            Text("When your Mac's screen appears, click \"Use This Input\".")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Use This Input") {
                    appState.confirmScannedInput()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Stop Scanning") {
                    appState.stopScanningInputs()
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}