import SwiftUI

struct AltitudePriorityMenuRow: Equatable, Identifiable {
    let role: String
    let sessionName: String
    let state: String
    let detail: String

    var id: String { role }
}

struct AltitudeMenuArrival: Equatable {
    enum Kind: Equatable {
        case finished
        case needsYou
    }

    let kind: Kind
    let sessionName: String
    let oldestWaitingSessionName: String?
    let oldestWaitSeconds: Int?
}

struct AltitudeMenuInteractionState: Equatable {
    var isPresented = false
    var selectedItemID: String?
    var arrival: AltitudeMenuArrival?
    var previousSnapshot: AltitudeNextUpSnapshot?
    var quietSince = Date()

    mutating func open(snapshot: AltitudeNextUpSnapshot, now: Date = Date()) {
        let items = AltitudeMenuPresentation.needsYouItems(snapshot: snapshot)
        arrival = previousSnapshot.flatMap {
            AltitudeMenuPresentation.arrival(previous: $0, current: snapshot)
        }
        previousSnapshot = snapshot
        selectedItemID = items.first?.sessionId
        isPresented = true
        if !items.isEmpty { quietSince = now }
    }

    mutating func dismiss() {
        isPresented = false
        selectedItemID = nil
    }

    mutating func update(
        snapshot: AltitudeNextUpSnapshot,
        previous: AltitudeNextUpSnapshot,
        now: Date = Date()
    ) {
        let items = AltitudeMenuPresentation.needsYouItems(snapshot: snapshot)
        if !items.isEmpty || !AltitudeMenuPresentation.needsYouItems(snapshot: previous).isEmpty {
            quietSince = now
        }
        guard isPresented else { return }
        if !items.contains(where: { $0.sessionId == selectedItemID }) {
            selectedItemID = items.first?.sessionId
        }
    }
}

enum AltitudeMenuPresentation {
    static let targetPaneOffset = 2

    static func targetPaneIndex(paneCount: Int) -> Int? {
        guard paneCount > 0 else { return nil }
        return min(targetPaneOffset, paneCount - 1)
    }

    static func isPrincipalMain(_ item: AltitudeNextUpItem) -> Bool {
        [item.sessionId, item.jumpSessionId, item.tmuxSession]
            .compactMap { $0?.lowercased() }
            .contains(where: { $0.contains("-main-") })
    }

    static func needsYouItems(snapshot: AltitudeNextUpSnapshot) -> [AltitudeNextUpItem] {
        snapshot.items.filter { !isPrincipalMain($0) }
    }

    static func sessionName(for item: AltitudeNextUpItem) -> String {
        item.tmuxSession ?? item.jumpSessionId ?? item.sessionId
    }

    static func oldestWaitingID(in items: [AltitudeNextUpItem]) -> String? {
        items.max(by: { $0.waitSeconds < $1.waitSeconds })?.sessionId
    }

    static func movedSelection(
        currentID: String?,
        delta: Int,
        items: [AltitudeNextUpItem]
    ) -> String? {
        guard !items.isEmpty else { return nil }
        guard let currentIndex = currentID.flatMap({ id in
            items.firstIndex(where: { $0.sessionId == id })
        }) else {
            return delta >= 0 ? items.first?.sessionId : items.last?.sessionId
        }
        let count = items.count
        return items[(currentIndex + delta % count + count) % count].sessionId
    }

    static func arrival(
        previous: AltitudeNextUpSnapshot,
        current: AltitudeNextUpSnapshot
    ) -> AltitudeMenuArrival? {
        let previousItems = needsYouItems(snapshot: previous)
        let currentItems = needsYouItems(snapshot: current)
        let currentIDs = Set(currentItems.map(\.sessionId))
        let previousIDs = Set(previousItems.map(\.sessionId))
        let oldest = currentItems.max(by: { $0.waitSeconds < $1.waitSeconds })

        if let finished = previousItems.first(where: { !currentIDs.contains($0.sessionId) }) {
            return AltitudeMenuArrival(
                kind: .finished,
                sessionName: sessionName(for: finished),
                oldestWaitingSessionName: oldest.map { sessionName(for: $0) },
                oldestWaitSeconds: oldest?.waitSeconds
            )
        }
        if let arrived = currentItems.first(where: { !previousIDs.contains($0.sessionId) }) {
            return AltitudeMenuArrival(
                kind: .needsYou,
                sessionName: sessionName(for: arrived),
                oldestWaitingSessionName: oldest.map { sessionName(for: $0) },
                oldestWaitSeconds: oldest?.waitSeconds
            )
        }
        return nil
    }
}

struct AltitudeMenuView: View {
    let snapshot: AltitudeNextUpSnapshot
    let priorityRows: [AltitudePriorityMenuRow]
    let selectedItemID: String?
    let arrival: AltitudeMenuArrival?
    let quietSeconds: Int
    let errorMessage: String?
    let onSelectionChange: (String) -> Void
    let onJump: (AltitudeNextUpItem) -> Void

    private let amber = Color(red: 1.0, green: 0.74, blue: 0.12)
    private let cyan = Color(red: 0.28, green: 0.82, blue: 0.88)
    private let green = Color(red: 0.48, green: 0.83, blue: 0.49)
    private let menuBackground = Color(red: 0.047, green: 0.047, blue: 0.051)
    private let rule = Color.white.opacity(0.18)

    private var items: [AltitudeNextUpItem] {
        AltitudeMenuPresentation.needsYouItems(snapshot: snapshot)
    }

    private var oldestWaitingID: String? {
        AltitudeMenuPresentation.oldestWaitingID(in: items)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                header(date: timeline.date)
                Divider().overlay(rule)
                prioritySection
                Divider().overlay(rule)
                if items.isEmpty { emptyState } else { needsYouSection }
                Spacer(minLength: 16)
                Divider().overlay(rule)
                processingSection
                Spacer(minLength: 8)
                footer
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(menuBackground)
            .foregroundStyle(Color.white.opacity(0.9))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
        }
    }

    private func header(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(String(localized: "altitude.menu.title", defaultValue: "ALTITUDE"))
                    .fontWeight(.semibold)
                Text(String(localized: "altitude.menu.label", defaultValue: "menu"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                Text("· ⌘0").foregroundStyle(.tertiary)
            }
            if let arrival {
                Text(arrivalText(arrival))
                    .foregroundStyle(cyan.opacity(0.9))
                    .lineLimit(2)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(amber).lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(priorityRows) { row in
                HStack(spacing: 6) {
                    Text(row.role).foregroundStyle(amber).fontWeight(.semibold)
                    Text(row.sessionName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(row.state).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(row.detail).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private var needsYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "altitude.menu.needsYou", defaultValue: "NEEDS YOU"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)").foregroundStyle(.tertiary)
            }
            .padding(.top, 14)
            ForEach(items) { item in
                needsYouRow(item)
                    .onHover { if $0 { onSelectionChange(item.sessionId) } }
                    .onTapGesture { onJump(item) }
            }
        }
    }

    private func needsYouRow(_ item: AltitudeNextUpItem) -> some View {
        let selected = selectedItemID == item.sessionId
        let isOldest = oldestWaitingID == item.sessionId
        return VStack(alignment: .leading, spacing: selected ? 6 : 3) {
            HStack(spacing: 8) {
                Text(AltitudeMenuPresentation.sessionName(for: item))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(waitLabel(item.waitSeconds))
                    .foregroundStyle(isOldest ? amber : Color.secondary)
                    .fontWeight(isOldest ? .semibold : .regular)
            }
            Text(item.why.line)
                .foregroundStyle(selected ? cyan.opacity(0.85) : Color.secondary)
                .lineLimit(selected ? 3 : 1)
                .padding(.leading, selected ? 14 : 0)
            if selected {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(localized: "altitude.menu.needs", defaultValue: "needs"))
                        .foregroundStyle(.tertiary)
                    Text(item.why.label).foregroundStyle(Color.white.opacity(0.78))
                    Spacer()
                    Text(waitLabel(item.waitSeconds)).foregroundStyle(.tertiary)
                }
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, selected ? 7 : 4)
        .background(selected ? Color(red: 0.10, green: 0.15, blue: 0.20) : Color.clear)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(String(localized: "altitude.menu.empty.title", defaultValue: "nothing needs you"))
                .foregroundStyle(green)
                .fontWeight(.semibold)
            Text(String(
                format: String(
                    localized: "altitude.menu.empty.summary",
                    defaultValue: "%lld processing · quietest in %@"
                ),
                Int64(snapshot.processingCount),
                durationLabel(quietSeconds)
            ))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(
                format: String(localized: "altitude.menu.processing", defaultValue: "PROCESSING · %lld"),
                Int64(snapshot.processingCount)
            ))
            .foregroundStyle(.tertiary)
            ForEach(snapshot.processing.prefix(5)) { item in
                HStack {
                    Text(item.sessionName).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(String(localized: "altitude.menu.working", defaultValue: "working"))
                }
                .foregroundStyle(Color.white.opacity(0.24))
                .padding(.leading, 14)
            }
            if snapshot.processing.count > 5 {
                Text(String(
                    format: String(localized: "altitude.menu.moreProcessing", defaultValue: "… %lld more"),
                    Int64(snapshot.processing.count - 5)
                ))
                .foregroundStyle(Color.white.opacity(0.20))
                .padding(.leading, 14)
            }
        }
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("↑↓")
            Text(String(localized: "altitude.menu.footer.move", defaultValue: "move"))
            Text("· ↩")
            Text(String(localized: "altitude.menu.footer.open", defaultValue: "open"))
            Text("· esc")
            Text(String(localized: "altitude.menu.footer.back", defaultValue: "back"))
            Spacer()
            Text("⌘1 1A · ⌘2 1B")
        }
        .foregroundStyle(.tertiary)
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .padding(.top, 5)
    }

    private func arrivalText(_ arrival: AltitudeMenuArrival) -> String {
        let change: String
        switch arrival.kind {
        case .finished:
            change = String(
                format: String(localized: "altitude.menu.arrival.finished", defaultValue: "%@ finished"),
                arrival.sessionName
            )
        case .needsYou:
            change = String(
                format: String(localized: "altitude.menu.arrival.needsYou", defaultValue: "%@ needs you"),
                arrival.sessionName
            )
        }
        guard let waiting = arrival.oldestWaitingSessionName,
              let seconds = arrival.oldestWaitSeconds else { return change }
        return String(
            format: String(
                localized: "altitude.menu.arrival.withWait",
                defaultValue: "%@ · %@ has been waiting %@"
            ),
            change,
            waiting,
            durationLabel(seconds)
        )
    }

    private func waitLabel(_ seconds: Int) -> String {
        String(
            format: String(localized: "altitude.menu.waiting", defaultValue: "waiting %@"),
            durationLabel(seconds)
        )
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return String(localized: "altitude.wait.now", defaultValue: "now") }
        if seconds < 3_600 { return "\(max(1, seconds / 60))m" }
        return "\(max(1, seconds / 3_600))h"
    }
}
