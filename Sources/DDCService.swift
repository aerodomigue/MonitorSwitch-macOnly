//
//  DDCService.swift
//  MonitorSwitchUI
//
//  DDC-CI service for monitor input switching via IOKit I2C
//

import Foundation
#if arch(arm64)
import CoreGraphics
import AppleSiliconDDC
import AppleSiliconDDCObjC
#else
import CDDCBridge
#endif

// VCP code for Input Source Select
private let kVCPInputSource: UInt8 = 0x60

struct MonitorInput {
    let value: UInt8
    let name: String
}

#if arch(arm64)
struct ExternalMonitor: Identifiable, @unchecked Sendable {
    let id: String          // "productName:serviceLocation" e.g. "MSI G274QPF-QD:1"
    let name: String        // productName e.g. "MSI G274QPF-QD"
    let service: IOAVService
}
#endif

/// DDC-CI service — all methods perform blocking I2C hardware I/O
/// and MUST be called off the main thread.
final class DDCService: Sendable {
    // Known input source names for display purposes
    static let knownInputs: [UInt8: String] = [
        0x01: "VGA-1",
        0x02: "VGA-2",
        0x03: "DVI-1",
        0x04: "DVI-2",
        0x0F: "DisplayPort-1",
        0x10: "DisplayPort-2",
        0x11: "HDMI-1",
        0x12: "HDMI-2",
        0x13: "HDMI-3",
    ]

    static let sortedInputs: [MonitorInput] = knownInputs
        .sorted { $0.key < $1.key }
        .map { MonitorInput(value: $0.key, name: $0.value) }

    static func inputName(for value: UInt8) -> String {
        knownInputs[value] ?? String(format: "Input 0x%02X", value)
    }

    #if arch(arm64)
    /// List all external monitors with IOAVService available
    func listExternalMonitors() -> [ExternalMonitor] {
        let services = AppleSiliconDDC.getIoregServicesForMatching()
        return services.compactMap { match in
            guard let service = match.service else { return nil }
            let id = "\(match.productName):\(match.location)"
            LogService.shared.log("DDCService: found monitor — \(match.productName) at location \(match.location)")
            return ExternalMonitor(id: id, name: match.productName, service: service)
        }
    }

    /// Find the IOAVService for a specific or first external display
    private func findExternalService(monitorID: String? = nil) -> IOAVService? {
        let monitors = listExternalMonitors()
        guard !monitors.isEmpty else {
            LogService.shared.log("DDCService: no IOAVService found via AppleSiliconDDC")
            return nil
        }

        let match: ExternalMonitor?
        if let monitorID, !monitorID.isEmpty {
            match = monitors.first(where: { $0.id == monitorID })
            if match == nil {
                LogService.shared.log("DDCService: monitor '\(monitorID)' not found, aborting")
                return nil
            }
        } else {
            match = monitors.first
        }

        guard let match else { return nil }
        LogService.shared.log("DDCService: using monitor — \(match.name) (id: \(match.id))")
        return match.service
    }
    #endif

    /// Switch the monitor to the specified input source via DDC-CI Set VCP 0x60
    func switchInput(to input: UInt8, monitorID: String? = nil) -> Bool {
        LogService.shared.log("DDCService: switching to input \(DDCService.inputName(for: input)) (0x\(String(input, radix: 16)))")

        #if arch(arm64)
        let maxAttempts = 3
        let baseDelayMs: UInt32 = 100

        for attempt in 1...maxAttempts {
            if let service = findExternalService(monitorID: monitorID) {
                let success = AppleSiliconDDC.write(service: service, command: kVCPInputSource, value: UInt16(input))
                if success {
                    LogService.shared.log("DDCService: input switch successful")
                    return true
                }
                LogService.shared.log("DDCService: write failed (attempt \(attempt)/\(maxAttempts))")
            } else {
                LogService.shared.log("DDCService: no service found (attempt \(attempt)/\(maxAttempts))")
            }

            if attempt < maxAttempts {
                let delayMs = baseDelayMs * UInt32(pow(4.0, Double(attempt - 1)))
                LogService.shared.log("DDCService: retrying in \(delayMs)ms...")
                usleep(UInt32(delayMs) * 1000)
            }
        }

        LogService.shared.log("DDCService: input switch failed after \(maxAttempts) attempts")
        return false
        #else
        let success = ddc_i2c_write(kVCPInputSource, input)
        if success {
            LogService.shared.log("DDCService: input switch successful")
        } else {
            LogService.shared.log("DDCService: input switch failed")
        }
        return success
        #endif
    }

    /// Read the current input source via DDC-CI Get VCP 0x60.
    /// Note: some monitors (e.g. LG UltraGear) support DDC writes but not reads.
    func readCurrentInput(monitorID: String? = nil) -> UInt8? {
        LogService.shared.log("DDCService: reading current input...")

        #if arch(arm64)
        guard let service = findExternalService(monitorID: monitorID) else {
            LogService.shared.log("DDCService: failed to read — no service")
            return nil
        }
        guard let result = AppleSiliconDDC.read(service: service, command: kVCPInputSource, readSleepTime: 100_000, numOfRetryAttemps: 9) else {
            LogService.shared.log("DDCService: failed to read current input (monitor may not support DDC reads)")
            return nil
        }
        let currentValue = UInt8(result.current & 0xFF)
        LogService.shared.log("DDCService: current input = \(DDCService.inputName(for: currentValue)) (0x\(String(currentValue, radix: 16)))")
        return currentValue
        #else
        let result = ddc_i2c_read(kVCPInputSource)
        if result.success {
            LogService.shared.log("DDCService: current input = \(DDCService.inputName(for: result.currentValue)) (0x\(String(result.currentValue, radix: 16)))")
            return result.currentValue
        } else {
            LogService.shared.log("DDCService: failed to read current input")
            return nil
        }
        #endif
    }
}
