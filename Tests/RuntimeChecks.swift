import Combine
import Foundation
import Darwin

private actor ControlledReader: QuotaReading {
    private(set) var requests = 0
    private var pending: [Int: CheckedContinuation<QuotaSnapshot, Error>] = [:]

    func read() async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            pending[requests] = continuation
            requests += 1
        }
    }

    // Deliberately allows a late reply after cancellation to exercise stale-result rejection.
    func resolve(_ id: Int, _ result: Result<QuotaSnapshot, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}

@MainActor
private final class TestClock { var value: TimeInterval = 1000 }

@main @MainActor
struct RuntimeChecks {
    private static var checked = 0

    static func check(_ success: Bool, _ label: String) {
        precondition(success, "FAILED: " + label)
        checked += 1
        print("PASS: " + label)
    }

    static func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw QuotaError.timedOut
    }

    static func snapshot(used: Int) throws -> QuotaSnapshot {
        try JSONDecoder().decode(QuotaSnapshot.self,
                                 from: Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(used)}}}".utf8))
    }

    static func checkStore() async throws {
        let reader = ControlledReader(), clock = TestClock()
        let store = UsageStore(connection: reader, monitor: nil, startImmediately: false, uptime: { clock.value })
        defer { store.stop() }
        var publications = 0, menuUpdates = 0
        let observation = store.$state.dropFirst().sink { _ in publications += 1 }
        let menuObservation = store.$state.map(\.statusItem).removeDuplicates().sink { _ in menuUpdates += 1 }
        defer { observation.cancel(); menuObservation.cancel() }
        store.refresh()
        store.refresh()
        try await waitFor { await reader.requests == 1 }
        check(await reader.requests == 1, "simultaneous refresh triggers share one request")
        await reader.resolve(0, .success(try snapshot(used: 65)))
        try await waitFor { !store.state.isRefreshing }
        check(publications == 2 && store.state.remaining == 35, "successful refresh publishes exactly start and coherent completion")
        clock.value += 30
        store.prepareForDisplay()
        await Task.yield()
        check(await reader.requests == 1 && menuUpdates == 3, "opening a fresh panel neither queries nor rewrites the menu bar")
        clock.value += 31
        store.prepareForDisplay()
        try await waitFor { await reader.requests == 2 }
        await reader.resolve(1, .failure(QuotaError.timedOut))
        try await waitFor { !store.state.isRefreshing }
        check(store.state.remaining == 35 && store.state.stale && store.state.lastError != nil,
              "failure preserves and marks the last successful snapshot")
        clock.value += 61
        store.prepareForDisplay()
        await Task.yield()
        check(await reader.requests == 2, "opening the panel respects failure backoff")
        clock.value += 60
        store.prepareForDisplay()
        try await waitFor { await reader.requests == 3 }
        var offline = EnergyState(); offline.networkAvailable = false
        store.updateSystemState(offline)
        check(!store.state.isRefreshing, "going offline clears the cancelled request state immediately")
        clock.value += 6
        store.updateSystemState(EnergyState())
        try await waitFor { await reader.requests == 4 }
        await reader.resolve(2, .success(try snapshot(used: 99)))
        try await Task.sleep(for: .milliseconds(20))
        check(store.state.isRefreshing && store.state.remaining == 35, "late cancelled reply cannot overwrite a reconnect request")
        await reader.resolve(3, .success(try snapshot(used: 10)))
        try await waitFor { !store.state.isRefreshing }
        check(store.state.remaining == 90 && store.state.lastError == nil, "reconnect commits only the new successful result")
        clock.value += 61
        store.refresh()
        try await waitFor { await reader.requests == 5 }
        store.stop()
        store.refresh()
        await reader.resolve(4, .success(try snapshot(used: 99)))
        try await Task.sleep(for: .milliseconds(20))
        let finalRequests = await reader.requests
        check(store.state.remaining == 90 && finalRequests == 5, "stop cancels pending work and rejects further refreshes")
    }

    static func checkProcess() async throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-usage-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func directory(_ name: String, mode: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try mode.write(to: url.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
            return url
        }
        func contents(_ file: URL) -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
        let normal = try directory("normal", mode: "normal")
        let client = CodexConnection(executable: executable, runtime: normal)
        check(try await client.read().main?.headline?.remaining == 35, "subprocess handles notifications and split JSON responses")
        check(contents(normal.appendingPathComponent("requests")) == "initialize\ninitialized\naccount/rateLimits/read\n",
              "subprocess sends only handshake and read-only quota request")
        let descriptorsBefore = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        for _ in 0..<8 { _ = try await client.read() }
        try await Task.sleep(for: .milliseconds(100))
        let descriptorsAfter = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        check(descriptorsAfter <= descriptorsBefore + 2, "repeated reads do not accumulate pipe descriptors")
        let hung = try directory("hung", mode: "hang")
        let hungClient = CodexConnection(executable: executable, runtime: hung)
        let pending = Task { try await hungClient.read() }
        try await waitFor { contents(hung.appendingPathComponent("requests")).contains("account/rateLimits/read") }
        let start = ProcessInfo.processInfo.systemUptime
        pending.cancel()
        var wasCancelled = false
        do { _ = try await pending.value } catch is CancellationError { wasCancelled = true }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        check(wasCancelled && elapsed < 1, "cancellation interrupts a blocked read in under one second")
        let pid = Int32(contents(hung.appendingPathComponent("pid")))!
        try await waitFor { kill(pid, 0) != 0 }
        check(kill(pid, 0) != 0, "cancelled query process exits")
        try "normal".write(to: hung.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        check(try await hungClient.read().main?.headline?.remaining == 35, "connection remains reusable after cancellation")
        let slow = try directory("slow", mode: "slow")
        var timedOut = false
        do { _ = try await CodexConnection(executable: executable, runtime: slow, timeout: 0.4).read() }
        catch QuotaError.timedOut { timedOut = true }
        check(timedOut, "handshake and quota read share a single total deadline")
        let malformed = try directory("malformed", mode: "malformed")
        var malformedRejected = false
        do { _ = try await CodexConnection(executable: executable, runtime: malformed).read() }
        catch QuotaError.malformed { malformedRejected = true }
        check(malformedRejected, "malformed responses fail without waiting for the timeout")
        let denied = try directory("denied", mode: "error")
        var safeError = false
        do { _ = try await CodexConnection(executable: executable, runtime: denied).read() }
        catch QuotaError.account { safeError = true }
        check(safeError, "upstream error details do not escape into the UI")
        print(String(format: "Blocked read cancellation: %.3f seconds; file descriptors: %d -> %d", elapsed, descriptorsBefore, descriptorsAfter))
    }

    static func main() async throws {
        try await checkStore()
        try await checkProcess()
        print("\(checked) runtime checks passed.")
    }
}
