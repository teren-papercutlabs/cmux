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
