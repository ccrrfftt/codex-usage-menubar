import Foundation

// Opt-in developer check: one quota read, no account values written to output.
@main
struct LiveCompatibilityCheck {
    static func main() async throws {
        let files = FileManager.default
        let runtime = files.temporaryDirectory.appendingPathComponent("codex-usage-live-check-" + UUID().uuidString)
        defer { try? files.removeItem(at: runtime) }
        let executable = try CodexConnection.findExecutable()
        let package = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("codex-package.json")
        struct PackageInfo: Decodable { let version: String }
        if let bytes = try? Data(contentsOf: package),
           let info = try? JSONDecoder().decode(PackageInfo.self, from: bytes) {
            print("Detected Codex CLI: \(info.version)")
        }
        let snapshot = try await CodexConnection(runtime: runtime).read()
        guard snapshot.main?.headline?.remaining != nil else { throw QuotaError.malformed }
        print("PASS: production CLI discovery and live quota decoding")
        print("Reset-card balance provided: \(snapshot.resetCardCount != nil)")
        print("Included-usage permission provided: \(snapshot.ordinaryUsageAllowed != nil)")
    }
}
