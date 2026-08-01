import AppKit
import CmuxFoundation
import SwiftUI

struct TmuxWorkspacePaneOverlayView: View {
    let unreadRects: [CGRect]
    let flashRect: CGRect?
    let activePaneBorderRect: CGRect?
    let activePaneBorderColorHex: String?
    let flashStartedAt: Date?
    let flashReason: WorkspaceAttentionFlashReason?
    let altitudeSnapshot: AltitudeNextUpSnapshot?
    let altitudeErrorMessage: String?
    let altitudeTargetRect: CGRect?
    let onAltitudeGo: (AltitudeNextUpItem) -> Void
    let onAltitudeFrameChange: (CGRect?) -> Void
    @State private var completedFlashStartedAt: Date?

    var body: some View {
        ZStack(alignment: .topLeading) {
            overlayContent
                .allowsHitTesting(false)

            if let altitudeSnapshot,
               let altitudeTargetRect,
               AltitudeNextUpFloatPresentation.shouldRender(snapshot: altitudeSnapshot) {
                AltitudeNextUpFloat(
                    snapshot: altitudeSnapshot,
                    errorMessage: altitudeErrorMessage,
                    availableWidth: altitudeTargetRect.width,
                    onGo: onAltitudeGo
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AltitudeNextUpFramePreferenceKey.self,
                            value: proxy.frame(in: .named(AltitudeNextUpFramePreferenceKey.coordinateSpace))
                        )
                    }
                }
                .frame(
                    width: altitudeTargetRect.width,
                    height: altitudeTargetRect.height,
                    alignment: AltitudeNextUpFloatPresentation.anchor
                )
                .offset(x: altitudeTargetRect.minX, y: altitudeTargetRect.minY)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: AltitudeNextUpFramePreferenceKey.coordinateSpace)
            .onPreferenceChange(AltitudeNextUpFramePreferenceKey.self) { frame in
                onAltitudeFrameChange(frame)
            }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if shouldAnimateFlash, let flashStartedAt {
            TimelineView(TmuxWorkspacePaneFlashTimelineSchedule(startDate: flashStartedAt)) { timeline in
                overlayCanvas(timelineDate: timeline.date)
                    .onChange(of: timeline.date) { _, date in
                        if date.timeIntervalSince(flashStartedAt) >= FocusFlashPattern.duration {
                            completedFlashStartedAt = flashStartedAt
                        }
                    }
            }
        } else if !unreadRects.isEmpty || activePaneBorderRect != nil {
            overlayCanvas(timelineDate: nil)
        } else {
            Color.clear
        }
    }

    private var shouldAnimateFlash: Bool {
        guard let flashRect,
              let flashStartedAt else { return false }
        guard completedFlashStartedAt != flashStartedAt,
              ringPath(for: flashRect) != nil else { return false }
        return Date() <= flashStartedAt.addingTimeInterval(FocusFlashPattern.duration)
    }

    private func overlayCanvas(timelineDate: Date?) -> some View {
        Canvas { context, _ in
            if let activePaneBorderRect,
               let activePaneBorderColorHex {
                drawActivePaneBorder(
                    in: &context,
                    rect: activePaneBorderRect,
                    colorHex: activePaneBorderColorHex
                )
            }

            for rect in unreadRects {
                drawUnreadRing(in: &context, rect: rect)
            }

            guard let flashRect,
                  let flashStartedAt,
                  let timelineDate else { return }
            let elapsed = timelineDate.timeIntervalSince(flashStartedAt)
            let opacity = FocusFlashPattern.opacity(at: elapsed)
            guard opacity > 0.001 else { return }
            drawFlashRing(
                in: &context,
                rect: flashRect,
                opacity: opacity,
                reason: flashReason ?? .notificationArrival
            )
        }
    }

    private func drawActivePaneBorder(
        in context: inout GraphicsContext,
        rect: CGRect,
        colorHex: String
    ) {
        guard let path = ringPath(for: rect),
              let color = NSColor(hex: colorHex) else { return }
        context.stroke(
            path,
            with: .color(Color(nsColor: color)),
            style: StrokeStyle(
                lineWidth: CGFloat(PaneChromeSettings.activeBorderLineWidth),
                lineJoin: .round
            )
        )
    }

    private func drawUnreadRing(in context: inout GraphicsContext, rect: CGRect) {
        guard let path = ringPath(for: rect) else { return }
        let presentation = WorkspaceAttentionCoordinator.notificationRingStyle
        let strokeColor = Color(nsColor: presentation.accent.strokeColor)

        var glowContext = context
        glowContext.addFilter(
            .shadow(
                color: strokeColor.opacity(presentation.glowOpacity),
                radius: presentation.glowRadius
            )
        )
        glowContext.stroke(
            path,
            with: .color(strokeColor),
            style: StrokeStyle(lineWidth: PanelOverlayRingMetrics.lineWidth, lineJoin: .round)
        )
    }

    private func drawFlashRing(
        in context: inout GraphicsContext,
        rect: CGRect,
        opacity: Double,
        reason: WorkspaceAttentionFlashReason
    ) {
        guard let path = ringPath(for: rect) else { return }
        let presentation = WorkspaceAttentionCoordinator.flashStyle(for: reason)
        let strokeColor = Color(nsColor: presentation.accent.strokeColor)

        var glowContext = context
        glowContext.addFilter(
            .shadow(
                color: strokeColor.opacity(opacity * presentation.glowOpacity),
                radius: presentation.glowRadius
            )
        )
        glowContext.stroke(
            path,
            with: .color(strokeColor.opacity(opacity)),
            style: StrokeStyle(lineWidth: PanelOverlayRingMetrics.lineWidth, lineJoin: .round)
        )
    }

    private func ringPath(for rect: CGRect) -> Path? {
        guard rect.width > PanelOverlayRingMetrics.inset * 2,
              rect.height > PanelOverlayRingMetrics.inset * 2 else { return nil }
        return Path(
            roundedRect: PanelOverlayRingMetrics.pathRect(in: rect),
            cornerRadius: PanelOverlayRingMetrics.cornerRadius
        )
    }
}

private struct AltitudeNextUpFramePreferenceKey: PreferenceKey {
    static let coordinateSpace = "cmux.altitude.next-up.overlay"
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct TmuxWorkspacePaneFlashTimelineSchedule: TimelineSchedule {
    let startDate: Date

    func entries(from requestedStartDate: Date, mode: Mode) -> Entries {
        let firstDate = requestedStartDate > startDate ? requestedStartDate : startDate
        let interval = mode == .lowFrequency ? 1.0 / 10.0 : 1.0 / 60.0
        return Entries(
            nextDate: firstDate,
            endDate: startDate.addingTimeInterval(FocusFlashPattern.duration),
            interval: interval
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date
        let endDate: Date
        let interval: TimeInterval

        mutating func next() -> Date? {
            guard nextDate <= endDate else { return nil }
            let date = nextDate
            nextDate = nextDate.addingTimeInterval(interval)
            return date
        }
    }
}
