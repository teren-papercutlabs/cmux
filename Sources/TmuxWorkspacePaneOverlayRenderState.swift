import CoreGraphics
import Foundation

struct AltitudeMenuOverlayState: Equatable {
    let snapshot: AltitudeNextUpSnapshot
    let priorityRows: [AltitudePriorityMenuRow]
    let selectedItemID: String?
    let arrival: AltitudeMenuArrival?
    let quietSeconds: Int
    let errorMessage: String?
}

struct TmuxWorkspacePaneOverlayRenderState: Equatable {
    let workspaceId: UUID
    let unreadRects: [CGRect]
    let flashRect: CGRect?
    let activePaneBorderRect: CGRect?
    let activePaneBorderColorHex: String?
    let flashToken: UInt64
    let flashReason: WorkspaceAttentionFlashReason?
    let altitudeMenu: AltitudeMenuOverlayState?
    let altitudeTargetRect: CGRect?

    init(
        workspaceId: UUID,
        unreadRects: [CGRect],
        flashRect: CGRect?,
        activePaneBorderRect: CGRect? = nil,
        activePaneBorderColorHex: String? = nil,
        flashToken: UInt64,
        flashReason: WorkspaceAttentionFlashReason?,
        altitudeMenu: AltitudeMenuOverlayState? = nil,
        altitudeTargetRect: CGRect? = nil
    ) {
        self.workspaceId = workspaceId
        self.unreadRects = unreadRects
        self.flashRect = flashRect
        self.activePaneBorderRect = activePaneBorderRect
        self.activePaneBorderColorHex = activePaneBorderColorHex
        self.flashToken = flashToken
        self.flashReason = flashReason
        self.altitudeMenu = altitudeMenu
        self.altitudeTargetRect = altitudeTargetRect
    }
}
