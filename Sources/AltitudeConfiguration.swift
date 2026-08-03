import CmuxCommandPalette
import AppKit
import Foundation

struct AltitudeConfiguration: Equatable, Sendable {
    static let readyBrightenSecondsKey = "Altitude.readyBrightenSeconds.v1"
    static let pulseSecondsKey = "Altitude.pulseSeconds.v1"
    static let viewerIDKey = "Altitude.viewerID.v1"
    static let restoreOfficeAttachesKey = "Altitude.restoreOfficeAttaches.v1"

    static let defaultViewerID = "276672685"
    static let defaultReadyBrightenSeconds = 120
    static let defaultPulseSeconds = 300

    static func isEnabled(bundle: Bundle = .main) -> Bool {
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ""
        return displayName.hasPrefix("Altitude")
    }

    let readyBrightenSeconds: Int
    let pulseSeconds: Int
    let viewerID: String
    let restoreOfficeAttaches: Bool

    init(defaults: UserDefaults = .standard) {
        let brighten = defaults.integer(forKey: Self.readyBrightenSecondsKey)
        let pulse = defaults.integer(forKey: Self.pulseSecondsKey)
        let storedViewer = defaults.string(forKey: Self.viewerIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        readyBrightenSeconds = brighten > 0 ? brighten : Self.defaultReadyBrightenSeconds
        pulseSeconds = pulse > 0 ? pulse : Self.defaultPulseSeconds
        viewerID = storedViewer.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultViewerID
        restoreOfficeAttaches = defaults.object(forKey: Self.restoreOfficeAttachesKey) == nil
            ? true
            : defaults.bool(forKey: Self.restoreOfficeAttachesKey)
    }
}

enum AltitudeSeatTitle {
    private static let prefixes = ["[1A] ", "[1B] "]

    static func baseTitle(_ title: String) -> String {
        for prefix in prefixes where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    static func resolved(baseTitle: String, role: String?) -> String {
        let title = Self.baseTitle(baseTitle)
        guard let role else { return title }
        return "[\(role)] \(title)"
    }

    static func role(
        isAltitudeEnabled: Bool,
        panelID: UUID,
        leadSurfaceID: UUID?,
        understudySurfaceID: UUID?
    ) -> String? {
        guard isAltitudeEnabled else { return nil }
        if leadSurfaceID == panelID { return "1A" }
        if understudySurfaceID == panelID { return "1B" }
        return nil
    }
}

enum AltitudePaletteCorpus {
    static func orderedEntries<Entry>(
        query: String,
        priorityEntries: [Entry],
        needsYouEntries: [Entry]
    ) -> [Entry] {
        if CommandPaletteFuzzyMatcher.preparedQuery(query).isEmpty {
            return priorityEntries + needsYouEntries
        }
        return []
    }
}

enum AltitudePriorityShortcut {
    static func hint(for priority: String) -> String? {
        switch priority {
        case "1A": return "⌘1"
        case "1B": return "⌘2"
        default: return nil
        }
    }

    static func priority(
        isAltitudeEnabled: Bool,
        characters: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        textInputOwnsEvent: Bool
    ) -> String? {
        guard isAltitudeEnabled, !textInputOwnsEvent else { return nil }
        let normalizedFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard normalizedFlags == [.command] else { return nil }

        let digit: Int? = switch keyCode {
        case 18: 1
        case 19: 2
        default: Int(characters)
        }
        switch digit {
        case 1: return "1A"
        case 2: return "1B"
        default: return nil
        }
    }
}

enum AltitudeMenuShortcut {
    static func matches(
        isAltitudeEnabled: Bool,
        characters: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        textInputOwnsEvent: Bool
    ) -> Bool {
        guard isAltitudeEnabled, !textInputOwnsEvent else { return false }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags == [.command] else { return false }
        return characters == "0" || keyCode == 29
    }
}

enum AltitudeTUIHostPresentation {
    enum ToggleDecision: Equatable {
        case returnTo(UUID)
        case focusTUI
        case createTUI
    }

    /// cmd-0 with a detached stack window: false (default) = jump to the
    /// window the menu lives in; true = the menu comes to the current window.
    /// Toggle: defaults write com.cmuxterm.app AltitudeMenuFollowsFocus -bool true
    static let menuFollowsFocusKey = "AltitudeMenuFollowsFocus"

    /// The menu belongs in the STACK region: the first pane not holding a seat
    /// surface. Positional index-2 targeting put the menu in a seat pane the
    /// moment the layout was anything but the canonical three columns.
    static func targetPane<Pane: Equatable>(
        paneIDs: [Pane],
        seatPanes: Set<Pane>
    ) -> Pane? where Pane: Hashable {
        guard !paneIDs.isEmpty else { return nil }
        return paneIDs.first(where: { !seatPanes.contains($0) }) ?? paneIDs.last
    }

    static func toggleDecision(
        focusedPanelID: UUID?,
        tuiPanelID: UUID?,
        returnPanelID: UUID?
    ) -> ToggleDecision {
        guard let tuiPanelID else { return .createTUI }
        if focusedPanelID == tuiPanelID, let returnPanelID { return .returnTo(returnPanelID) }
        return .focusTUI
    }

    static func launchCommand(
        bunPath: String,
        tuiDirectory: String,
        returnTargetPath: String
    ) -> String {
        let directory = shellQuote(tuiDirectory)
        let returnPath = shellQuote(returnTargetPath)
        let bun = shellQuote(bunPath)
        // node_modules is gitignored and `bun run` does not auto-install for a
        // script path, so a fresh checkout must install before first launch or
        // the pane shows a dead module error forever.
        return "cd \(directory) && { [ -d node_modules ] || \(bun) install --frozen-lockfile; } && exec env ALTITUDE_RETURN_TARGET_FILE=\(returnPath) \(bun) run src/index.ts"
    }

    /// Ghostty execs a surface's initialCommand directly (no shell), so the
    /// compound launch command is written to a self-deleting script and the
    /// script path is the command. Unlike the Dock's shellStartupScript, this
    /// deliberately does NOT fall back to an interactive shell when the TUI
    /// exits: the pane must DIE on exit so the cmd-0 host detects processExited
    /// and recreates the menu — a surviving shell reads as a live menu forever.
    static func writeLaunchScript(
        bunPath: String,
        tuiDirectory: String,
        returnTargetPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        let command = launchCommand(
            bunPath: bunPath,
            tuiDirectory: tuiDirectory,
            returnTargetPath: returnTargetPath
        )
        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-altitude-tui-\(UUID().uuidString.lowercased()).sh")
        let body = """
        #!/bin/sh
        rm -f -- "$0" 2>/dev/null || true
        \(command)
        """
        do {
            try body.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            return scriptURL.path
        } catch {
            return nil
        }
    }

    /// Resolve the altitude-tui checkout at RUNTIME. `#filePath` bakes the
    /// build machine's worktree path into the binary — a path that does not
    /// exist on the machine the app is installed on — so it is only the
    /// last-resort dev fallback. Precedence: explicit env override, per-user
    /// default, app-bundle copy, then the compile-time path.
    static func sourceTUIDirectory(
        sourceFile: String = #filePath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> String {
        var isDirectory: ObjCBool = false
        func usable(_ path: String?) -> String? {
            guard let path, !path.isEmpty,
                  fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return path
        }
        if let override = usable(environment["ALTITUDE_TUI_DIR"]) { return override }
        if let configured = usable(defaults.string(forKey: "AltitudeTUIDirectory")) { return configured }
        if let bundled = usable(bundleResourceURL?.appendingPathComponent("altitude-tui", isDirectory: true).path) {
            return bundled
        }
        return URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("altitude-tui", isDirectory: true)
            .path
    }

    static func bunPath(fileManager: FileManager = .default) -> String? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/bun", "/usr/local/bin/bun", "\(home)/.bun/bin/bun"]
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum AltitudePriorityFocusTarget {
    static func surfaceID(
        for priority: String,
        configuration: PcLPrioritySwitcherConfiguration
    ) -> UUID? {
        switch priority {
        case "1A": return configuration.leadSurfaceId
        case "1B": return configuration.understudySurfaceId
        default: return nil
        }
    }
}

enum AltitudeOfficeAttachResumePolicy {
    static let bindingKind = "altitude-office-attach"

    static func allowsRestore(
        bindingKind: String?,
        isAltitudeEnabled: Bool,
        restoreOfficeAttaches: Bool
    ) -> Bool {
        guard bindingKind == Self.bindingKind else { return true }
        return isAltitudeEnabled && restoreOfficeAttaches
    }
}
