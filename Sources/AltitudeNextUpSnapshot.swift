import Foundation

struct AltitudeProcessingItem: Codable, Equatable, Identifiable, Sendable {
    let agentId: String
    let agentName: String
    let sessionId: String
    let tmuxSession: String?
    let priority: String?

    var id: String { sessionId }
    var sessionName: String { tmuxSession ?? sessionId }
}

struct AltitudeNextUpSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let collectedAt: String
    let items: [AltitudeNextUpItem]
    let processingCount: Int
    let idleCount: Int
    let processing: [AltitudeProcessingItem]

    init(
        schemaVersion: Int,
        collectedAt: String,
        items: [AltitudeNextUpItem],
        processingCount: Int,
        idleCount: Int,
        processing: [AltitudeProcessingItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.collectedAt = collectedAt
        self.items = items
        self.processingCount = processingCount
        self.idleCount = idleCount
        self.processing = processing
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, collectedAt, items, processingCount, idleCount, processing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        collectedAt = try container.decode(String.self, forKey: .collectedAt)
        items = try container.decode([AltitudeNextUpItem].self, forKey: .items)
        processingCount = try container.decode(Int.self, forKey: .processingCount)
        idleCount = try container.decode(Int.self, forKey: .idleCount)
        processing = try container.decodeIfPresent([AltitudeProcessingItem].self, forKey: .processing) ?? []
    }

    static let empty = Self(
        schemaVersion: 1,
        collectedAt: "",
        items: [],
        processingCount: 0,
        idleCount: 0,
        processing: []
    )
}
