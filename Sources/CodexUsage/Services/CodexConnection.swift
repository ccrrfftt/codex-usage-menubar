import Foundation
import Darwin

enum QuotaError: LocalizedError {
    case unavailable, disconnected, timedOut, account, malformed
    var errorDescription: String? {
        switch self {
        case .unavailable: "未找到 Codex，请先安装桌面应用。"
        case .disconnected: "用量连接已中断，稍后自动重试。"
        case .timedOut: "用量查询超时，请检查网络。"
        case .account: "请确认 Codex 已登录 ChatGPT 账户。"
        case .malformed: "暂时无法识别服务返回的用量数据。"
        }
    }
}

/// All connection state lives on one queue. Only initialization and quota reads are sent.
final class CodexConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.codexusage.connection", qos: .utility)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var serial = 0

    func read() async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.process?.isRunning != true { try self.start() }
                    let result = try self.call("account/rateLimits/read")
                    let bytes = try JSONSerialization.data(withJSONObject: result)
                    continuation.resume(returning: try JSONDecoder().decode(QuotaSnapshot.self, from: bytes))
                } catch {
                    self.close()
                    continuation.resume(throwing: error is QuotaError ? error : QuotaError.disconnected)
                }
            }
        }
    }

    func stop() { queue.async { self.close() } }

    private func start() throws {
        close()
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw QuotaError.unavailable
        }
        let runtime = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.codexusage.menubar/runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let quoted = String(data: try encoder.encode(runtime.path), encoding: .utf8)!
        let proc = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = ["app-server", "--listen", "stdio://", "-c", "sqlite_home=" + quoted,
                          "-c", "log_dir=" + quoted, "-c", "analytics.enabled=false"]
        proc.currentDirectoryURL = runtime
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        buffer.removeAll(keepingCapacity: true)
        _ = try call("initialize", params: ["clientInfo": [
            "name": "codex_usage_menubar", "title": "Codex Usage Menu Bar", "version": "1.0.0"
        ]])
        try send(["method": "initialized"])
    }

    private func send(_ object: [String: Any]) throws {
        guard process?.isRunning == true, let input else { throw QuotaError.disconnected }
        var bytes = try JSONSerialization.data(withJSONObject: object)
        bytes.append(10)
        try input.write(contentsOf: bytes)
    }

    private func call(_ method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        guard ["initialize", "account/rateLimits/read"].contains(method) else { throw QuotaError.malformed }
        serial += 1
        var request: [String: Any] = ["method": method, "id": serial]
        if let params { request["params"] = params }
        try send(request)
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        while true {
            let line = try readLine(deadline: deadline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["method"] == nil, let responseID = object["id"] as? Int, responseID == serial else { continue }
            if object["error"] != nil { throw QuotaError.account }
            guard let result = object["result"] as? [String: Any] else { throw QuotaError.malformed }
            return result
        }
    }

    private func readLine(deadline: TimeInterval) throws -> Data {
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                return line
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw QuotaError.timedOut }
            guard let output, process?.isRunning == true else { throw QuotaError.disconnected }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, Int32(min(1000, remaining * 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw QuotaError.disconnected
            }
            if ready == 0 { continue }
            let bytes = output.availableData
            guard !bytes.isEmpty else { throw QuotaError.disconnected }
            buffer.append(bytes)
            guard buffer.count <= 4_000_000 else { throw QuotaError.malformed }
        }
    }

    private func close() {
        // Closing stdin first also lets app-server exit if this app is terminated.
        try? input?.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? output?.close()
        output = nil
        buffer.removeAll(keepingCapacity: false)
    }
}
