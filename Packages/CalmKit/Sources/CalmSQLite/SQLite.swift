import Foundation
import SQLite3

/// A small wrapper over the system SQLite: enough for the search index and for reading an
/// agent's own database (OpenCode's), nothing more. Not thread-safe; callers confine it to one
/// queue.
package final class SQLiteDatabase {
    package enum Failure: Error, CustomStringConvertible {
        case open(String)
        case statement(String, sql: String)

        package var description: String {
            switch self {
            case let .open(message): "Couldn't open the database: \(message)"
            case let .statement(message, sql): "Database query failed: \(message) (\(sql.prefix(80)))"
            }
        }
    }

    package enum Value {
        case text(String)
        case integer(Int64)
        case real(Double)
        case null
    }

    private var handle: OpaquePointer?

    /// `readOnly` never creates or changes the file: for databases that belong to another
    /// program. A write-ahead log next to it is still read, so recent writes are seen.
    package init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw Failure.open(message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close(handle)
    }

    package func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw Failure.statement(message, sql: sql)
        }
    }

    /// Runs a statement with bound values, calling `row` for each result row.
    package func query(_ sql: String, _ values: [Value] = [], row: ((Row) -> Void)? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.statement(String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let .text(text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case let .integer(number): sqlite3_bind_int64(statement, position, number)
            case let .real(number): sqlite3_bind_double(statement, position, number)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                row?(Row(statement: statement))
            } else if result == SQLITE_DONE {
                return
            } else {
                throw Failure.statement(String(cString: sqlite3_errmsg(handle)), sql: sql)
            }
        }
    }

    package var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    package func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    package struct Row {
        let statement: OpaquePointer?

        package func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        package func integer(_ column: Int32) -> Int64 {
            sqlite3_column_int64(statement, column)
        }

        package func real(_ column: Int32) -> Double {
            sqlite3_column_double(statement, column)
        }
    }

    /// SQLite copies bound text (SQLITE_TRANSIENT).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
