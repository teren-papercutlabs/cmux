import Foundation

struct AltitudeSurfaceEvidence: Equatable {
    let title: String
    let bindingText: [String]
    let processArgumentVectors: [[String]]

    init(
        title: String,
        bindingText: [String] = [],
        processArgumentVectors: [[String]]
    ) {
        self.title = title
        self.bindingText = bindingText
        self.processArgumentVectors = processArgumentVectors
    }
}

enum AltitudeSurfaceMatcher {
    static func matches(
        sessionIDs: Set<String>,
        tmuxSession: String?,
        evidence: AltitudeSurfaceEvidence
    ) -> Bool {
        let candidates = sessionIDs.union(tmuxSession.map { [$0] } ?? [])
        guard !candidates.isEmpty else { return false }
        if !tokens(in: evidence.title).isDisjoint(with: candidates) { return true }
        if evidence.bindingText.contains(where: { !tokens(in: $0).isDisjoint(with: candidates) }) {
            return true
        }

        for arguments in evidence.processArgumentVectors {
            for index in arguments.indices where arguments[index] == "a" {
                let next = arguments.index(after: index)
                if arguments.indices.contains(next), candidates.contains(arguments[next]) {
                    return true
                }
            }
        }
        return false
    }

    private static func tokens(in value: String) -> Set<String> {
        Set(value.split { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
        }.map(String.init))
    }
}
