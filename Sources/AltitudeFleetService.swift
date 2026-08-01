import Foundation

actor AltitudeFleetService {
    enum ServiceError: LocalizedError {
        case missingFleetLayer
        case missingNode
        case timedOut
        case commandFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .missingFleetLayer:
                return String(localized: "altitude.error.fleetUnavailable", defaultValue: "Altitude fleet projection is unavailable")
            case .missingNode:
                return String(localized: "altitude.error.nodeMissing", defaultValue: "Altitude cannot find the Node runtime used by fleet-layer")
            case .timedOut:
                return String(localized: "altitude.error.timedOut", defaultValue: "Altitude fleet refresh timed out")
            case .commandFailed(_, let message):
                return message.isEmpty
                    ? String(localized: "altitude.error.refreshFailed", defaultValue: "Altitude fleet refresh failed")
                    : message
            }
        }
    }

    private final class PipeCapture: @unchecked Sendable {
        var data = Data()
    }

    private let scriptURL: URL?
    private let viewerID: String
    private let timeoutSeconds: TimeInterval

    init(scriptURL: URL?, viewerID: String, timeoutSeconds: TimeInterval = 15) {
        self.scriptURL = scriptURL
        self.viewerID = viewerID
        self.timeoutSeconds = timeoutSeconds
    }

    func fetch(priorityBySessionId: [String: String]) async throws -> AltitudeNextUpSnapshot {
        guard let scriptURL else { throw ServiceError.missingFleetLayer }
        guard let nodeURL = Self.nodeExecutableURL() else { throw ServiceError.missingNode }
        let priorityData = try JSONSerialization.data(withJSONObject: priorityBySessionId, options: [.sortedKeys])
        let priorityJSON = String(decoding: priorityData, as: UTF8.self)
        let output = try await Self.runFleetLayer(
            nodeURL: nodeURL,
            scriptPath: scriptURL.path,
            viewerID: viewerID,
            priorityJSON: priorityJSON,
            timeoutSeconds: timeoutSeconds
        )
        return try JSONDecoder().decode(AltitudeNextUpSnapshot.self, from: output)
    }

    private static func nodeExecutableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let override = environment["CMUX_ALTITUDE_NODE"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/node" })
        }
        return candidates.lazy
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func runFleetLayer(
        nodeURL: URL,
        scriptPath: String,
        viewerID: String,
        priorityJSON: String,
        timeoutSeconds: TimeInterval
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "com.cmuxterm.altitude.fleet-process", qos: .utility).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let outputCapture = PipeCapture()
                let errorCapture = PipeCapture()
                let readers = DispatchGroup()
                let terminated = DispatchSemaphore(value: 0)

                process.executableURL = nodeURL
                process.arguments = [
                    scriptPath, "next-up",
                    "--viewer-id", viewerID,
                    "--priority-json", priorityJSON,
                ]
                process.standardOutput = stdout
                process.standardError = stderr
                process.terminationHandler = { _ in terminated.signal() }

                readers.enter()
                DispatchQueue.global(qos: .utility).async {
                    outputCapture.data = stdout.fileHandleForReading.readDataToEndOfFile()
                    readers.leave()
                }
                readers.enter()
                DispatchQueue.global(qos: .utility).async {
                    errorCapture.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    readers.leave()
                }

                do {
                    try process.run()
                } catch {
                    stdout.fileHandleForReading.closeFile()
                    stderr.fileHandleForReading.closeFile()
                    _ = readers.wait(timeout: .now() + 1)
                    continuation.resume(throwing: error)
                    return
                }

                guard terminated.wait(timeout: .now() + timeoutSeconds) == .success else {
                    process.terminate()
                    _ = terminated.wait(timeout: .now() + 2)
                    stdout.fileHandleForReading.closeFile()
                    stderr.fileHandleForReading.closeFile()
                    _ = readers.wait(timeout: .now() + 1)
                    continuation.resume(throwing: ServiceError.timedOut)
                    return
                }

                _ = readers.wait(timeout: .now() + 2)
                let error = String(decoding: errorCapture.data, as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: ServiceError.commandFailed(
                            process.terminationStatus,
                            error.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                    return
                }
                continuation.resume(returning: outputCapture.data)
            }
        }
    }
}
