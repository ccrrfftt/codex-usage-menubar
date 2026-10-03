import Foundation
import SQLite3

struct ScopedThreadIndexResult: Sendable {
    let threads: [AccountingThreadDescriptor]
    let isComplete: Bool
    let issues: Set<AccountingIssue>
}

protocol ThreadIndexReading: Sendable {
    func read(allowedRoots: [String], limit: Int,
              shouldContinue: @escaping @Sendable () -> Bool) throws -> ScopedThreadIndexResult
    func read(allowedRoots: [String], limit: Int, trackingStart: Date?,
              shouldContinue: @escaping @Sendable () -> Bool) throws -> ScopedThreadIndexResult
}

extension ThreadIndexReading {
    func read(allowedRoots: [String], limit: Int, trackingStart: Date?,
              shouldContinue: @escaping @Sendable () -> Bool) throws -> ScopedThreadIndexResult {
        let result = try read(allowedRoots: allowedRoots, limit: limit, shouldContinue: shouldContinue)
        guard let trackingStart else { return result }
        guard trackingStart.timeIntervalSince1970.isFinite else { throw ThreadIndexError.queryFailed }
        return ScopedThreadIndexResult(threads: result.threads.filter {
            max($0.createdAt, $0.updatedAt) >= trackingStart.timeIntervalSince1970
        }, isComplete: result.isComplete, issues: result.issues)
    }
}

enum ThreadIndexError: Error, Sendable { case unavailable, unsupportedSchema, interrupted, queryFailed }

/// Lexical component boundaries avoid filesystem enumeration and symlink walks.
enum AccountingPathScope {
    static func normalized(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func roots(_ paths: [String]) -> [String] {
        let sorted = Set(paths.compactMap(normalized)).sorted()
        return sorted.filter { candidate in
            !sorted.contains { other in other != candidate && contains(candidate, roots: [other]) }
        }
    }

    static func contains(_ path: String, roots: [String]) -> Bool {
        guard let path = normalized(path) else { return false }
        return roots.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }
}

/// Pure path resolution; construction never checks or opens a user directory.
/// https://learn.chatgpt.com/docs/config-file/environment-variables
/// Custom config.toml sqlite_home is intentionally not parsed. An explicit
/// database URL or matching CODEX_SQLITE_HOME is required for that override.
struct CodexStateLocation: Sendable {
    let codexHome: URL
    let sqliteHome: URL
    var databaseURL: URL { sqliteHome.appendingPathComponent("state_5.sqlite") }
    var sessionRoots: [URL] { [codexHome.appendingPathComponent("sessions"), codexHome.appendingPathComponent("archived_sessions")] }

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        func location(_ value: String?, fallback: URL) -> URL {
            guard let value, !value.isEmpty, !value.contains("\0") else { return fallback }
            if value.hasPrefix("/") { return URL(fileURLWithPath: value).standardizedFileURL }
            return workingDirectory.appendingPathComponent(value).standardizedFileURL
        }
        codexHome = location(environment["CODEX_HOME"], fallback: homeDirectory.appendingPathComponent(".codex"))
        sqliteHome = location(environment["CODEX_SQLITE_HOME"], fallback: codexHome)
    }
}

/// Read-only projection of explicitly scoped thread metadata, never titles or
/// previews. No migrations, repair, unscoped fallback, or directory enumeration.
/// Public schema verified at openai/codex b741e480e203f037ca726bc2a76d99a8e8668e66:
/// state/src/sqlite.rs:38 (state_5.sqlite); state/migrations/0001_threads.sql;
/// 0021_thread_spawn_edges.sql; 0025_thread_timestamps_millis.sql;
/// 0039_threads_recency_at.sql. See https://github.com/openai/codex/tree/b741e480e203f037ca726bc2a76d99a8e8668e66/codex-rs/state
struct ScopedThreadIndex: ThreadIndexReading {
    let databaseURL: URL

    init(databaseURL: URL = CodexStateLocation().databaseURL) { self.databaseURL = databaseURL }

    func read(allowedRoots: [String], limit: Int = 1000,
              shouldContinue: @escaping @Sendable () -> Bool = { true }) throws -> ScopedThreadIndexResult {
        try read(allowedRoots: allowedRoots, limit: limit, trackingStart: nil, shouldContinue: shouldContinue)
    }

    func read(allowedRoots: [String], limit: Int = 1000, trackingStart: Date?,
              shouldContinue: @escaping @Sendable () -> Bool = { true }) throws -> ScopedThreadIndexResult {
        if let trackingStart {
            guard trackingStart.timeIntervalSince1970.isFinite, trackingStart.timeIntervalSince1970 >= 0,
                  trackingStart.timeIntervalSince1970 < 32_503_680_000 else { throw ThreadIndexError.queryFailed }
        }
        let roots = AccountingPathScope.roots(allowedRoots)
        guard !roots.isEmpty else { return ScopedThreadIndexResult(threads: [], isComplete: false, issues: [.scopeRequired]) }
        guard shouldContinue() else { throw ThreadIndexError.interrupted }
        // Root inputs cannot increase the SQLite variable count without bound.
        guard roots.count <= 128 else { throw ThreadIndexError.queryFailed }
        let url = databaseURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
              url.resolvingSymlinksInPath().path == url.path else { throw ThreadIndexError.unavailable }
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard opened == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw ThreadIndexError.unavailable
        }
        defer { sqlite3_close(db) }
        guard sqlite3_db_readonly(db, "main") == 1 else { throw ThreadIndexError.queryFailed }
        // No extension loading, temp tables, or write-capable PRAGMAs are used.
        sqlite3_busy_timeout(db, 100)
        let progress = IndexProgress(shouldContinue)
        let context = Unmanaged.passRetained(progress).toOpaque()
        sqlite3_progress_handler(db, 200, { pointer in
            guard let pointer else { return 1 }
            return Unmanaged<IndexProgress>.fromOpaque(pointer).takeUnretainedValue().shouldContinue() ? 0 : 1
        }, context)
        defer {
            sqlite3_progress_handler(db, 0, nil, nil)
            Unmanaged<IndexProgress>.fromOpaque(context).release()
        }
        try executeReadSetup("PRAGMA query_only = ON", db: db)
        try executeReadSetup("PRAGMA trusted_schema = OFF", db: db)
        let columns = try tableColumns("threads", db: db)
        let required: [String: String] = ["id": "TEXT", "rollout_path": "TEXT", "cwd": "TEXT",
            "model_provider": "TEXT", "source": "TEXT", "created_at": "INTEGER", "updated_at": "INTEGER"]
        guard required.allSatisfy({ columns[$0.key] == $0.value }) else { throw ThreadIndexError.unsupportedSchema }
        for name in ["created_at_ms", "updated_at_ms", "recency_at", "recency_at_ms"] {
            if let type = columns[name], type != "INTEGER" { throw ThreadIndexError.unsupportedSchema }
        }
        let edges = try tableColumns("thread_spawn_edges", db: db)
        let hasEdges = edges["parent_thread_id"] == "TEXT" && edges["child_thread_id"] == "TEXT"
        if !edges.isEmpty && !hasEdges { throw ThreadIndexError.unsupportedSchema }

        // Timestamps are projected as seconds without losing the newer millisecond precision.
        func seconds(_ name: String) -> String {
            let old = "t.\(name)"
            return columns[name + "_ms"] == nil ? old : "COALESCE(t.\(name)_ms / 1000.0, \(old))"
        }
        let created = seconds("created_at"), updated = seconds("updated_at")
        let recency = columns["recency_at"] == nil ? updated : "CASE WHEN t.recency_at > 0 THEN \(seconds("recency_at")) ELSE \(updated) END"
        // Derive a boolean marker in SQL; never retrieve the source JSON or an
        // ancestor ID. The descriptor only needs non-nil to exclude child rows
        // from the three root conversation slots. Agent usage remains included.
        // Structured SessionSource values serialize as JSON objects. Also
        // recognize plain string markers defensively, without substring-matching
        // unrelated custom source names such as "custom-subagent-tool".
        let subagentMarker = "(trim(lower(t.source)) = 'subagent' OR instr(lower(t.source), '\"subagent\"') > 0)"
        let child = hasEdges
            ? "CASE WHEN EXISTS(SELECT 1 FROM thread_spawn_edges e WHERE e.child_thread_id = t.id) OR \(subagentMarker) THEN '' ELSE NULL END"
            : "CASE WHEN \(subagentMarker) THEN '' ELSE NULL END"
        let clauses = roots.map { _ in "(t.cwd = ? COLLATE BINARY OR (t.cwd >= ? COLLATE BINARY AND t.cwd < ? COLLATE BINARY))" }
        let activeClause = trackingStart == nil ? "" : "AND (\(updated) >= ? OR \(created) >= ?)"
        let sql = """
        SELECT t.id, t.rollout_path, t.cwd, \(created), \(updated), \(recency), \(child)
        FROM threads t
        WHERE t.model_provider = ? AND trim(lower(t.source)) <> 'internal'
          AND instr(lower(t.source), '\"internal\"') = 0
          AND instr('/' || t.cwd || '/', '/../') = 0
          AND (\(clauses.joined(separator: " OR ")))
          \(activeClause)
        ORDER BY \(recency) DESC, t.id DESC
        LIMIT ?
        """
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        var parameter: Int32 = 1
        func bind(_ value: String) throws {
            guard sqlite3_bind_text(statement, parameter, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw ThreadIndexError.queryFailed }
            parameter += 1
        }
        // Provider names are configuration keys; this excludes non-OpenAI usage
        // but does not establish the ChatGPT account or subscription behind it.
        try bind("openai")
        for root in roots {
            try bind(root)
            try bind(root == "/" ? "/" : root + "/")
            try bind(root == "/" ? "0" : root + "0")
        }
        if let trackingStart {
            let start = trackingStart.timeIntervalSince1970
            guard sqlite3_bind_double(statement, parameter, start) == SQLITE_OK,
                  sqlite3_bind_double(statement, parameter + 1, start) == SQLITE_OK else { throw ThreadIndexError.queryFailed }
            parameter += 2
        }
        let boundedLimit = max(1, min(1000, limit))
        guard sqlite3_bind_int(statement, parameter, Int32(boundedLimit + 1)) == SQLITE_OK else { throw ThreadIndexError.queryFailed }
        var threads: [AccountingThreadDescriptor] = []
        var issues = Set<AccountingIssue>()
        while true {
            guard shouldContinue() else { throw ThreadIndexError.interrupted }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            if status == SQLITE_INTERRUPT { throw ThreadIndexError.interrupted }
            guard status == SQLITE_ROW else { throw ThreadIndexError.queryFailed }
            if threads.count == boundedLimit { issues.insert(.threadLimitReached); break }
            guard let id = text(statement, 0), !id.isEmpty,
                  let path = text(statement, 1), let cwd = text(statement, 2),
                  AccountingPathScope.contains(cwd, roots: roots),
                  (3...5).allSatisfy({ sqlite3_column_type(statement, Int32($0)) == SQLITE_INTEGER || sqlite3_column_type(statement, Int32($0)) == SQLITE_FLOAT }) else {
                issues.insert(.invalidRecord); continue
            }
            let createdAt = sqlite3_column_double(statement, 3), updatedAt = sqlite3_column_double(statement, 4)
            let recencyAt = sqlite3_column_double(statement, 5)
            guard [createdAt, updatedAt, recencyAt].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 32_503_680_000 }) else { issues.insert(.invalidRecord); continue }
            threads.append(AccountingThreadDescriptor(id: id, name: nil, cwd: cwd, path: path,
                createdAt: createdAt, updatedAt: updatedAt, recencyAt: recencyAt, forkedFromId: nil,
                parentThreadId: text(statement, 6)))
        }
        return ScopedThreadIndexResult(threads: threads, isComplete: issues.isEmpty, issues: issues)
    }

    private func tableColumns(_ table: String, db: OpaquePointer) throws -> [String: String] {
        // Names are fixed call-site literals, never input or database-provided SQL.
        guard ["threads", "thread_spawn_edges"].contains(table) else { throw ThreadIndexError.queryFailed }
        let kind = try prepare("SELECT type FROM sqlite_schema WHERE name = ? LIMIT 1", db: db)
        defer { sqlite3_finalize(kind) }
        guard sqlite3_bind_text(kind, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw ThreadIndexError.queryFailed }
        let kindStatus = sqlite3_step(kind)
        if kindStatus == SQLITE_DONE { return [:] }
        if kindStatus == SQLITE_INTERRUPT { throw ThreadIndexError.interrupted }
        guard kindStatus == SQLITE_ROW, text(kind, 0) == "table" else { throw ThreadIndexError.unsupportedSchema }
        let statement = try prepare("PRAGMA table_info(\(table))", db: db)
        defer { sqlite3_finalize(statement) }
        var result: [String: String] = [:]
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            if status == SQLITE_INTERRUPT { throw ThreadIndexError.interrupted }
            guard status == SQLITE_ROW, let name = text(statement, 1), let type = text(statement, 2) else { throw ThreadIndexError.queryFailed }
            result[name] = type.uppercased()
        }
    }

    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw status == SQLITE_INTERRUPT ? ThreadIndexError.interrupted : ThreadIndexError.queryFailed
        }
        return statement
    }

    private func executeReadSetup(_ sql: String, db: OpaquePointer) throws {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ThreadIndexError.queryFailed }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let value = sqlite3_column_text(statement, column) else { return nil }
        let size = Int(sqlite3_column_bytes(statement, column))
        guard size <= 32_768 else { return nil }
        return String(bytes: UnsafeBufferPointer(start: value, count: size), encoding: .utf8)
    }
}

private final class IndexProgress {
    let shouldContinue: @Sendable () -> Bool
    init(_ check: @escaping @Sendable () -> Bool) { shouldContinue = check }
}
