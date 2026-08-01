import Foundation

enum AltitudeSeatMoveDecision: Equatable {
    case allow
    case offerReanoint
}

enum AltitudeSeatMovePolicy {
    static func decision(movingSurfaceID: UUID, destinationSeatSurfaceID: UUID?) -> AltitudeSeatMoveDecision {
        guard let destinationSeatSurfaceID, destinationSeatSurfaceID != movingSurfaceID else { return .allow }
        return .offerReanoint
    }
}
