import Foundation
import Combine
import SQLite3

struct WarehouseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func fail(_ message: String) -> WarehouseError { WarehouseError(message: message) }
func money(_ amount: Int64) -> String { "\(amount / 100)," + String(format: "%02lld", amount % 100) }
func isoDate(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
func parseISO(_ text: String) -> Date? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
    guard let date = f.date(from: text), f.string(from: date) == text else { return nil }
    return date
}
func displayDate(_ text: String) -> String {
    let parts = text.split(separator: "-"); return parts.count == 3 ? parts.reversed().joined(separator: ".") : text
}
struct Product: Identifiable, Codable {
    var id: Int64 = 0
    var name: String = ""
    var kind: String = ""
    var code: String = ""
    var priceKopecks: Int64 = 0
    var quantity: Int64 = 0
    var expiryDate: String = isoDate(Date())
    var expired: Bool { expiryDate < isoDate(Date()) }
    var total: Int64 { priceKopecks * quantity }
    enum CodingKeys: String, CodingKey {
        case name, kind, code, quantity
        case priceKopecks = "price_kopecks"
        case expiryDate = "expiry_date"
    }
    func validated() throws -> Product {
        var p = self
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        p.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.name.isEmpty, !p.kind.isEmpty, !p.code.isEmpty else { throw fail("Заполните наименование, вид и шифр.") }
        guard (0...10_000_000_000).contains(priceKopecks), (0...1_000_000).contains(quantity) else { throw fail("Недопустимая цена или количество.") }
        guard parseISO(expiryDate) != nil else { throw fail("Некорректная дата.") }
        return p
    }
}
func totalMoney(_ rows: [Product]) -> String {
    let sum = rows.reduce(Decimal(0)) { $0 + Decimal($1.total) } / 100
    let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "ru_RU")
    formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSDecimalNumber(decimal: sum)) ?? "0,00"
}

struct Transfer: Codable {
    var format = "sklad-v1"
    var products: [Product]
}

final class Store: ObservableObject {
    @Published var products: [Product] = []
    @Published var error: String?
    private var handle: OpaquePointer?
    let folder: URL
    let database: URL
    init(databaseURL: URL? = nil, seedURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = databaseURL?.deletingLastPathComponent() ?? base.appendingPathComponent("SkladNative", isDirectory: true)
        database = databaseURL ?? folder.appendingPathComponent("warehouse.db")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: database.path) {
                guard let seed = seedURL ?? Bundle.main.url(forResource: "warehouse", withExtension: "db") else { throw fail("Не найдена начальная база приложения.") }
                try FileManager.default.copyItem(at: seed, to: database)
            }
            guard sqlite3_open(database.path, &handle) == SQLITE_OK else { throw fail("Не удалось открыть базу данных.") }
            sqlite3_busy_timeout(handle, 5000)
            try load()
        } catch { self.error = error.localizedDescription }
    }
    deinit { sqlite3_close(handle) }
    private func message() -> WarehouseError {
        guard let handle else { return fail("База данных недоступна.") }
        if sqlite3_errcode(handle) == SQLITE_CONSTRAINT { return fail("Не удалось сохранить товар. Проверьте уникальность шифра и значения полей.") }
        return fail(String(cString: sqlite3_errmsg(handle)))
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard let handle, sqlite3_prepare_v2(handle, sql, -1, &result, nil) == SQLITE_OK, let result else { throw message() }
        return result
    }
    private func execute(_ sql: String) throws {
        guard let handle, sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw message() }
    }
    func load() throws {
        let s = try statement("SELECT id,name,kind,code,price_kopecks,quantity,expiry_date FROM products ORDER BY name,code")
        defer { sqlite3_finalize(s) }
        func text(_ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
        var rows: [Product] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            let p = Product(id: sqlite3_column_int64(s,0), name: text(1), kind: text(2), code: text(3), priceKopecks: sqlite3_column_int64(s,4), quantity: sqlite3_column_int64(s,5), expiryDate: text(6))
            rows.append(try p.validated()); status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw message() }
        products = rows
    }
    private func write(_ product: Product, update: Bool) throws {
        let p = try product.validated()
        let sql = update ? "UPDATE products SET name=?,kind=?,code=?,price_kopecks=?,quantity=?,expiry_date=? WHERE id=?" : "INSERT INTO products(name,kind,code,price_kopecks,quantity,expiry_date) VALUES(?,?,?,?,?,?)"
        let s = try statement(sql); defer { sqlite3_finalize(s) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        func bind(_ text: String, _ index: Int32) throws {
            let status = text.withCString { sqlite3_bind_text(s,index,$0,-1,transient) }
            guard status == SQLITE_OK else { throw message() }
        }
        try bind(p.name,1); try bind(p.kind,2); try bind(p.code,3)
        guard sqlite3_bind_int64(s,4,p.priceKopecks) == SQLITE_OK, sqlite3_bind_int64(s,5,p.quantity) == SQLITE_OK else { throw message() }
        try bind(p.expiryDate,6)
        if update { sqlite3_bind_int64(s,7,p.id) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw message() }
    }
    func save(_ p: Product) throws { try write(p, update: p.id != 0); try load() }
    func remove(_ p: Product) throws {
        let s = try statement("DELETE FROM products WHERE id=?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_int64(s,1,p.id)
        guard sqlite3_step(s) == SQLITE_DONE else { throw message() }; try load()
    }
    func exportFile(_ url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Transfer(products: products)).write(to: url, options: .atomic)
    }
    func readFile(_ url: URL) throws -> [Product] {
        let transfer = try JSONDecoder().decode(Transfer.self, from: Data(contentsOf: url))
        guard transfer.format == "sklad-v1" else { throw fail("Это не файл данных приложения «Склад».") }
        var codes = Set<String>()
        return try transfer.products.map {
            let p = try $0.validated()
            guard codes.insert(p.code).inserted else { throw fail("В файле повторяются шифры товаров.") }
            return p
        }
    }
    func importRows(_ rows: [Product]) throws {
        let backups = folder.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try exportFile(backups.appendingPathComponent(UUID().uuidString + ".sklad"))
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM products")
            for row in rows { try write(row, update: false) }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        try load()
    }
}
