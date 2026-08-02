import Foundation

enum AltitudeOfficeAttachResumeParser {
    static func binding(
        processName: String,
        processPath: String?,
        arguments: [String],
        environment: [String: String],
        homeDirectory: String,
        isEnabled: Bool,
        capturedAt: TimeInterval
    ) -> SurfaceResumeBindingSnapshot? {
        guard isEnabled, arguments.count == 4 else { return nil }

        let executableBasenames = [
            processName,
            processPath.map { ($0 as NSString).lastPathComponent },
            arguments.first.map { ($0 as NSString).lastPathComponent },
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard !executableBasenames.isEmpty,
              executableBasenames.allSatisfy({ $0 == "node" || $0 == "nodejs" }) else {
            return nil
        }

        let expectedScript = (homeDirectory as NSString)
            .appendingPathComponent("pcl-client/office/dist/index.js")
        guard (arguments[1] as NSString).standardizingPath == (expectedScript as NSString).standardizingPath,
              arguments[2] == "a",
              let sessionID = normalizedSessionID(arguments[3]) else {
            return nil
        }

        let command = arguments.map(shellSingleQuoted).joined(separator: " ")
        return SurfaceResumeBindingSnapshot(
            name: "Office \(sessionID)",
            kind: AltitudeOfficeAttachResumePolicy.bindingKind,
            command: command,
            cwd: normalized(environment["CMUX_AGENT_LAUNCH_CWD"] ?? environment["PWD"]),
            checkpointId: sessionID,
            source: "process-detected",
            environment: nil,
            autoResume: true,
            updatedAt: capturedAt
        )
    }

    private static func normalizedSessionID(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 256 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private static func normalized(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
