import SwiftUI

/// Two separately installed, test-only apps share this source. All content is invented;
/// there are no accounts, network calls, external stores, permissions or write actions.
@main
struct ObservationFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if FixtureContent.invalidSeededContent {
                    ContentUnavailableView("Fixture data unavailable", systemImage: "exclamationmark.triangle",
                        description: Text("The supplied synthetic payload was invalid. No fallback content is substituted."))
                        .accessibilityIdentifier("benchmark.invalidContent")
                } else {
                    FixtureListView()
                        .navigationDestination(for: FixtureItem.self) { FixtureDetailView(item: $0) }
                }
            }
            .tint(FixtureContent.tint)
        }
    }
}

private struct FixtureItem: Identifiable, Hashable, Decodable {
    let index: Int
    let title: String
    let subtitle: String
    let preview: String
    var body: String? = nil
    var sourceID: String? = nil
    var sourceRevision: String? = nil
    var fields: [String: String]? = nil
    var id: String { String(format: "%02d", index) }
}

private struct SeededFixtureContent: Decodable {
    let schemaVersion: Int
    let generatorVersion: String
    let seed: String
    let messages: [FixtureItem]
    let events: [FixtureItem]

    var isValid: Bool {
        guard schemaVersion == 1, generatorVersion == "seeded-fixture-v1",
              seed.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil else { return false }
        return [("message", messages), ("event", events)].allSatisfy { kind, items in
            items.count == 30 && items.map(\.index) == Array(1...30) && items.allSatisfy { item in
                guard item.sourceID == "fixture.\(kind).\(item.id)",
                      let revision = item.sourceRevision,
                      revision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                      let fields = item.fields, let body = item.body,
                      fields["subject"] == item.title, fields["body"] == body,
                      fields.count <= 8 else { return false }
                let required = kind == "message" ? ["sender", "subject", "date", "time", "body"]
                    : ["subject", "date", "time", "endTime", "location", "reminder", "body"]
                return Set(fields.keys) == Set(required) && fields.values.allSatisfy { !$0.isEmpty && $0.count <= 500 }
                    && [item.title, item.subtitle, item.preview].allSatisfy { !$0.isEmpty && $0.count <= 500 }
            }
        }
    }
}

private enum FixtureContent {
    private static let rawContent = ProcessInfo.processInfo.environment["MO_OBSERVATION_FIXTURE_CONTENT"]
    private static let seeded: SeededFixtureContent? = {
        guard let rawContent, rawContent.utf8.count <= 200_000,
              let result = try? JSONDecoder().decode(SeededFixtureContent.self, from: Data(rawContent.utf8)),
              result.isValid,
              result.seed == ProcessInfo.processInfo.environment["MO_OBSERVATION_FIXTURE_SEED"] else { return nil }
        return result
    }()
    static var invalidSeededContent: Bool { rawContent != nil && seeded == nil }
    static let detailFieldOrder = ["sender", "date", "time", "endTime", "location", "reminder"]
    static func fieldLabel(_ field: String) -> String {
        ["sender": "From", "date": "Date", "time": "Time", "endTime": "Until",
         "location": "Place", "reminder": "Reminder"][field] ?? field
    }

    #if FIXTURE_INBOX
    static let title = "Cedar Mail"
    static let listTitle = "Inbox"
    static let detailKind = "Synthetic message"
    static let tint: Color = .indigo
    static let symbol = "envelope"
    static var items: [FixtureItem] { seeded?.messages ?? legacyItems }
    private static let legacyItems = (1...30).map { index in
        let subjects = ["Weekend garden plans", "A quiet reading afternoon", "Notes for the sketchbook",
                        "Saturday picnic ideas", "A walk by the river", "Library opening hours"]
        let senders = ["Juniper", "Maya", "Robin", "Alex", "Taylor", "Sam"]
        return FixtureItem(index: index, title: "\(subjects[(index - 1) % subjects.count]) · \(index)",
                           subtitle: "\(senders[(index - 1) % senders.count]) · Sample mail \(index)",
                           preview: "A small fictional note, saved here for a controlled screen observation.")
    }
    static func body(for item: FixtureItem) -> String {
        item.body ?? "Hello,\n\nThis is invented message \(item.id) in Cedar Mail. Let's bring a notebook on our next walk and sketch a tree beside the river. There is no account connected and no reply to send.\n\nHave a peaceful morning."
    }
    #elseif FIXTURE_CALENDAR
    static let title = "Lumen Calendar"
    static var listTitle: String { seeded == nil ? "Saturday agenda" : "Agenda" }
    static let detailKind = "Synthetic event"
    static let tint: Color = .teal
    static let symbol = "calendar"
    static var items: [FixtureItem] { seeded?.events ?? legacyItems }
    private static let legacyItems = (1...30).map { index in
        let subjects = ["Morning walk", "Reading hour", "Sketchbook time", "Garden break", "Quiet planning", "Tea by the window"]
        let minute = 7 * 60 + (index - 1) * 20
        let time = String(format: "%02d:%02d", minute / 60, minute % 60)
        return FixtureItem(index: index, title: "\(subjects[(index - 1) % subjects.count]) · \(index)",
                           subtitle: "\(time) · Sample event \(index)",
                           preview: "A fictional twenty-minute activity in this local demonstration agenda.")
    }
    static func body(for item: FixtureItem) -> String {
        item.body ?? "Event \(item.id) is a fictional entry for this observation benchmark.\n\nBring a notebook and take a quiet break. No calendar account is connected. This screen cannot create, edit or invite anyone to an event."
    }
    #else
    #error("Build this source only in a benchmark fixture target with FIXTURE_INBOX or FIXTURE_CALENDAR.")
    #endif
}

private struct FixtureHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: FixtureContent.symbol).accessibilityHidden(true)
                Text(FixtureContent.title).accessibilityIdentifier("benchmark.heading")
            }
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(FixtureContent.tint)
            Text("Benchmark fixture · Synthetic content only")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.vertical, 14)
    }
}

private struct FixtureListView: View {
    var body: some View {
        VStack(spacing: 0) {
            FixtureHeader()
            HStack {
                Text(FixtureContent.listTitle).font(.title2.bold())
                Spacer()
                Text("30 items").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(FixtureContent.items) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                Text(item.subtitle).font(.subheadline).foregroundStyle(FixtureContent.tint)
                                Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("benchmark.row.\(item.id)")
                        Divider().padding(.leading, 22)
                    }
                }
            }
            .accessibilityIdentifier("benchmark.list")
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FixtureDetailView: View {
    let item: FixtureItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FixtureHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(FixtureContent.detailKind) \(item.id)")
                        .font(.subheadline).foregroundStyle(FixtureContent.tint)
                        .accessibilityIdentifier("benchmark.detail.kind")
                    Text(item.title).font(.title2.bold())
                        .accessibilityIdentifier("benchmark.detail.title")
                    if let fields = item.fields {
                        ForEach(FixtureContent.detailFieldOrder, id: \.self) { field in
                            if let value = fields[field] {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(FixtureContent.fieldLabel(field)).foregroundStyle(.secondary)
                                        .frame(width: 76, alignment: .leading)
                                    Text(value).accessibilityIdentifier("benchmark.detail.\(field)")
                                }.font(.subheadline)
                            }
                        }
                    } else {
                        Text(item.subtitle).font(.headline).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(FixtureContent.body(for: item)).font(.body).lineSpacing(4)
                        .accessibilityIdentifier("benchmark.detail.body")
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("benchmark.detail")
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { dismiss() }
                    .accessibilityIdentifier("benchmark.back")
            }
        }
    }
}
