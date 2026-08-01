import Foundation

struct AltitudeConfiguration: Equatable, Sendable {
    static let flatPaletteKey = "Altitude.flatPalette.v1"
    static let readyBrightenSecondsKey = "Altitude.readyBrightenSeconds.v1"
    static let pulseSecondsKey = "Altitude.pulseSeconds.v1"
    static let viewerIDKey = "Altitude.viewerID.v1"

    static let defaultViewerID = "276672685"
    static let defaultReadyBrightenSeconds = 120
    static let defaultPulseSeconds = 300

    let flatPalette: Bool
    let readyBrightenSeconds: Int
    let pulseSeconds: Int
    let viewerID: String

    init(defaults: UserDefaults = .standard) {
        flatPalette = defaults.bool(forKey: Self.flatPaletteKey)
        let brighten = defaults.integer(forKey: Self.readyBrightenSecondsKey)
        let pulse = defaults.integer(forKey: Self.pulseSecondsKey)
        let storedViewer = defaults.string(forKey: Self.viewerIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        readyBrightenSeconds = brighten > 0 ? brighten : Self.defaultReadyBrightenSeconds
        pulseSeconds = pulse > 0 ? pulse : Self.defaultPulseSeconds
        viewerID = storedViewer.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultViewerID
    }
}
