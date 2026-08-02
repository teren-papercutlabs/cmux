import SwiftUI

enum AltitudeNextUpFloatPresentation {
    struct Card: Identifiable, Equatable {
        let item: AltitudeNextUpItem
        let sessionName: String
        let shortcutHint: String

        var id: String { item.id }
    }

    static let maximumCardCount = 3
    static let targetPaneOffset = 2
    static let anchor: Alignment = .bottomTrailing
    static let cardWidth: CGFloat = 420
    static let edgeInset: CGFloat = 12
    static let cardSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 12

    static var preferredFloatWidth: CGFloat {
        cardWidth + edgeInset * 2 + cardHorizontalPadding * 2
    }

    static func shouldRender(snapshot: AltitudeNextUpSnapshot) -> Bool {
        !snapshot.items.isEmpty
    }

    static func cards(snapshot: AltitudeNextUpSnapshot) -> [Card] {
        Array(snapshot.items.prefix(maximumCardCount)).enumerated().map { index, item in
            Card(
                item: item,
                sessionName: item.tmuxSession ?? item.jumpSessionId ?? item.sessionId,
                shortcutHint: index == 0 ? "⌥↩" : "⌥\(index + 1)"
            )
        }
    }

    static func targetPaneIndex(terminalPaneIndices: [Int]) -> Int? {
        terminalPaneIndices.last(where: { $0 <= targetPaneOffset }) ?? terminalPaneIndices.first
    }

    static func floatWidth(availableWidth: CGFloat) -> CGFloat {
        min(max(0, availableWidth), preferredFloatWidth)
    }

    static func cardContentWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, floatWidth(availableWidth: availableWidth) - edgeInset * 2 - cardHorizontalPadding * 2)
    }

    static func floatOriginX(targetMaxX: CGFloat) -> CGFloat {
        max(0, targetMaxX - floatWidth(availableWidth: targetMaxX))
    }
}

struct AltitudeNextUpFloat: View {
    let snapshot: AltitudeNextUpSnapshot
    let errorMessage: String?
    let availableWidth: CGFloat
    let onGo: (AltitudeNextUpItem) -> Void

    var body: some View {
        let cards = AltitudeNextUpFloatPresentation.cards(snapshot: snapshot)
        if !cards.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .cmuxFont(size: 11, weight: .medium)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                        .frame(
                            width: AltitudeNextUpFloatPresentation.cardContentWidth(availableWidth: availableWidth),
                            alignment: .leading
                        )
                }

                ForEach(cards) { card in
                    Button {
                        onGo(card.item)
                    } label: {
                        cardLabel(card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "altitude.strip.go.accessibility", defaultValue: "Go to %@, %@"),
                            card.sessionName,
                            card.item.why.line
                        )
                    )
                }
            }
            .padding(AltitudeNextUpFloatPresentation.edgeInset)
            .frame(width: AltitudeNextUpFloatPresentation.floatWidth(availableWidth: availableWidth))
        }
    }

    private func cardLabel(_ card: AltitudeNextUpFloatPresentation.Card) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let priority = card.item.priority {
                    Text(priority.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }

                Text(card.sessionName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(card.shortcutHint)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(card.item.why.line)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(card.item.classification == "uncertain" ? Color.orange : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(formattedWait(card.item.waitSeconds))
                .cmuxFont(size: 10, weight: .medium)
                .foregroundStyle(.tertiary)
        }
        .frame(
            width: AltitudeNextUpFloatPresentation.cardContentWidth(availableWidth: availableWidth),
            alignment: .leading
        )
        .padding(.horizontal, AltitudeNextUpFloatPresentation.cardHorizontalPadding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
