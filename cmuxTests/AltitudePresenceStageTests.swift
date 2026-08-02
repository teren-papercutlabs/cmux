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
}

@Suite("Altitude floating next-up cards")
struct AltitudeNextUpFloatPresentationTests {
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

    @Test("an empty snapshot has no floating presentation footprint")
    func emptySnapshotDoesNotRender() {
        #expect(!AltitudeNextUpFloatPresentation.shouldRender(snapshot: .empty))
        #expect(AltitudeNextUpFloatPresentation.cards(snapshot: .empty).isEmpty)
    }

    @Test("the float exposes at most three cards with session names")
    func cardsUseSessionNamesAndCapAtThree() throws {
        let snapshot = AltitudeNextUpSnapshot(
            schemaVersion: 1,
            collectedAt: "2026-08-01T20:05:00Z",
            items: [
                item(id: "one", tmuxSession: "kleya-hive-drive"),
                item(id: "two", tmuxSession: "xianxing-altitude-third-pane"),
                item(id: "three", tmuxSession: "rasim-resilience"),
                item(id: "four", tmuxSession: "must-not-render"),
            ],
            processingCount: 4,
            idleCount: 2
        )

        let cards = AltitudeNextUpFloatPresentation.cards(snapshot: snapshot)
        let first = try #require(cards.first)
        #expect(cards.count == 3)
        #expect(first.sessionName == "kleya-hive-drive")
        #expect(cards.map(\.shortcutHint) == ["⌥↩", "⌥2", "⌥3"])
    }

    @Test("the third terminal pane is the stable anchor with a nearest-terminal fallback")
    func targetPaneIndex() {
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(terminalPaneIndices: []) == nil)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(terminalPaneIndices: [0]) == 0)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(terminalPaneIndices: [0, 1, 2]) == 2)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(terminalPaneIndices: [0, 1, 3]) == 1)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(terminalPaneIndices: [3, 4]) == 3)
    }

    @Test("cards grow leftward from the target pane edge instead of clipping to the pane")
    func cardWidthUsesOverlaySpace() {
        #expect(AltitudeNextUpFloatPresentation.preferredFloatWidth == 468)
        #expect(AltitudeNextUpFloatPresentation.floatWidth(availableWidth: 500) == 468)
        #expect(AltitudeNextUpFloatPresentation.cardContentWidth(availableWidth: 500) == 420)
        #expect(AltitudeNextUpFloatPresentation.floatOriginX(targetMaxX: 1_000) == 532)
        #expect(AltitudeNextUpFloatPresentation.floatWidth(availableWidth: 300) == 300)
        #expect(AltitudeNextUpFloatPresentation.cardContentWidth(availableWidth: 300) == 252)
        #expect(AltitudeNextUpFloatPresentation.floatOriginX(targetMaxX: 300) == 0)
    }
}

@MainActor
@Suite("Altitude window overlay interaction")
struct AltitudeWindowOverlayInteractionTests {
    @Test("the flipped container only captures the measured card frame")
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
}
