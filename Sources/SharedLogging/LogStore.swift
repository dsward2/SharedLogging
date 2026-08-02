import Foundation
import Observation
import os

@MainActor
@Observable
public final class LogStore {
    public static let shared = LogStore()

    /// Entries stay capped at this count in memory; the file on disk is the
    /// real persistent history.
    nonisolated private static let maxInMemoryEntries = 2000

    /// The log file itself is trimmed to this many lines at `configure()`
    /// time so it doesn't grow unbounded across the app's lifetime.
    nonisolated private static let maxFileLines = 5000

    public private(set) var entries: [LogEntry] = []

    private var appName = "App"
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var osLogger: Logger?
    /// Lines logged before `configure()`'s background setup has finished
    /// resolving the container/file; flushed once the file handle is ready.
    private var pendingLines: [String] = []
    private let writeQueue = DispatchQueue(label: "com.dsward.antennahead.SharedLogging.write")

    private init() {}

    /// Call once at app launch. Resolves the shared App Group container,
    /// opens (creating if needed) `Logs/<appName>.log` for appending, and
    /// loads recent existing lines so the viewer shows history across
    /// launches. Falls back to Application Support if the App Group
    /// container can't be resolved (e.g. running unsigned outside the app
    /// bundle, such as `swift test`), so the package stays usable standalone.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` can take a
    /// long time to resolve the first time it's called from a process
    /// without the entitlement (observed ~35s from an unsigned `swift test`
    /// binary) — all of this work runs on a detached background task so a
    /// slow resolution never blocks the app's launch sequence. `log(_:_:_:)`
    /// keeps working immediately (in-memory) regardless; any lines logged
    /// before setup finishes are buffered and flushed to the file once it's
    /// ready.
    public func configure(appName: String, appGroupID: String = "group.com.dsward.antennahead") {
        self.appName = appName
        self.osLogger = Logger(subsystem: appName, category: "LogStore")

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let logsDirectory = Self.resolveLogsDirectory(appGroupID: appGroupID)
            try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

            let url = logsDirectory.appendingPathComponent("\(appName).log")
            Self.trimFileIfNeeded(at: url)
            let loadedEntries = Self.loadExistingEntries(from: url)

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()

            await self.finishConfiguring(url: url, handle: handle, loadedEntries: loadedEntries)
        }
    }

    private func finishConfiguring(url: URL, handle: FileHandle?, loadedEntries: [LogEntry]) {
        fileURL = url
        fileHandle = handle

        let merged = loadedEntries + entries
        entries = merged.count > Self.maxInMemoryEntries ? Array(merged.suffix(Self.maxInMemoryEntries)) : merged

        guard let handle, !pendingLines.isEmpty else { return }
        let combined = pendingLines.map { $0 + "\n" }.joined()
        pendingLines.removeAll()
        writeQueue.async {
            guard let data = combined.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    nonisolated private static func resolveLogsDirectory(appGroupID: String) -> URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent("Logs", isDirectory: true)
        }
        // Fallback for unsigned/standalone contexts (unit tests, `swift run`).
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("SharedLogging/Logs", isDirectory: true)
    }

    public func log(_ level: LogLevel, source: String, _ message: String) {
        let entry = LogEntry(level: level, source: source, message: message)
        entries.append(entry)
        if entries.count > Self.maxInMemoryEntries {
            entries.removeFirst(entries.count - Self.maxInMemoryEntries)
        }

        osLogger?.log(level: level.osLogType, "\(source, privacy: .public): \(message, privacy: .public)")

        let line = Self.formatLine(entry: entry)
        if let fileHandle {
            writeQueue.async {
                guard let data = (line + "\n").data(using: .utf8) else { return }
                fileHandle.write(data)
            }
        } else {
            pendingLines.append(line)
        }
    }

    public func clear() {
        entries.removeAll()
    }

    nonisolated private static func formatLine(entry: LogEntry) -> String {
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        return "\(timestamp) [\(entry.level.rawValue.uppercased())] \(entry.source): \(entry.message)"
    }

    nonisolated private static func loadExistingEntries(from url: URL) -> [LogEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let recent = lines.suffix(maxInMemoryEntries)
        return recent.map { line in
            parseLine(String(line))
        }
    }

    nonisolated private static func parseLine(_ line: String) -> LogEntry {
        // Best-effort parse of "<timestamp> [<LEVEL>] <source>: <message>";
        // falls back to a plain info entry if the format doesn't match
        // (e.g. a line written before this format existed).
        guard let openBracket = line.firstIndex(of: "["),
              let closeBracket = line[openBracket...].firstIndex(of: "]") else {
            return LogEntry(level: .info, source: "log", message: line)
        }
        let timestampString = line[line.startIndex..<openBracket].trimmingCharacters(in: .whitespaces)
        let levelString = line[line.index(after: openBracket)..<closeBracket].lowercased()
        let rest = line[line.index(after: closeBracket)...].trimmingCharacters(in: .whitespaces)

        let level = LogLevel(rawValue: levelString) ?? .info
        let timestamp = ISO8601DateFormatter().date(from: timestampString) ?? Date()

        guard let colonRange = rest.range(of: ": ") else {
            return LogEntry(timestamp: timestamp, level: level, source: "log", message: rest)
        }
        let source = String(rest[rest.startIndex..<colonRange.lowerBound])
        let message = String(rest[colonRange.upperBound...])
        return LogEntry(timestamp: timestamp, level: level, source: source, message: message)
    }

    nonisolated private static func trimFileIfNeeded(at url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxFileLines else { return }
        let trimmed = lines.suffix(maxFileLines).joined(separator: "\n") + "\n"
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .error
        case .error: return .fault
        }
    }
}
