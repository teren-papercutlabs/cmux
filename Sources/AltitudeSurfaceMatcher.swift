import Foundation

struct AltitudeSurfaceEvidence: Equatable {
    let title: String
    let processArguments: [String]
}

enum AltitudeSurfaceMatcher {
    static func matches(
        sessionIDs: Set<String>,
        tmuxSession: String?,
        evidence: AltitudeSurfaceEvidence
    ) -> Bool {
        let candidates = sessionIDs.union(tmuxSession.map { [$0] } ?? [])
        guard !candidates.isEmpty else { return false }
        let titleTokens = tokens(in: evidence.title)
        if !titleTokens.isDisjoint(with: candidates) { return true }

        for index in evidence.processArguments.indices where evidence.processArguments[index] == "a" {
            let next = evidence.processArguments.index(after: index)
            if evidence.processArguments.indices.contains(next), candidates.contains(evidence.processArguments[next]) {
                return true
            }
        }
        return evidence.processArguments.contains(where: candidates.contains)
    }

    private static func tokens(in value: String) -> Set<String> {
        Set(value.split { $0.isWhitespace || $0 == "[" || $0 == "]" || $0 == ":" }.map(String.init))
    }
}
