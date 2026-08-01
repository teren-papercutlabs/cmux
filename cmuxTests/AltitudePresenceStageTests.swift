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
    @Test("needs-you entries remain in the corpus for a typed query")
    func typedQueryKeepsNeedsYouEntries() {
        let entries = AltitudePaletteCorpus.orderedEntries(
            query: "needs teren",
            priorityEntries: ["priority"],
            needsYouEntries: ["needs-you"]
        )
        #expect(entries == ["needs-you"])
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

    @Test("the third pane is the stable anchor with a last-pane fallback")
    func targetPaneIndex() {
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(paneCount: 0) == nil)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(paneCount: 1) == 0)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(paneCount: 2) == 1)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(paneCount: 3) == 2)
        #expect(AltitudeNextUpFloatPresentation.targetPaneIndex(paneCount: 5) == 2)
    }

    @Test("only the card stack captures clicks inside the target pane")
    func interactiveRectStaysBottomTrailing() throws {
        let target = CGRect(x: 800, y: 40, width: 500, height: 700)
        let rect = try #require(
            AltitudeNextUpFloatPresentation.interactiveRect(
                targetRect: target,
                cardCount: 3,
                includesError: false
            )
        )

        #expect(rect.maxX == target.maxX)
        #expect(rect.maxY == target.maxY)
        #expect(rect.minX >= target.minX)
        #expect(rect.minY > target.minY)
        #expect(AltitudeNextUpFloatPresentation.interactiveRect(
            targetRect: target,
            cardCount: 0,
            includesError: false
        ) == nil)
    }
}
