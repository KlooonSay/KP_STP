import Foundation
import AppKit

@main
struct CoreChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let seed = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = Store(databaseURL: folder.appendingPathComponent("test.db"), seedURL: seed)
        if let error = store.error { throw fail(error) }
        let count = store.products.count
        let original = Product(name: "Тест", kind: "Проверка", code: "TEST-UNIQUE", priceKopecks: 1234, quantity: 3, expiryDate: "2020-01-01")
        try store.save(original)
        precondition(store.products.count == count + 1)
        guard var row = store.products.first(where: { $0.code == "TEST-UNIQUE" }) else { throw fail("Товар не сохранён") }
        precondition(row.expired && row.total == 3702)
        row.name = "Изменено"; try store.save(row)
        precondition(store.products.first(where: { $0.id == row.id })?.name == "Изменено")
        var rejected = false
        do { try store.save(original) } catch { rejected = true }
        precondition(rejected, "Ограничение уникальности не сработало")
        let file = folder.appendingPathComponent("copy.sklad")
        try store.exportFile(file)
        let imported = try store.readFile(file)
        precondition(imported.count == count + 1)
        try store.importRows(imported)
        precondition(store.products.count == count + 1)
        let encoder = JSONEncoder()
        try encoder.encode(Transfer(products: [original, original])).write(to: file)
        rejected = false
        do { _ = try store.readFile(file) } catch { rejected = true }
        precondition(rejected)
        // Даже при прямом импорте конфликт откатывает всю транзакцию.
        rejected = false
        do { try store.importRows([original, original]) } catch { rejected = true }
        precondition(rejected)
        try store.load(); precondition(store.products.count == count + 1)
        let today = Product(expiryDate: isoDate(Date()))
        precondition(!today.expired)
        precondition(parseISO("2026-02-30") == nil)
        if let target = store.products.first(where: { $0.code == "TEST-UNIQUE" }) { try store.remove(target) }
        precondition(store.products.count == count)
        _ = NSApplication.shared
        let report = InventoryReportView(products: store.products, expired: false)
        for size in [NSSize(width:770,height:523), NSSize(width:523,height:770)] {
            report.paginate(size: size)
            precondition(report.pages.flatMap { $0 }.count == count)
            precondition(report.pages.allSatisfy { $0.reduce(CGFloat(0)) { $0 + $1.height } <= size.height-208.0+0.01 })
        }
        var long = original; long.name = String(repeating: "Длинное наименование товара ", count: 400)
        let longReport = InventoryReportView(products: [long], expired: true)
        precondition(longReport.pages.count > 1)
        precondition(InventoryReportView(products: [], expired: true).pages.count == 1)
        print("Проверки SQLite, переноса данных и разбиения отчётов на страницы пройдены.")
    }
}
