import Foundation

struct AltitudeNextUpItem: Codable, Equatable, Identifiable, Sendable {
    struct Why: Codable, Equatable, Sendable {
        let label: String
        let confidence: Double
        let line: String
    }

    let agentId: String
    let agentName: String
    let sessionId: String
    let jumpSessionId: String?
    let tmuxSession: String?
    let priority: String?
    let classification: String
    let why: Why
    let waitingSince: String?
    let waitSeconds: Int

    var id: String { sessionId }
}
