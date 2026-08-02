import Foundation

public struct LogEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let source: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, source: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
    }
}
