import Foundation
import Darwin

// Fully synthetic local fixture. No network or real Codex files are accessed.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mode = (try? String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8)) ?? "normal"
let starts = root.appendingPathComponent("starts")
let previous = (try? String(contentsOf: starts, encoding: .utf8)) ?? ""
try (previous + "start\n").write(to: starts, atomically: true, encoding: .utf8)
var requests: [String] = []
while let line = readLine() {
    let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let method = request["method"] as! String
    requests.append(method)
    try requests.joined(separator: "\n").write(to: root.appendingPathComponent("requests"), atomically: true, encoding: .utf8)
    guard let id = request["id"] as? Int else { continue }
    let params = request["params"] as? [String: Any] ?? [:]
    var result: [String: Any] = [:]
    switch method {
    case "initialize": break
    case "account/rateLimits/read":
        result = ["accountId": "fixture-account", "rateLimits": ["primary": ["usedPercent": 20]]]
    case "account/usage/read":
        if mode == "usage-error" {
            print("{\"id\":\(id),\"error\":{\"code\":-1,\"message\":\"synthetic\"}}")
            fflush(stdout); continue
        }
        result = ["summary": ["lifetimeTokens": 1000], "dailyUsageBuckets": [["startDate": "2026-10-02", "tokens": 300]]]
        if let thread = params["threadId"] as? String {
            guard ["fixture-current", "fixture-archived"].contains(thread) else { exit(10) }
            result["threadUsage"] = ["threadId": thread, "estimatedUsageCreditsMicros": 100,
                "groups": [["model": "fixture-model", "inputTokens": 100, "cachedInputTokens": 20,
                            "outputTokens": 10, "totalTokens": 110, "estimatedUsageCreditsMicros": 100]]]
        }
    case "thread/list":
        guard params["cwd"] as? [String] == ["/fixture/project"], params["useStateDbOnly"] as? Bool == true,
              params["sourceKinds"] as? [String] == ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther"] else { exit(11) }
        let archived = params["archived"] as? Bool == true
        let thread = archived ? "fixture-archived" : "fixture-current"
        let valid: [String: Any] = ["id": thread, "name": "Fixture", "cwd": "/fixture/project",
            "path": root.appendingPathComponent("sessions/" + thread + ".jsonl").path, "createdAt": 0, "updatedAt": archived ? 1 : 2]
        let rejected: [String: Any] = ["id": "wrong-cwd", "cwd": "/not-selected", "path": "/not-opened.jsonl", "createdAt": 0, "updatedAt": 3]
        result = ["data": [valid, rejected], "nextCursor": NSNull()]
    default: exit(12)
    }
    let data = try JSONSerialization.data(withJSONObject: ["id": id, "result": result])
    try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
}
