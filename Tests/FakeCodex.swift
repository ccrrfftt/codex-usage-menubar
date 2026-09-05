import Foundation
import Darwin

// Local subprocess fixture. It never contacts Codex or the network.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mode = (try? String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8)) ?? "normal"
if mode == "stubborn" { signal(SIGTERM, SIG_IGN) }
try String(getpid()).write(to: root.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
var requests = ""
while let line = readLine() {
    guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let method = object["method"] as? String else { exit(2) }
    requests += method + "\n"
    try requests.write(to: root.appendingPathComponent("requests"), atomically: true, encoding: .utf8)
    guard let id = object["id"] as? Int else { continue }
    if mode == "slow" { usleep(250_000) }
    if method == "account/rateLimits/read" && ["hang", "stubborn"].contains(mode) { sleep(30) }
    if method == "account/rateLimits/read" && mode == "unrelated" {
        print(#"{"id":999,"result":"an unrelated response"}"#)
        print(#"{"id":"server-request","method":"unrelated","params":{}}"#)
    }
    if method == "account/rateLimits/read" && mode == "malformed" {
        print("invalid JSON")
        fflush(stdout)
        continue
    }
    let response: [String: Any]
    if method == "initialize" {
        print(#"{"method":"notification","params":{"ignored":true}}"#)
        response = ["id": id, "result": [String: String]()]
    } else if method == "account/rateLimits/read" && mode == "error" {
        response = ["id": id, "error": ["code": -1, "message": "private upstream detail"]]
    } else if method == "account/rateLimits/read" {
        response = ["id": id, "result": ["rateLimits": ["primary": ["usedPercent": 65]]]]
    } else { exit(3) }
    fflush(stdout)
    var bytes = try JSONSerialization.data(withJSONObject: response)
    bytes.append(10)
    // Also exercise a response split across pipe reads.
    let split = bytes.count / 2
    try FileHandle.standardOutput.write(contentsOf: bytes.prefix(split))
    usleep(1_000)
    try FileHandle.standardOutput.write(contentsOf: bytes.suffix(from: split))
}
