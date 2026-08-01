import SwiftUI

struct AltitudeNextUpStrip: View {
    let snapshot: AltitudeNextUpSnapshot
    let configuration: AltitudeConfiguration
    let errorMessage: String?
    let onGo: (AltitudeNextUpItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .cmuxFont(size: 10, weight: .medium)
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
            }
            presenceLines
            HStack(spacing: 6) {
                if snapshot.items.isEmpty, errorMessage == nil {
                    Text(
                        String(
                            format: String(localized: "altitude.strip.empty", defaultValue: "nothing waiting · %lld processing"),
                            Int64(snapshot.processingCount)
                        )
                    )
                        .cmuxFont(size: 11, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                } else if snapshot.items.isEmpty {
                    Text(String(localized: "altitude.strip.unavailable", defaultValue: "queue unavailable"))
                        .cmuxFont(size: 11, weight: .medium)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                } else {
                    ForEach(Array(snapshot.items.prefix(3).enumerated()), id: \.element.id) { index, item in
                        Button {
                            onGo(item)
                        } label: {
                            itemLabel(item, index: index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(
                                format: String(localized: "altitude.strip.go.accessibility", defaultValue: "Go to %@, %@"),
                                item.agentName,
                                item.why.line
                            )
                        )
                    }
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var presenceLines: some View {
        ForEach(snapshot.items.filter { $0.priority == "1A" || $0.priority == "1B" }.prefix(2)) { item in
            let stage = AltitudePresenceStage.resolve(
                waitSeconds: item.waitSeconds,
                priority: item.priority,
                configuration: configuration
            )
            HStack(spacing: 6) {
                if stage == .pulse {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(item.priority ?? "")
                            .cmuxFont(size: 10, weight: .bold)
                            .foregroundStyle(Color.orange)
                            .opacity(Int(context.date.timeIntervalSince1970 / 60).isMultiple(of: 2) ? 1 : 0.45)
                            .animation(.easeInOut(duration: 0.8), value: context.date)
                    }
                } else {
                    Text(item.priority ?? "")
                        .cmuxFont(size: 10, weight: .bold)
                        .foregroundStyle(stage >= .bright ? Color.orange : Color.secondary)
                }
                Text(stage >= .bright ? formattedWait(item.waitSeconds) : String(localized: "altitude.presence.ready", defaultValue: "ready"))
                    .cmuxFont(size: 10, weight: .medium)
                    .foregroundStyle(stage >= .bright ? Color.primary : Color.secondary)
            }
        }
    }

    private func itemLabel(_ item: AltitudeNextUpItem, index: Int) -> some View {
        let shortcut = index == 0 ? "⌥↩" : "⌥\(index + 1)"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let priority = item.priority {
                    Text(priority)
                        .cmuxFont(size: 9, weight: .bold)
                        .foregroundStyle(.orange)
                }
                Text(item.agentName)
                    .cmuxFont(size: 11, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(shortcut)
                    .cmuxFont(size: 9, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            Text(item.why.line)
                .cmuxFont(size: 10, weight: .regular)
                .foregroundStyle(item.classification == "uncertain" ? Color.orange : Color.secondary)
                .lineLimit(1)
            Text(formattedWait(item.waitSeconds))
                .cmuxFont(size: 9, weight: .medium)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(index == 0 ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func formattedWait(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(localized: "altitude.wait.now", defaultValue: "now")
        }
        let minutes = max(1, seconds / 60)
        return String(
            format: String(localized: "altitude.wait.minutes", defaultValue: "%lldm waiting"),
            Int64(minutes)
        )
    }
}
