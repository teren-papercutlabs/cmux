import Foundation

enum AltitudeSeatMoveDecision: Equatable {
    case allow
    case offerReanoint
    case refuseAnointedSeatMove
}

enum AltitudeSeatMovePolicy {
    static func decision(
        movingSurfaceID: UUID,
        sourceSeatSurfaceID: UUID?,
        destinationSeatSurfaceID: UUID?
    ) -> AltitudeSeatMoveDecision {
        if sourceSeatSurfaceID == movingSurfaceID, destinationSeatSurfaceID != movingSurfaceID {
            return .refuseAnointedSeatMove
        }
        guard let destinationSeatSurfaceID, destinationSeatSurfaceID != movingSurfaceID else { return .allow }
        return .offerReanoint
    }
}
