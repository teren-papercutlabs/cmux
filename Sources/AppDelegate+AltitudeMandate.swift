import AppKit
import Bonsplit
import CmuxWorkspaces

// Decision 27 (teren-ruled 2026-08-04): two MANDATED workspaces. "Priority"
// holds exactly the 1A/1B seats; "Flex" holds everything else. Both always
// exist and can never be closed or renamed. This file is the EXECUTION layer:
// every verdict comes from AltitudeWorkspaceMandate (pure, tested); this code
// only enumerates live state and carries out the returned decisions.
extension AppDelegate {

    // MARK: - Registry

    func altitudeMandatedWorkspaceID(_ mandated: AltitudeMandatedWorkspace) -> UUID? {
        guard AltitudeConfiguration.isEnabled(),
              let raw = UserDefaults.standard.string(forKey: mandated.storedIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    private func altitudeStoreMandatedWorkspaceID(_ id: UUID, for mandated: AltitudeMandatedWorkspace) {
        UserDefaults.standard.set(id.uuidString, forKey: mandated.storedIDKey)
    }

    private func altitudeWorkspace(withID id: UUID) -> (workspace: Workspace, manager: TabManager)? {
        guard let manager = tabManagerFor(tabId: id),
              let workspace = manager.tabs.first(where: { $0.id == id }) else { return nil }
        return (workspace, manager)
    }

    private func altitudeAllWorkspaces() -> [(id: UUID, title: String, manager: TabManager)] {
        var result: [(id: UUID, title: String, manager: TabManager)] = []
        for summary in listMainWindowSummaries() {
            guard let manager = tabManagerFor(windowId: summary.windowId) else { continue }
            for workspace in manager.tabs {
                result.append((workspace.id, workspace.customTitle ?? "", manager))
            }
        }
        return result
    }

    // MARK: - Ensure (launch/restore)

    /// Ensure Priority and Flex exist, adopting live workspaces by stored id or
    /// title before creating anything. Safe to call repeatedly.
    func altitudeEnsureMandatedWorkspaces() {
        guard AltitudeConfiguration.isEnabled() else { return }
        let live = altitudeAllWorkspaces()
        guard !live.isEmpty else { return }
        for mandated in AltitudeMandatedWorkspace.allCases {
            let stored = altitudeMandatedWorkspaceID(mandated)
            switch AltitudeWorkspaceMandate.resolution(
                storedID: stored,
                workspaces: live.map { ($0.id, $0.title) },
                mandated: mandated
            ) {
            case .existing:
                break
            case .adopt(let id):
                altitudeStoreMandatedWorkspaceID(id, for: mandated)
                if let adopted = altitudeWorkspace(withID: id),
                   adopted.workspace.customTitle != mandated.rawValue {
                    _ = adopted.manager.setCustomTitle(tabId: id, title: mandated.rawValue)
                }
            case .create:
                guard let manager = live.first?.manager else { continue }
                let workspace = manager.addWorkspace(title: mandated.rawValue, select: false)
                altitudeStoreMandatedWorkspaceID(workspace.id, for: mandated)
            }
        }
        altitudeEnforcePriorityMembership()
        altitudeEnsureSeatSlots()
    }

    /// Restore completion is not observable (plain flags, async multi-window
    /// hops), so poll briefly after launch instead of racing it.
    func altitudeScheduleMandateEnsureAfterRestore(attempt: Int = 0) {
        guard AltitudeConfiguration.isEnabled(), attempt < 40 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.didAttemptStartupSessionRestore, !self.isApplyingSessionRestore {
                self.altitudeEnsureMandatedWorkspaces()
            } else {
                self.altitudeScheduleMandateEnsureAfterRestore(attempt: attempt + 1)
            }
        }
    }

    // MARK: - Enforcement (Priority holds exactly the seats)

    /// Bounce every non-seat surface out of Priority into Flex. Idempotent.
    func altitudeEnforcePriorityMembership() {
        guard AltitudeConfiguration.isEnabled(),
              let priorityID = altitudeMandatedWorkspaceID(.priority),
              let priority = altitudeWorkspace(withID: priorityID) else { return }
        let configuration = PcLPrioritySwitcherConfiguration.load()
        let interlopers = priority.workspace.panels.filter { _, panel in
            !(panel is AltitudeSeatPlaceholderPanel)
        }.keys.filter { panelID in
            AltitudeWorkspaceMandate.membership(
                surfaceID: panelID,
                destinationWorkspaceID: priorityID,
                priorityID: priorityID,
                leadSurfaceID: configuration.leadSurfaceId,
                understudySurfaceID: configuration.understudySurfaceId
            ) == .bounceToFlex
        }
        for panelID in interlopers {
            _ = altitudeMoveSurfaceToFlex(panelID: panelID)
        }
    }

    // MARK: - Cross-workspace moves

    /// Move a surface into Flex (displacement, un-anoint, enforcement bounce).
    @discardableResult
    func altitudeMoveSurfaceToFlex(panelID: UUID, focus: Bool = false) -> Bool {
        guard let flexID = altitudeMandatedWorkspaceID(.flex),
              let flex = altitudeWorkspace(withID: flexID),
              let source = locateSurface(surfaceId: panelID),
              let sourceWorkspace = source.tabManager.tabs.first(where: { $0.id == source.workspaceId })
        else { return false }
        guard source.workspaceId != flexID else { return true }
        guard let targetPane = flex.workspace.bonsplitController.allPaneIds.last else { return false }
        sourceWorkspace.setPanelPinned(panelId: panelID, pinned: false)
        guard let detached = sourceWorkspace.detachSurface(panelId: panelID) else { return false }
        return flex.workspace.attachDetachedSurface(detached, inPane: targetPane, focus: focus) != nil
    }

    /// Decision 27 anoint: membership in Priority IS the seat. The new surface
    /// moves into Priority; a displaced holder shifts to Flex.
    func altitudeAnoint(role: PcLPrioritySwitcherConfiguration.Role, panelID: UUID) {
        guard AltitudeConfiguration.isEnabled() else { return }
        altitudeEnsureMandatedWorkspaces()
        guard let priorityID = altitudeMandatedWorkspaceID(.priority),
              let priority = altitudeWorkspace(withID: priorityID),
              let source = locateSurface(surfaceId: panelID),
              let sourceWorkspace = source.tabManager.tabs.first(where: { $0.id == source.workspaceId })
        else { return }

        let previousConfiguration = PcLPrioritySwitcherConfiguration.load()
        let previousHolderID: UUID? = {
            let id = role == .lead ? previousConfiguration.leadSurfaceId : previousConfiguration.understudySurfaceId
            guard let id, id != panelID, locateSurface(surfaceId: id) != nil else { return nil }
            return id
        }()

        var configuration = previousConfiguration
        configuration.assign(role: role, surfaceId: panelID)
        configuration.save()

        priority.workspace.isApplyingAltitudeSeatMove = true
        defer { priority.workspace.isApplyingAltitudeSeatMove = false }

        // Bring the new seat surface into Priority FIRST (a pane never empties
        // and auto-closes this way), preferring the displaced holder's pane so
        // the new tab visibly takes the old one's spot.
        if source.workspaceId != priorityID {
            let seatPane: PaneID? = previousHolderID.flatMap { priority.workspace.paneId(forPanelId: $0) }
                ?? priority.workspace.bonsplitController.allPaneIds.first
            if let seatPane, let detached = sourceWorkspace.detachSurface(panelId: panelID) {
                guard priority.workspace.attachDetachedSurface(detached, inPane: seatPane, atIndex: 0, focus: true) != nil else { return }
            }
        } else if let previousHolderID,
                  let seatPane = priority.workspace.paneId(forPanelId: previousHolderID),
                  priority.workspace.paneId(forPanelId: panelID) != seatPane {
            _ = priority.workspace.moveSurface(panelId: panelID, toPane: seatPane, atIndex: 0, focus: true)
        }

        // Displaced holder: out of its seat, out of Priority, into Flex —
        // unless it still holds the OTHER seat (role swap).
        if let previousHolderID,
           configuration.leadSurfaceId != previousHolderID,
           configuration.understudySurfaceId != previousHolderID {
            _ = altitudeMoveSurfaceToFlex(panelID: previousHolderID)
        }
        priority.workspace.setPanelPinned(panelId: panelID, pinned: true)

        altitudeEnforcePriorityMembership()
        altitudeEnsureSeatSlots()
        priority.workspace.bonsplitController.invalidateHostProvidedChrome()
        priority.workspace.objectWillChange.send()
        NotificationCenter.default.post(name: .altitudeSeatConfigurationDidChange, object: priority.workspace)
    }

    /// Un-anoint: the seat empties and the tab goes home to Flex.
    func altitudeClearSeat(panelID: UUID) {
        guard AltitudeConfiguration.isEnabled() else { return }
        var configuration = PcLPrioritySwitcherConfiguration.load()
        if configuration.leadSurfaceId == panelID { configuration.leadSurfaceId = nil }
        if configuration.understudySurfaceId == panelID { configuration.understudySurfaceId = nil }
        configuration.save()
        if let located = locateSurface(surfaceId: panelID),
           let workspace = located.tabManager.tabs.first(where: { $0.id == located.workspaceId }) {
            workspace.setPanelPinned(panelId: panelID, pinned: false)
            if located.workspaceId == altitudeMandatedWorkspaceID(.priority) {
                _ = altitudeMoveSurfaceToFlex(panelID: panelID)
            }
            altitudeEnsureSeatSlots()
            workspace.bonsplitController.invalidateHostProvidedChrome()
            workspace.objectWillChange.send()
            NotificationCenter.default.post(name: .altitudeSeatConfigurationDidChange, object: workspace)
        }
    }
}

// MARK: - Empty-seat placeholders (decision 27 phase 2)

extension Workspace {
    /// Create a placeholder tab holding an empty seat's slot. Mandate-owned:
    /// nothing else creates or keeps these.
    @discardableResult
    func addAltitudeSeatPlaceholder(role: String, inPane paneID: PaneID?) -> UUID? {
        let panel = AltitudeSeatPlaceholderPanel(workspaceId: id, role: role)
        panels[panel.id] = panel
        panelTitles[panel.id] = panel.displayTitle
        let targetPane = paneID ?? bonsplitController.allPaneIds.first
        guard let targetPane,
              let tabId = bonsplitController.createTab(
                  title: panel.displayTitle,
                  icon: "chair.lounge.fill",
                  kind: SurfaceKind.altitudeSeatPlaceholder.rawValue,
                  isPinned: true,
                  inPane: targetPane
              ) else {
            panels.removeValue(forKey: panel.id)
            panelTitles.removeValue(forKey: panel.id)
            return nil
        }
        bindSurface(tabId, toPanelId: panel.id)
        return panel.id
    }

    var altitudeSeatPlaceholders: [(panelID: UUID, role: String)] {
        panels.compactMap { key, value in
            guard let placeholder = value as? AltitudeSeatPlaceholderPanel else { return nil }
            return (key, placeholder.role)
        }
    }
}

extension AppDelegate {
    /// Priority always renders both slots: each role shows its seat surface,
    /// or a placeholder when empty. Idempotent; runs after ensure/anoint/clear.
    func altitudeEnsureSeatSlots() {
        guard AltitudeConfiguration.isEnabled(),
              let priorityID = altitudeMandatedWorkspaceID(.priority),
              let priority = altitudeWorkspace(withID: priorityID) else { return }
        let configuration = PcLPrioritySwitcherConfiguration.load()
        let workspace = priority.workspace
        workspace.isApplyingAltitudeSeatMove = true
        defer { workspace.isApplyingAltitudeSeatMove = false }

        let seatPresent: (UUID?) -> Bool = { id in
            guard let id else { return false }
            return workspace.panels[id] != nil
        }
        let roleFilled: [String: Bool] = [
            "1A": seatPresent(configuration.leadSurfaceId),
            "1B": seatPresent(configuration.understudySurfaceId),
        ]

        // Drop placeholders for roles that are filled (or duplicated).
        var seenRoles = Set<String>()
        for (panelID, role) in workspace.altitudeSeatPlaceholders {
            if roleFilled[role] == true || seenRoles.contains(role) {
                _ = workspace.closePanel(panelID, force: true)
            } else {
                seenRoles.insert(role)
            }
        }
        // Create placeholders for empty roles, 1A into the first pane, 1B
        // beside it (second pane when one exists).
        let paneIDs = workspace.bonsplitController.allPaneIds
        for (role, pane) in [("1A", paneIDs.first), ("1B", paneIDs.count > 1 ? paneIDs[1] : paneIDs.first)] {
            guard roleFilled[role] == false, !seenRoles.contains(role) else { continue }
            _ = workspace.addAltitudeSeatPlaceholder(role: role, inPane: pane)
        }
    }
}
