//
//  Logger.swift
//  VNTM Gamepad
//
//  Thin wrapper over os.Logger plus an in-memory ring buffer so the
//  diagnostics screen can show the last few hundred events without Xcode.
//

import Foundation
import os

enum LogCategory: String, CaseIterable {
    case app = "App"
    case bluetooth = "Bluetooth"
    case wifi = "Wi-Fi"
    case network = "Network"
    case input = "Input"
    case packet = "Packet"
    case haptics = "Haptics"
    case motion = "Motion"
    case profile = "Profile"
    case connection = "Connection"
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let category: LogCategory
    let message: String
    let isError: Bool

    var timeString: String {
        LogEntry.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

/// Observable buffer rendered by the diagnostics screen.
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    private let lock = NSLock()
    private let maxEntries = 250

    private init() {}

    func append(_ entry: LogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

/// Category-based wrapper around os.Logger.
enum AppLogger {
    private static let bundleId = AppConstants.bundleId

    private static let categoryLoggers: [String: os.Logger] = [
        "App": os.Logger(subsystem: bundleId, category: "App"),
        "Bluetooth": os.Logger(subsystem: bundleId, category: "Bluetooth"),
        "Wi-Fi": os.Logger(subsystem: bundleId, category: "Wi-Fi"),
        "Network": os.Logger(subsystem: bundleId, category: "Network"),
        "Input": os.Logger(subsystem: bundleId, category: "Input"),
        "Packet": os.Logger(subsystem: bundleId, category: "Packet"),
        "Haptics": os.Logger(subsystem: bundleId, category: "Haptics"),
        "Motion": os.Logger(subsystem: bundleId, category: "Motion"),
        "Profile": os.Logger(subsystem: bundleId, category: "Profile"),
        "Connection": os.Logger(subsystem: bundleId, category: "Connection")
    ]

    private static func logger(for category: String) -> os.Logger {
        categoryLoggers[category] ?? os.Logger(subsystem: bundleId, category: category)
    }

    // MARK: - General Logging Methods

    static func info(_ message: String, category: String = "App") {
        logger(for: category).info("\(message, privacy: .public)")
        recordEntry(message: message, categoryName: category, isError: false)
    }

    static func debug(_ message: String, category: String = "App") {
        logger(for: category).debug("\(message, privacy: .public)")
        recordEntry(message: message, categoryName: category, isError: false)
    }

    static func warning(_ message: String, category: String = "App") {
        logger(for: category).warning("\(message, privacy: .public)")
        recordEntry(message: message, categoryName: category, isError: false)
    }

    static func error(_ message: String, category: String = "App") {
        logger(for: category).error("\(message, privacy: .public)")
        recordEntry(message: message, categoryName: category, isError: true)
    }

    // MARK: - Specialized Category Methods

    static func network(_ message: String) {
        info(message, category: "Network")
    }

    static func bluetooth(_ message: String) {
        info(message, category: "Bluetooth")
    }

    static func haptics(_ message: String) {
        info(message, category: "Haptics")
    }

    // MARK: - LogCategory Overloads

    static func info(_ message: String, category: LogCategory) {
        info(message, category: category.rawValue)
    }

    static func debug(_ message: String, category: LogCategory) {
        debug(message, category: category.rawValue)
    }

    static func warning(_ message: String, category: LogCategory) {
        warning(message, category: category.rawValue)
    }

    static func error(_ message: String, category: LogCategory) {
        error(message, category: category.rawValue)
    }

    // MARK: - Internal Recording

    private static func recordEntry(message: String, categoryName: String, isError: Bool) {
        let cat = LogCategory(rawValue: categoryName) ?? .app
        let entry = LogEntry(date: Date(), category: cat, message: message, isError: isError)
        DispatchQueue.main.async {
            LogStore.shared.append(entry)
        }
    }
}

// Backward compatibility alias
typealias AppLog = AppLogger
