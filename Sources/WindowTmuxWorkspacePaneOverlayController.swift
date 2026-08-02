import AppKit
import ObjectiveC
import SwiftUI

private var tmuxWorkspacePaneWindowOverlayKey: UInt8 = 0
private let tmuxWorkspacePaneOverlayContainerIdentifier = NSUserInterfaceItemIdentifier("cmux.tmuxWorkspacePane.overlay.container")

@MainActor
final class WindowTmuxWorkspacePaneOverlayController: NSObject {
    private weak var window: NSWindow?
    private let containerView = PassthroughWindowOverlayContainerView(frame: .zero)
    private let model = TmuxWorkspacePaneOverlayModel()
    private let hostingView: NSHostingView<TmuxWorkspacePaneOverlayView>
    private let chromeComposition = AppWindowChromeComposition()
    private var installConstraints: [NSLayoutConstraint] = []
    private weak var installedReferenceView: NSView?
    private var lastRenderState: TmuxWorkspacePaneOverlayRenderState?
    private var pendingGeometryRefresh = false

    var hasRenderedState: Bool {
        lastRenderState != nil || !containerView.isHidden
    }

    var isAltitudeMenuPresented: Bool {
        lastRenderState?.altitudeMenuIsPresented == true
    }

    static func controller(for window: NSWindow, createIfNeeded: Bool) -> WindowTmuxWorkspacePaneOverlayController? {
        if let existing = objc_getAssociatedObject(window, &tmuxWorkspacePaneWindowOverlayKey) as? WindowTmuxWorkspacePaneOverlayController {
            return existing
        }
        guard createIfNeeded else { return nil }
        let controller = WindowTmuxWorkspacePaneOverlayController(window: window)
        objc_setAssociatedObject(window, &tmuxWorkspacePaneWindowOverlayKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    init(window: NSWindow) {
        self.window = window
        self.hostingView = NSHostingView(
            rootView: TmuxWorkspacePaneOverlayView(
                unreadRects: [],
                flashRect: nil,
                activePaneBorderRect: nil,
                activePaneBorderColorHex: nil,
                flashStartedAt: nil,
                flashReason: nil,
                altitudeMenu: nil,
                altitudeTargetRect: nil,
                onAltitudeSelectionChange: { _ in },
                onAltitudeJump: { _ in }
            )
        )
        super.init()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.isHidden = true
        containerView.alphaValue = 0
        containerView.identifier = tmuxWorkspacePaneOverlayContainerIdentifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        _ = ensureInstalled()
    }

    @discardableResult
    private func ensureInstalled() -> Bool {
        guard let window,
              let target = chromeComposition
                .contentOverlayTargetResolver
                .installationTarget(for: window) else { return false }

        if containerView.superview !== target.container || installedReferenceView !== target.reference {
            NSLayoutConstraint.deactivate(installConstraints)
            installConstraints.removeAll()
            containerView.removeFromSuperview()
            target.container.addSubview(containerView, positioned: .above, relativeTo: target.reference)
            installConstraints = [
                containerView.topAnchor.constraint(equalTo: target.reference.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: target.reference.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: target.reference.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: target.reference.trailingAnchor),
            ]
            NSLayoutConstraint.activate(installConstraints)
            installedReferenceView = target.reference
        }

        Self.promoteAbovePortalHosts(containerView: containerView, in: target.container)

        return true
    }

    static func promoteAbovePortalHosts(containerView: NSView, in container: NSView) {
        guard containerView.superview === container else { return }
        let portalHosts = container.subviews.compactMap { $0 as? WindowTerminalHostView }
        guard let topmostPortalHost = portalHosts.max(by: {
            (container.subviews.firstIndex(of: $0) ?? -1) < (container.subviews.firstIndex(of: $1) ?? -1)
        }),
        let overlayIndex = container.subviews.firstIndex(of: containerView),
        let hostIndex = container.subviews.firstIndex(of: topmostPortalHost),
        overlayIndex <= hostIndex else { return }
        container.addSubview(containerView, positioned: .above, relativeTo: topmostPortalHost)
    }

    func update(state: TmuxWorkspacePaneOverlayRenderState?) {
        guard ensureInstalled() else { return }

        if state == nil, lastRenderState == nil, containerView.isHidden {
            return
        }
        if let state, state == lastRenderState {
            return
        }

        if let state {
            lastRenderState = state
            model.apply(state)
            hostingView.rootView = TmuxWorkspacePaneOverlayView(
                unreadRects: model.unreadRects,
                flashRect: model.flashRect,
                activePaneBorderRect: model.activePaneBorderRect,
                activePaneBorderColorHex: model.activePaneBorderColorHex,
                flashStartedAt: model.flashStartedAt,
                flashReason: model.flashReason,
                altitudeMenu: state.altitudeMenu,
                altitudeTargetRect: state.altitudeTargetRect,
                onAltitudeSelectionChange: { [weak self] sessionID in
                    self?.handleAltitudeSelectionChange(sessionID)
                },
                onAltitudeJump: { [weak self] item in self?.handleAltitudeJump(item) }
            )
            containerView.interactiveRect = state.altitudeMenu == nil ? nil : state.altitudeTargetRect
            containerView.alphaValue = 1
            containerView.isHidden = false
        } else {
            lastRenderState = nil
            model.clear()
            hostingView.rootView = TmuxWorkspacePaneOverlayView(
                unreadRects: [],
                flashRect: nil,
                activePaneBorderRect: nil,
                activePaneBorderColorHex: nil,
                flashStartedAt: nil,
                flashReason: nil,
                altitudeMenu: nil,
                altitudeTargetRect: nil,
                onAltitudeSelectionChange: { _ in },
                onAltitudeJump: { _ in }
            )
            containerView.interactiveRect = nil
            containerView.alphaValue = 0
            containerView.isHidden = true
        }
    }

    private func handleAltitudeSelectionChange(_ sessionID: String) {
        NotificationCenter.default.post(
            name: .altitudeMenuSelect,
            object: window,
            userInfo: ["sessionID": sessionID]
        )
    }

    private func handleAltitudeJump(_ item: AltitudeNextUpItem) {
        NotificationCenter.default.post(
            name: .altitudeMenuJump,
            object: window,
            userInfo: ["sessionID": item.sessionId]
        )
    }

    func scheduleGeometryRefresh(stateProvider: @MainActor @escaping () -> TmuxWorkspacePaneOverlayRenderState?) {
        guard !pendingGeometryRefresh else { return }
        pendingGeometryRefresh = true
        // Divider drags can emit many geometry snapshots; one overlay update per
        // main-actor turn is enough to keep the active border aligned.
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingGeometryRefresh = false
            update(state: stateProvider())
        }
    }
}
