@testable import CalmSQLite
import Foundation
import Testing

struct SQLiteDatabaseTests {
    /// A class's deinit runs even when its init throws, once every stored property has a value:
    /// a failed open that closed its connection in init, and again in deinit, freed it twice. The
    /// package suite then crashed now and then inside SQLite's next open, in another test. SQLite
    /// logs the second close ("API call with invalid database connection pointer"), which is how
    /// this was confirmed; the test itself can only show that a failed open throws.
    @Test func `a database that can't be opened throws, and is closed once`() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "calm-missing-\(UUID().uuidString)/none.db").path
        for _ in 0 ..< 200 {
            #expect(throws: SQLiteDatabase.Failure.self) { try SQLiteDatabase(path: missing, readOnly: true) }
        }
    }

    @Test func `a database that opens reads what was written`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "calm-sqlite-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try SQLiteDatabase(path: path)
        try database.execute("CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('kept')")
        var value: String?
        try database.query("SELECT v FROM t") { value = $0.text(0) }
        #expect(value == "kept")
    }
}
