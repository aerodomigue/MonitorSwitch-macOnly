//
//  USBDevice.swift
//  MonitorSwitchUI
//
//  USB Device data model
//

import Foundation

struct USBDevice: Identifiable, Hashable, Codable {
    let id = UUID()
    let deviceID: String
    let name: String
    let vendorID: String
    let productID: String
    var isConnected: Bool
    
    private enum CodingKeys: String, CodingKey {
        case deviceID, name, vendorID, productID, isConnected
    }
    
    init(deviceID: String, name: String, vendorID: String, productID: String, isConnected: Bool = true) {
        self.deviceID = deviceID
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.isConnected = isConnected
    }
    
    var displayName: String {
        if name.isEmpty {
            return "Unknown Device (\(vendorID):\(productID))"
        }
        return name
    }

    /// Stable identifier based on vendorID:productID only (without locationID)
    /// Used for matching devices that may reconnect on different ports (e.g., KVM switches)
    var stableID: String {
        "\(vendorID):\(productID)"
    }
    
    static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
        lhs.deviceID == rhs.deviceID
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(deviceID)
    }
}