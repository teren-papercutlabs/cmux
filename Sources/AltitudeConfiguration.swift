import CmuxCommandPalette
import AppKit
import Foundation

struct AltitudeConfiguration: Equatable, Sendable {
    static let flatPaletteKey = "Altitude.flatPalette.v1"
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

    let flatPalette: Bool
    let readyBrightenSeconds: Int
    let pulseSeconds: Int
    let viewerID: String
    let restoreOfficeAttaches: Bool

    init(defaults: UserDefaults = .standard) {
        flatPalette = defaults.bool(forKey: Self.flatPaletteKey)
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
