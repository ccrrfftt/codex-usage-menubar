import Foundation
import SQLite3
import Darwin


private final class IndexCancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Bool { lock.lock(); defer { lock.unlock() }; value += 1; return value < 30 }
}

@main @MainActor struct ScopedThreadIndexChecks {
    static var count = 0
    static func check(_ value: Bool, _ label: String) {
        precondition(value, "FAILED: " + label); count += 1; print("PASS: " + label); fflush(stdout)
    }

    static func sql(_ db: OpaquePointer, _ value: String) throws {
        guard sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK else { throw FixtureError.failed }
    }

    enum FixtureError: Error { case failed }

    static func fixture(at url: URL, modern: Bool = true) throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db = handle else { throw FixtureError.failed }
        try sql(db, """
        CREATE TABLE threads (
          id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, cwd TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, model_provider TEXT NOT NULL,
          source TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
          title TEXT NOT NULL DEFAULT 'synthetic confidential title', preview TEXT DEFAULT 'synthetic ignored preview'
        );
        CREATE TABLE thread_spawn_edges(parent_thread_id TEXT NOT NULL, child_thread_id TEXT PRIMARY KEY, status TEXT NOT NULL);
        CREATE INDEX fixture_cwd ON threads(cwd);
        """)
        if modern {
            try sql(db, "ALTER TABLE threads ADD COLUMN created_at_ms INTEGER; ALTER TABLE threads ADD COLUMN updated_at_ms INTEGER; ALTER TABLE threads ADD COLUMN recency_at INTEGER NOT NULL DEFAULT 0; ALTER TABLE threads ADD COLUMN recency_at_ms INTEGER NOT NULL DEFAULT 0;")
        }
        return db
    }

    static func insert(_ db: OpaquePointer, id: String, cwd: String, provider: String = "openai", archived: Bool = false, source: String = "cli") throws {
        let query = "INSERT INTO threads(id,rollout_path,cwd,created_at,updated_at,model_provider,source,archived) VALUES(?,?,?,100,200,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw FixtureError.failed }
        defer { sqlite3_finalize(statement) }
        for (index, value) in [id, "/fixture-codex/sessions/" + id + ".jsonl", cwd, provider, source].enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw FixtureError.failed }
        }
        sqlite3_bind_int(statement, 6, archived ? 1 : 0)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.failed }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("scoped-index-fixtures-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state_5.sqlite")
        let db = try fixture(at: url)
        try insert(db, id: "root", cwd: "/fixture/project")
        try insert(db, id: "child", cwd: "/fixture/project/nested/deep")
        try insert(db, id: "archived", cwd: "/fixture/project/old", archived: true)
        try insert(db, id: "similar", cwd: "/fixture/project-other")
        try insert(db, id: "prefix", cwd: "/fixture/project2")
        try insert(db, id: "outside", cwd: "/elsewhere")
        try insert(db, id: "traversal", cwd: "/fixture/project/../elsewhere")
        try insert(db, id: "provider", cwd: "/fixture/project/alternate", provider: "amazon-bedrock")
        try insert(db, id: "internal", cwd: "/fixture/project/internal", source: #"{"internal":"guardian"}"#)
        try insert(db, id: "agent", cwd: "/fixture/project/nested", source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}"#)
        try sql(db, "INSERT INTO thread_spawn_edges VALUES('root','agent','complete'); UPDATE threads SET created_at_ms=100125,updated_at_ms=200250,recency_at=300,recency_at_ms=300750 WHERE id='archived';")
        sqlite3_close(db)
        let before = try Data(contentsOf: url)
        let index = ScopedThreadIndex(databaseURL: url)
        let scoped = try index.read(allowedRoots: ["/fixture/project/"], limit: 1000)
        check(Set(scoped.threads.map(\.id)) == ["root", "child", "archived", "agent"], "root and descendants match exact path components")
        check(scoped.threads.first?.id == "archived", "archived conversation participates in recency order")
        check(scoped.threads.first?.createdAt == 100.125 && scoped.threads.first?.recencyAt == 300.75, "millisecond timestamps retain precision")
        check(scoped.threads.allSatisfy { $0.name == nil }, "database titles and previews are not projected")
        check(scoped.threads.first { $0.id == "agent" }?.parentThreadId != nil, "derived subagent marker avoids ancestor identity reads")
        check(scoped.isComplete && scoped.issues.isEmpty, "bounded complete recursive index reports coverage")
        check(try Data(contentsOf: url) == before, "read-only index leaves the database unchanged")
        check(!FileManager.default.fileExists(atPath: url.path + "-journal"), "reader creates no rollback journal")
        let bounded = try index.read(allowedRoots: ["/fixture/project"], limit: 2)
        check(bounded.threads.count == 2 && !bounded.isComplete && bounded.issues.contains(.threadLimitReached), "row cap reports explicit partial coverage")
        let overlap = try index.read(allowedRoots: ["/fixture/project", "/fixture/project/nested"], limit: 1000)
        check(overlap.threads.count == scoped.threads.count, "overlapping roots do not duplicate rows")
        let missing = directory.appendingPathComponent("missing.sqlite")
        let empty = try ScopedThreadIndex(databaseURL: missing).read(allowedRoots: [], limit: 1000)
        check(empty.threads.isEmpty && empty.issues.contains(.scopeRequired) && !FileManager.default.fileExists(atPath: missing.path), "empty scope never opens or creates a database")
        do { _ = try ScopedThreadIndex(databaseURL: missing).read(allowedRoots: ["/fixture"], limit: 1000); check(false, "missing database should fail") }
        catch ThreadIndexError.unavailable { check(!FileManager.default.fileExists(atPath: missing.path), "missing database is not created") }
        let link = directory.appendingPathComponent("linked.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        do { _ = try ScopedThreadIndex(databaseURL: link).read(allowedRoots: ["/fixture"], limit: 1000); check(false, "symlink database should fail") }
        catch ThreadIndexError.unavailable { check(true, "symlink database path is rejected") }
        do { _ = try index.read(allowedRoots: ["/fixture"], limit: 1000, shouldContinue: { false }); check(false, "cancelled query should fail") }
        catch ThreadIndexError.interrupted { check(true, "cancellation prevents database open") }

        let edgeURL = directory.appendingPathComponent("edge.sqlite")
        let edgeDB = try fixture(at: edgeURL, modern: false)
        try insert(edgeDB, id: "literal", cwd: "/fixture/100%_safe/nested")
        try insert(edgeDB, id: "wildcard", cwd: "/fixture/100xyysafe/nested")
        try insert(edgeDB, id: "unicode", cwd: "/fixture/项目/子目录")
        try insert(edgeDB, id: "injection", cwd: "/fixture/' OR 1=1 --/nested")
        try insert(edgeDB, id: "other", cwd: "/outside")
        sqlite3_close(edgeDB)
        let edgeIndex = ScopedThreadIndex(databaseURL: edgeURL)
        let literal = try edgeIndex.read(allowedRoots: ["/fixture/100%_safe"], limit: 1000)
        check(literal.threads.map(\.id) == ["literal"], "percent and underscore remain literal path characters")
        check(literal.threads.first?.updatedAt == 200, "legacy second timestamps remain supported")
        check(try edgeIndex.read(allowedRoots: ["/fixture/项目"], limit: 1000).threads.map(\.id) == ["unicode"], "Unicode root boundaries remain exact")
        check(try edgeIndex.read(allowedRoots: ["/fixture/' OR 1=1 --"], limit: 1000).threads.map(\.id) == ["injection"], "bound roots cannot inject SQL")
        let malformedURL = directory.appendingPathComponent("unsupported.sqlite")
        var malformed: OpaquePointer?
        sqlite3_open(malformedURL.path, &malformed)
        try sql(malformed!, "CREATE TABLE threads(id TEXT,cwd TEXT,title TEXT)")
        sqlite3_close(malformed)
        do { _ = try ScopedThreadIndex(databaseURL: malformedURL).read(allowedRoots: ["/fixture"], limit: 1000); check(false, "unsupported schema should fail") }
        catch ThreadIndexError.unsupportedSchema { check(true, "missing required columns fail closed without migration") }

        let viewURL = directory.appendingPathComponent("view.sqlite")
        var viewDB: OpaquePointer?
        sqlite3_open(viewURL.path, &viewDB)
        try sql(viewDB!, "CREATE VIEW threads AS SELECT 'id' AS id;")
        sqlite3_close(viewDB)
        do { _ = try ScopedThreadIndex(databaseURL: viewURL).read(allowedRoots: ["/fixture"], limit: 1000); check(false, "view schema should fail") }
        catch ThreadIndexError.unsupportedSchema { check(true, "schema views cannot masquerade as the official table") }
        let futureURL = directory.appendingPathComponent("future.sqlite")
        let futureDB = try fixture(at: futureURL, modern: false)
        try insert(futureDB, id: "future", cwd: "/fixture/project")
        try sql(futureDB, "UPDATE threads SET created_at=32503680001;")
        sqlite3_close(futureDB)
        let future = try ScopedThreadIndex(databaseURL: futureURL).read(allowedRoots: ["/fixture/project"], limit: 1000)
        check(future.threads.isEmpty && !future.isComplete && future.issues.contains(.invalidRecord), "absurd timestamps are rejected rather than guessed")
        let busyURL = directory.appendingPathComponent("busy.sqlite")
        let busyDB = try fixture(at: busyURL)
        try insert(busyDB, id: "busy", cwd: "/fixture/project")
        try sql(busyDB, "BEGIN EXCLUSIVE")
        let began = ProcessInfo.processInfo.systemUptime
        do { _ = try ScopedThreadIndex(databaseURL: busyURL).read(allowedRoots: ["/fixture"], limit: 1000); check(false, "locked database should fail") }
        catch { check(ProcessInfo.processInfo.systemUptime - began < 2, "busy database wait is bounded well below refresh deadline") }
        try sql(busyDB, "ROLLBACK")
        try sql(busyDB, "WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<5000) INSERT INTO threads(id,rollout_path,cwd,created_at,updated_at,model_provider,source) SELECT 'row-'||i,'/fixture-codex/sessions/row-'||i||'.jsonl','/fixture/project/'||i,100,200,'openai','cli' FROM n;")
        sqlite3_close(busyDB)
        let counter = IndexCancellationCounter()
        do { _ = try ScopedThreadIndex(databaseURL: busyURL).read(allowedRoots: ["/fixture"], limit: 1000, shouldContinue: { counter.next() }); check(false, "in-flight cancellation should fail") }
        catch ThreadIndexError.interrupted { check(true, "SQLite progress handler interrupts an active query") }
        let walURL = directory.appendingPathComponent("wal.sqlite")
        let walDB = try fixture(at: walURL)
        try sql(walDB, "PRAGMA journal_mode=WAL;")
        try insert(walDB, id: "wal-row", cwd: "/fixture/project")
        let walBefore = try Data(contentsOf: URL(fileURLWithPath: walURL.path + "-wal"))
        let walResult = try ScopedThreadIndex(databaseURL: walURL).read(allowedRoots: ["/fixture"], limit: 1000)
        check(walResult.threads.map(\.id) == ["wal-row"], "read-only connection sees committed WAL records")
        check(try Data(contentsOf: URL(fileURLWithPath: walURL.path + "-wal")) == walBefore, "index query leaves WAL data unchanged")
        sqlite3_close(walDB)

        let sourceURL = directory.appendingPathComponent("source-markers.sqlite")
        let sourceDB = try fixture(at: sourceURL, modern: false)
        let sourceFixtures = [
            ("root", "cli"),
            ("root-custom", "custom-internal-tool"),
            ("root-custom-child-word", "custom-subagent-tool"),
            ("internal-plain", "internal"),
            ("internal-quoted", #""internal""#),
            ("internal-object", #"{"internal":"guardian"}"#),
            ("internal-case", "  Internal  "),
            ("child-plain", "subagent"),
            ("child-quoted", #""subagent""#),
            ("child-object", #"{"subagent":"review"}"#),
            ("child-wire-case", #"{"subAgent":"review"}"#)
        ]
        for (id, source) in sourceFixtures { try insert(sourceDB, id: id, cwd: "/fixture/markers", source: source) }
        try sql(sourceDB, "UPDATE threads SET updated_at=300 WHERE id LIKE 'child-%';")
        sqlite3_close(sourceDB)
        let sourceIndex = ScopedThreadIndex(databaseURL: sourceURL)
        let markersWithEdges = try sourceIndex.read(allowedRoots: ["/fixture/markers"], limit: 1000)
        check(!markersWithEdges.threads.contains { $0.id.hasPrefix("internal-") }, "plain, quoted and object internal markers are excluded")
        check(markersWithEdges.threads.filter { $0.id.hasPrefix("child-") }.allSatisfy { $0.parentThreadId != nil }, "plain, quoted and object subagent markers classify children without spawn edges")
        check(Set(markersWithEdges.threads.filter { $0.parentThreadId == nil }.prefix(3).map(\.id)) == ["root", "root-custom", "root-custom-child-word"], "newer child markers cannot occupy the latest three root slots")
        var sourceWriter: OpaquePointer?
        sqlite3_open(sourceURL.path, &sourceWriter)
        try sql(sourceWriter!, "DROP TABLE thread_spawn_edges;")
        sqlite3_close(sourceWriter)
        let markersWithoutTable = try sourceIndex.read(allowedRoots: ["/fixture/markers"], limit: 1000)
        check(markersWithoutTable.threads.filter { $0.id.hasPrefix("child-") }.count == 4 && markersWithoutTable.threads.filter { $0.id.hasPrefix("child-") }.allSatisfy { $0.parentThreadId != nil }, "child source markers also work when the spawn-edge table is absent")
        check(markersWithoutTable.threads.filter { $0.id.hasPrefix("root-custom") }.allSatisfy { $0.parentThreadId == nil }, "unrelated custom source substrings retain root classification")

        let prospectiveURL = directory.appendingPathComponent("prospective.sqlite")
        let prospectiveDB = try fixture(at: prospectiveURL, modern: false)
        try sql(prospectiveDB, "WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<1500) INSERT INTO threads(id,rollout_path,cwd,created_at,updated_at,model_provider,source) SELECT 'inactive-'||i,'/fixture-codex/sessions/old-'||i||'.jsonl','/fixture/prospective/'||i,100,200,'openai','cli' FROM n;")
        try insert(prospectiveDB, id: "resumed", cwd: "/fixture/prospective/old-chat")
        try insert(prospectiveDB, id: "created", cwd: "/fixture/prospective/new-chat")
        try sql(prospectiveDB, "UPDATE threads SET updated_at=1000 WHERE id='resumed'; UPDATE threads SET created_at=1000 WHERE id='created';")
        sqlite3_close(prospectiveDB)
        let prospectiveIndex = ScopedThreadIndex(databaseURL: prospectiveURL)
        let current = try prospectiveIndex.read(allowedRoots: ["/fixture/prospective"], limit: 2, trackingStart: Date(timeIntervalSince1970: 1000))
        check(Set(current.threads.map(\.id)) == ["resumed", "created"] && current.isComplete, "inactive old chats are filtered before the row cap")
        check(current.threads.first { $0.id == "resumed" }?.createdAt == 100, "an old conversation updated at the cutoff remains eligible")
        let zero = try prospectiveIndex.read(allowedRoots: ["/fixture/prospective"], limit: 2, trackingStart: Date(timeIntervalSince1970: 2000))
        check(zero.threads.isEmpty && zero.isComplete, "successful prospective query can establish no matching activity")

        let location = CodexStateLocation(environment: ["CODEX_HOME": "/fixture/custom", "CODEX_SQLITE_HOME": "/fixture/sqlite"], homeDirectory: URL(fileURLWithPath: "/fixture/home"), workingDirectory: directory)
        check(location.databaseURL.path == "/fixture/sqlite/state_5.sqlite", "documented SQLite home changes only the index location")
        check(location.sessionRoots.map(\.path) == ["/fixture/custom/sessions", "/fixture/custom/archived_sessions"], "custom Codex home controls strict rollout roots")
        let defaults = CodexStateLocation(environment: [:], homeDirectory: URL(fileURLWithPath: "/fixture/home"), workingDirectory: directory)
        check(defaults.databaseURL.path == "/fixture/home/.codex/state_5.sqlite", "official state filename is resolved without probing disk")
        check(AccountingPathScope.roots(["relative", "/fixture/../other"]).isEmpty, "invalid roots cannot broaden scope")
        check(AccountingPathScope.contains("/fixture/project/nested", roots: ["/fixture/project"]) && !AccountingPathScope.contains("/fixture/project-2", roots: ["/fixture/project"]), "reader-side scope predicate matches index boundaries")
        print("Scoped index checks passed: \(count)")
    }
}
