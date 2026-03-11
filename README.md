# MonitorSwitch

A native macOS menu bar app that automatically switches monitor inputs (DDC-CI) when a USB device connects or disconnects. Ideal for KVM switch setups.

## Features

- **DDC-CI Input Switching** — Automatically change your monitor's input source via DDC-CI
- **Switch Modes** — Trigger on connect, disconnect, or both directions
- **Multi-Monitor Support** — Select which external monitor to control
- **Input Scanner** — Cycle through all inputs to find the right one
- **Instant USB Detection** — IOKit notifications for immediate response
- **Built-in Logging** — Real-time log viewer with disk persistence and crash detection
- **DDC Safety** — Serial queue with 5s timeout prevents I2C bus conflicts
- **Menu Bar App** — Runs quietly in your menu bar, no dock icon
- **Login Launch** — Optional auto-start at login

## Requirements

- macOS 14.0+
- Apple Silicon (DDC-CI uses IOAVService, arm64 only)
- Swift 6.0+ (for building from source)

## Install

```bash
git clone https://github.com/aerodomigue/MonitorSwitch-macOnly.git
cd MonitorSwitch-macOnly
./build.sh
cp -r .build/release/MonitorSwitch.app /Applications/
```

Since the app is unsigned, remove quarantine before launching:
```bash
xattr -cr /Applications/MonitorSwitch.app
```

## Usage

1. Launch the app — it appears in your menu bar
2. Click the menu bar icon to open the popover
3. Open **Settings** to configure:
   - **Device** — Select which USB device triggers input switching
   - **Monitor** — Pick the external monitor to control
   - **Input source** — Choose the DDC input (HDMI-1, DisplayPort-1, etc.) or use **Detect** / **Scan**
   - **Switch mode** — Connect only, disconnect only, or both (with separate inputs per direction)
4. Plug/unplug your USB device — the monitor input switches automatically

## Architecture

```
MonitorSwitchUIApp (entry point)
  → AppDelegate (menu bar setup)
    → AppState (central state container)
        ├── USBService     — IOKit notifications for USB device events
        ├── DDCService     — DDC-CI I2C commands (switchInput, readInput)
        ├── SettingsService — UserDefaults JSON persistence
        ├── AutostartService — SMAppService for login launch
        └── LogService     — Disk-persisted logging with crash detection
```

## License

Same license as the original [MonitorSwitch](https://github.com/aerodomigue/MonitorSwitch) project.
