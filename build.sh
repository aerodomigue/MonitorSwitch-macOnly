#!/bin/bash

# Build script for MonitorSwitchUI
# This script builds the SwiftUI app for macOS

set -e

echo "Building MonitorSwitchUI..."

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf .build/release

# Build the Swift package
echo "Building Swift package..."
swift build --configuration release

# Create app bundle structure
APP_NAME="MonitorSwitch.app"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/MonitorSwitchUI" "$APP_DIR/Contents/MacOS/"

# Copy Info.plist
cp "Info.plist" "$APP_DIR/Contents/"

# Copy icon if available
if [ -f "icons/MonitorSwitch.icns" ]; then
    echo "Copying app icon..."
    cp "icons/MonitorSwitch.icns" "$APP_DIR/Contents/Resources/"
else
    echo "Warning: App icon not found at icons/MonitorSwitch.icns"
fi

# Set executable permissions
chmod +x "$APP_DIR/Contents/MacOS/MonitorSwitchUI"

echo "Build complete! App bundle created at: $APP_DIR"
echo ""
echo "To install the app:"
echo "1. Copy $APP_DIR to /Applications/"
echo "2. Grant necessary permissions in System Preferences > Security & Privacy"
echo ""
echo "To run directly:"
echo "./$APP_DIR/Contents/MacOS/MonitorSwitchUI"