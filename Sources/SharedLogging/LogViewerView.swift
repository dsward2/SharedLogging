import SwiftUI

public struct LogViewerView: View {
    @State private var levelFilter: LogLevel?
    @State private var searchText = ""
    @State private var selection: LogEntry.ID?

    public init() {}

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var filteredEntries: [LogEntry] {
        LogStore.shared.entries.filter { entry in
            (levelFilter == nil || entry.level == levelFilter)
                && (searchText.isEmpty
                    || entry.message.localizedCaseInsensitiveContains(searchText)
                    || entry.source.localizedCaseInsensitiveContains(searchText))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Level", selection: $levelFilter) {
                    Text("All Levels").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(LogLevel?.some(level))
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Spacer()
                Button("Clear") {
                    LogStore.shared.clear()
                }
            }
            .padding()

            Table(filteredEntries, selection: $selection) {
                TableColumn("Time") { entry in
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 70)
                TableColumn("Level") { entry in
                    Text(entry.level.rawValue.uppercased())
                }
                .width(min: 60, ideal: 70)
                TableColumn("Source", value: \.source)
                    .width(min: 80, ideal: 120)
                TableColumn("Message", value: \.message)
            }
        }
        .navigationTitle("Logs")
        .frame(minWidth: 700, minHeight: 400)
    }
}
