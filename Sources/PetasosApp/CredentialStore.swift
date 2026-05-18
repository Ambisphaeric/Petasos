import Foundation
import SQLite3

/// Persists bearer tokens to a private SQLite database at
/// `~/Library/Application Support/Petasos/credentials.sqlite`.
///
/// Why SQLite instead of Keychain: keychain ACLs are tied to the binary's
/// designated requirement, which changes on every codesign-with-a-new-cdhash —
/// i.e. every rebuild + reinstall. That meant the user was retyping their
/// macOS login password every time a fresh DMG installed. SQLite at a stable
/// path under Application Support survives reinstalls, requires no system
/// prompts, and keeps the rest of the app's call shape identical to the old
/// KeychainStore.
///
/// Security note: the DB is set to file mode 0600, so only the user account
/// that owns Application Support can read it. That's the same boundary other
/// indie macOS apps (1Password's cache, Slack's tokens pre-Keychain, VS Code's
/// settings sync) use for non-sandboxed local data.
public struct CredentialStore: @unchecked Sendable {
    public enum CredentialError: Error, LocalizedError {
        case sqlite(String)
        public var errorDescription: String? {
            switch self {
            case .sqlite(let m): return "Credential store: \(m)"
            }
        }
    }

    private let dbPath: String

    public init(directory: URL? = nil) throws {
        let dir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbPath = dir.appendingPathComponent("credentials.sqlite").path
        try ensureSchema()
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)
    }

    public static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Petasos", isDirectory: true)
    }

    // MARK: - Public API (mirrors the old KeychainStore)

    public func save(token: String, account: String) throws {
        try withDB { db in
            let sql = """
            INSERT INTO credentials (account, token, created_at)
            VALUES (?, ?, ?)
            ON CONFLICT(account) DO UPDATE SET
              token = excluded.token,
              created_at = excluded.created_at
            """
            try exec(db: db, sql: sql) { stmt in
                bindText(stmt, position: 1, value: account)
                bindText(stmt, position: 2, value: token)
                sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            }
        }
    }

    public func load(account: String) throws -> String? {
        try withDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT token FROM credentials WHERE account = ?", -1, &stmt, nil) == SQLITE_OK else {
                throw CredentialError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            bindText(stmt, position: 1, value: account)
            if sqlite3_step(stmt) == SQLITE_ROW, let cstr = sqlite3_column_text(stmt, 0) {
                return String(cString: cstr)
            }
            return nil
        }
    }

    public func delete(account: String) throws {
        try withDB { db in
            try exec(db: db, sql: "DELETE FROM credentials WHERE account = ?") { stmt in
                bindText(stmt, position: 1, value: account)
            }
        }
    }

    // MARK: - Internals

    private func ensureSchema() throws {
        try withDB { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS credentials (
              account TEXT PRIMARY KEY NOT NULL,
              token TEXT NOT NULL,
              created_at REAL NOT NULL
            );
            """
            var err: UnsafeMutablePointer<Int8>?
            guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw CredentialError.sqlite(msg)
            }
        }
    }

    private func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var raw: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db = raw else {
            let msg = raw.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed (\(rc))"
            sqlite3_close(raw)
            throw CredentialError.sqlite(msg)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func exec(db: OpaquePointer, sql: String, bind: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CredentialError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CredentialError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bindText(_ stmt: OpaquePointer?, position: Int32, value: String) {
        // SQLITE_TRANSIENT makes SQLite copy the bytes, so the Swift String can
        // be released as soon as the statement is finalized.
        sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT_STORE)
    }
}

// Swift can't import SQLITE_TRANSIENT directly because it's defined as a macro
// casting -1 to a function-pointer type. Reconstruct it once here.
private let SQLITE_TRANSIENT_STORE = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)
