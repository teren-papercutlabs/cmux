import Foundation

actor AltitudeFleetService {
    enum ServiceError: LocalizedError {
        case missingFleetLayer
        case commandFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .missingFleetLayer:
                return "Altitude fleet projection is unavailable"
            case .commandFailed(_, let message):
                return message.isEmpty ? "Altitude fleet refresh failed" : message
            }
        }
    }

    private let scriptURL: URL?
    private let viewerID: String

    init(scriptURL: URL?, viewerID: String) {
        self.scriptURL = scriptURL
        self.viewerID = viewerID
    }

    func fetch(priorityBySessionId: [String: String]) async throws -> AltitudeNextUpSnapshot {
        guard let scriptURL else { throw ServiceError.missingFleetLayer }
        let priorityData = try JSONSerialization.data(withJSONObject: priorityBySessionId, options: [.sortedKeys])
        let priorityJSON = String(decoding: priorityData, as: UTF8.self)
        let scriptPath = scriptURL.path
        let viewerID = self.viewerID

        let output = try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "node", scriptPath, "next-up",
                "--viewer-id", viewerID,
                "--priority-json", priorityJSON,
            ]
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()

            // Drain both pipes while the child is running. Waiting first can
            // deadlock as soon as either pipe fills: the child cannot exit
            // until its write completes, while the parent is waiting for exit
            // before it starts reading.
            async let outputRead = stdout.fileHandleForReading.readToEnd()
            async let errorRead = stderr.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            let (outputData, errorData) = try await (outputRead, errorRead)
            let output = outputData ?? Data()
            let error = String(decoding: errorData ?? Data(), as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw ServiceError.commandFailed(process.terminationStatus, error.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value

        return try JSONDecoder().decode(AltitudeNextUpSnapshot.self, from: output)
    }
}
