import Foundation

enum AltitudePresenceStage: Int, Comparable, Sendable {
    case ready = 1
    case bright = 2
    case pulse = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func resolve(
        waitSeconds: Int,
        priority: String?,
        configuration: AltitudeConfiguration
    ) -> Self {
        if priority == "1A", waitSeconds >= configuration.pulseSeconds {
            return .pulse
        }
        if waitSeconds >= configuration.readyBrightenSeconds {
            return .bright
        }
        return .ready
    }
}
