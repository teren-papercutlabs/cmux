import Foundation

struct AltitudeNextUpSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let collectedAt: String
    let items: [AltitudeNextUpItem]
    let processingCount: Int
    let idleCount: Int

    static let empty = Self(
        schemaVersion: 1,
        collectedAt: "",
        items: [],
        processingCount: 0,
        idleCount: 0
    )
}
