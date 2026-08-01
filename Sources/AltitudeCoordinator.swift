import Foundation
import Observation

@MainActor
@Observable
final class AltitudeCoordinator {
    private(set) var snapshot: AltitudeNextUpSnapshot = .empty
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    private let service: AltitudeFleetService
    private let refreshInterval: Duration
    private var refreshTask: Task<Void, Never>?

    init(service: AltitudeFleetService, refreshInterval: Duration = .seconds(10)) {
        self.service = service
        self.refreshInterval = refreshInterval
    }

    func start(priorityProvider: @escaping @MainActor @Sendable () -> [String: String]) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh(priorityBySessionId: priorityProvider())
                do {
                    // The refresh cadence is the intended behavior, not a synchronization poll.
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(priorityBySessionId: [String: String]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await service.fetch(priorityBySessionId: priorityBySessionId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
