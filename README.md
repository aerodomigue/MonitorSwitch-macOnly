# MonitorSwitch SwiftUI

A SwiftUI version of MonitorSwitch for macOS that automatically controls your monitor based on USB device connections.

## Features

- **Menu Bar App**: Runs quietly in your menu bar with quick access to controls
- **USB Device Monitoring**: Automatically detects USB device connections and disconnections
- **Smart Display Control**: Turns your monitor on/off based on selected device state
- **Customizable Settings**: Configure autostart, screen off delay, and startup behavior
- **Native macOS Integration**: Built with SwiftUI for modern macOS experience

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later

## Building

1. Navigate to the `monitorSwitchUI` directory:
   ```bash
   cd monitorSwitchUI
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```

3. The built app will be available in `.build/release/MonitorSwitch.app`

## Installation

1. Copy the built app to your Applications folder:
   ```bash
   cp -r .build/release/MonitorSwitch.app /Applications/
   ```

2. Launch the app and grant necessary permissions when prompted:
   - **USB Device Access**: Required to monitor USB connections
   - **Display Control**: Required to turn monitor on/off
   - **Accessibility**: May be required for some display control features

## Usage

1. **First Launch**: The app will appear in your menu bar with a display icon
2. **Select Device**: Click the menu bar icon and choose "Manage Devices" to select which USB device to monitor
3. **Configure Settings**: Access settings through the menu bar or use the Settings window
4. **Automatic Operation**: Once configured, the app will automatically:
   - Turn your monitor ON when the selected device connects
   - Turn your monitor OFF (after delay) when the selected device disconnects

## Configuration

The app stores settings using macOS UserDefaults. You can configure:

- **Selected USB Device**: Choose which device triggers monitor control
- **Autostart**: Launch automatically at login
- **Start Minimized**: Start without showing device selection window
- **Screen Off Delay**: Time to wait before turning off monitor (1-60 seconds)

## Architecture

The SwiftUI app is built with a clean architecture:

- **AppState**: Central state management with Combine publishers
- **Services**: Separate services for USB monitoring, display control, settings, and autostart
- **Views**: SwiftUI views for menu bar, device selection, and settings
- **Models**: Data models for USB devices and app configuration

## Key Services

- **USBService**: Monitors USB device connections using IOKit
- **DisplayService**: Controls monitor power using Core Graphics and IOKit
- **SettingsService**: Manages app configuration persistence
- **AutostartService**: Handles launch agent registration for autostart

## Permissions

The app requires the following permissions:
- USB device access (automatically granted)
- Display control (may require manual approval in System Preferences)
- Background app refresh (for monitoring while minimized)

## Troubleshooting

- **Monitor not turning off/on**: Check System Preferences > Security & Privacy > Privacy tab for accessibility permissions
- **USB devices not detected**: Ensure devices are properly connected and try refreshing the device list
- **Autostart not working**: Check System Preferences > Users & Groups > Login Items

## Differences from Qt Version

This SwiftUI version offers:
- Native macOS look and feel
- Better system integration
- Modern Swift/SwiftUI architecture
- Improved menu bar experience
- More robust USB device detection
- Better permission handling

## License

Same license as the original MonitorSwitch project.