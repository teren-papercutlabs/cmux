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
