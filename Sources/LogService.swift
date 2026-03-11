//
//  LogService.swift
//  MonitorSwitchUI
//
//  Centralized logging service that captures logs for display in the UI
//  and persists them to disk for crash diagnostics.
//

import Foundation
import Combine

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

final class LogService: ObservableObject, @unchecked Sendable {
    static let shared = LogService()

    @MainActor @Published private(set) var entries: [LogEntry] = []
    @MainActor @Published private(set) var lastCrashReport: String?

    private let lock = NSLock()
    private var buffer: [LogEntry] = []
    private var flushScheduled = false
    private static let maxEntries = 1000

    // File logging
    private var logFileHandle: FileHandle?
    private let logFilePath: String
    private static let maxLogFileSize: UInt64 = 500_000 // 500KB
    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // Raw file descriptor for signal-safe crash writing
    nonisolated(unsafe) static var crashFileDescriptor: Int32 = -1

    private init() {
        let logsDir = NSHomeDirectory() + "/Library/Logs/MonitorSwitch"
        logFilePath = logsDir + "/monitor.log"

        // Create directory
        try? FileManager.default.createDirectory(
            atPath: logsDir, withIntermediateDirectories: true)

        // Create file if needed
        if !FileManager.default.fileExists(atPath: logFilePath) {
            FileManager.default.createFile(atPath: logFilePath, contents: nil)
        }

        // Open for appending
        logFileHandle = FileHandle(forWritingAtPath: logFilePath)
        logFileHandle?.seekToEndOfFile()

        if let fh = logFileHandle {
            Self.crashFileDescriptor = fh.fileDescriptor
        }

        checkForPreviousCrash()
        installCrashHandlers()
    }

    func log(_ message: String) {
        print(message)
        let entry = LogEntry(date: Date(), message: message)

        // Write to file immediately (crash-safe)
        writeToFile("[\(Self.fileDateFormatter.string(from: entry.date))] \(message)\n")

        // Batch to UI
        lock.lock()
        buffer.append(entry)
        let shouldSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()

        if shouldSchedule {
            DispatchQueue.main.async { [self] in self.flush() }
        }
    }

    @MainActor
    private func flush() {
        lock.lock()
        let pending = buffer
        buffer.removeAll(keepingCapacity: true)
        flushScheduled = false
        lock.unlock()

        guard !pending.isEmpty else { return }
        entries.append(contentsOf: pending)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    @MainActor
    func clear() {
        entries.removeAll()
    }

    @MainActor
    func dismissCrashReport() {
        lastCrashReport = nil
        // Remove [CRASH] markers from the log file so it won't re-appear on next launch
        DispatchQueue.global(qos: .utility).async { [logFilePath] in
            guard let content = try? String(contentsOfFile: logFilePath, encoding: .utf8) else { return }
            let cleaned = content.replacingOccurrences(of: "[CRASH]", with: "[CRASH-DISMISSED]")
            try? cleaned.write(toFile: logFilePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - File Logging

    private func writeToFile(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let fh = logFileHandle,
              let data = line.data(using: .utf8) else { return }
        fh.write(data)

        if fh.offsetInFile > Self.maxLogFileSize {
            rotateLogFile()
        }
    }

    private func rotateLogFile() {
        logFileHandle?.closeFile()
        logFileHandle = nil
        Self.crashFileDescriptor = -1

        let rotatedPath = logFilePath + ".1"
        try? FileManager.default.removeItem(atPath: rotatedPath)
        try? FileManager.default.moveItem(atPath: logFilePath, toPath: rotatedPath)

        FileManager.default.createFile(atPath: logFilePath, contents: nil)
        logFileHandle = FileHandle(forWritingAtPath: logFilePath)
        logFileHandle?.seekToEndOfFile()

        if let fh = logFileHandle {
            Self.crashFileDescriptor = fh.fileDescriptor
        }
    }

    // MARK: - Crash Handlers

    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let msg = "[CRASH] NSException: \(exception.name.rawValue) - \(exception.reason ?? "unknown")\n\(symbols)\n"
            let fd = LogService.crashFileDescriptor
            guard fd >= 0 else { return }
            if let data = msg.data(using: .utf8) {
                data.withUnsafeBytes { buf in
                    if let ptr = buf.baseAddress {
                        _ = Darwin.write(fd, ptr, data.count)
                    }
                }
            }
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig) { sigNum in
                let fd = LogService.crashFileDescriptor
                guard fd >= 0 else {
                    Darwin.signal(sigNum, SIG_DFL)
                    Darwin.raise(sigNum)
                    return
                }
                // Signal-safe: use stack buffer, no allocations
                var buf = Array<UInt8>(repeating: 0, count: 64)
                let prefix = Array("[CRASH] Signal ".utf8)
                let newline: UInt8 = 0x0A // '\n'
                var pos = 0
                for b in prefix { buf[pos] = b; pos += 1 }
                // Write signal number as ASCII digits
                var num = sigNum
                if num < 0 { num = 0 }
                var digits = [UInt8]()
                if num == 0 {
                    digits.append(0x30)
                } else {
                    var n = num
                    while n > 0 {
                        digits.append(UInt8(0x30 + n % 10))
                        n /= 10
                    }
                    digits.reverse()
                }
                for d in digits { buf[pos] = d; pos += 1 }
                buf[pos] = newline; pos += 1
                _ = Darwin.write(fd, &buf, pos)
                Darwin.signal(sigNum, SIG_DFL)
                Darwin.raise(sigNum)
            }
        }
    }

    // MARK: - Previous Crash Detection

    private func checkForPreviousCrash() {
        guard let content = try? String(contentsOfFile: logFilePath, encoding: .utf8),
              content.contains("[CRASH]") else { return }
        DispatchQueue.main.async { [self] in
            self.lastCrashReport = content
        }
    }
}
