import AppKit

@MainActor
final class PassthroughWindowOverlayContainerView: NSView {
    var interactiveRect: CGRect?

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let interactiveRect,
              interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
