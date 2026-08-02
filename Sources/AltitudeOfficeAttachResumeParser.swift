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

    /// Replay-time re-validation: the snapshot JSON is not a trust boundary.
    /// A stored binding may only auto-execute if its command still parses as
    /// the exact office-attach shape this parser would have captured, and its
    /// session id matches the stored checkpoint id.
    static func isRecognizedStoredCommand(
        _ command: String,
        checkpointId: String?,
        homeDirectory: String
    ) -> Bool {
        guard let argv = parseSingleQuotedArgv(command), argv.count == 4 else { return false }
        let basename = (argv[0] as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard basename == "node" || basename == "nodejs" else { return false }
        let expectedScript = (homeDirectory as NSString)
            .appendingPathComponent("pcl-client/office/dist/index.js")
        guard (argv[1] as NSString).standardizingPath == (expectedScript as NSString).standardizingPath,
              argv[2] == "a",
              let sessionID = normalizedSessionID(argv[3]) else {
            return false
        }
        guard let checkpointId else { return false }
        return sessionID == checkpointId
    }

    /// Strict inverse of `shellSingleQuoted`-joined argv: space-separated
    /// single-quoted words with the standard '\'' escape. Anything else —
    /// bare words, operators, subshells, extra whitespace — fails the parse.
    private static func parseSingleQuotedArgv(_ command: String) -> [String]? {
        var argv: [String] = []
        var current = ""
        var index = command.startIndex

        func expect(_ literal: String) -> Bool {
            guard command[index...].hasPrefix(literal) else { return false }
            index = command.index(index, offsetBy: literal.count)
            return true
        }

        while index < command.endIndex {
            guard expect("'") else { return nil }
            var closed = false
            while index < command.endIndex {
                let ch = command[index]
                if ch == "'" {
                    index = command.index(after: index)
                    if expect("\\''") {
                        current.append("'")
                        continue
                    }
                    closed = true
                    break
                }
                current.append(ch)
                index = command.index(after: index)
            }
            guard closed else { return nil }
            argv.append(current)
            current = ""
            if index < command.endIndex {
                guard expect(" ") else { return nil }
                guard index < command.endIndex else { return nil }
            }
        }
        return argv.isEmpty ? nil : argv
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
