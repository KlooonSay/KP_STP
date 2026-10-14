import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

func showError(_ error: Error) {
    let alert = NSAlert(); alert.messageText = "Не удалось выполнить действие"
    alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "ОК"); alert.runModal()
}
func confirm(_ title: String, _ detail: String, action: String = "Подтвердить", symbol: String = "questionmark.circle") -> Bool {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
    alert.icon = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: action)
    return alert.runModal() == .alertSecondButtonReturn
}
func exportProducts(_ store: Store) {
    let panel = NSSavePanel(); panel.nameFieldStringValue = "Товары.sklad"
    if panel.runModal() == .OK, let url = panel.url {
        do { try store.exportFile(url) } catch { showError(error) }
    }
}
func importProducts(_ store: Store) {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
    panel.message = "Выберите файл .sklad, экспортированный из любой версии приложения."
    if panel.runModal() == .OK, let url = panel.url {
        do {
            let rows = try store.readFile(url)
            if confirm("Заменить перечень товаров?", "Будет загружено \(rows.count) записей. Предыдущие данные сохранятся в резервной копии.", action: "Импортировать") {
                try store.importRows(rows)
            }
        } catch { showError(error) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirm("Завершить работу?", "Все сохранённые изменения останутся в базе. Несохранённые поля открытой формы будут потеряны.", action: "Выйти", symbol: "power") ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct WindowHook: NSViewRepresentable {
    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { view.window?.delegate = coordinator }
    }
}

@main
struct SkladApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Склад — Native") {
            MainView(store: store)
                .frame(minWidth: 440, minHeight: 400)
                .background(WindowHook())
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .defaultSize(width: 1180, height: 730)
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Данные") {
                Button("Экспортировать товары…") { exportProducts(store) }
                Button("Импортировать товары…") { importProducts(store) }
            }
        }
    }
}
enum SectionID: String, CaseIterable, Identifiable {
    case products = "Перечень всех товаров"
    case reports = "Формирование отчётов"
    var id: String { rawValue }
    var symbol: String { self == .products ? "shippingbox.fill" : "doc.text.fill" }
}
struct MainView: View {
    @ObservedObject var store: Store
    @State private var section: SectionID? = .products
    @State private var selection: Int64?
    @State private var editor: Product?
    @State private var selecting = false
    @State private var search = ""
    @State private var expiredOnly = false
    @State private var clock = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var filtered: [Product] {
        let _ = clock
        return store.products.filter {
            (!expiredOnly || section != .reports || $0.expired) &&
            (search.isEmpty || ($0.name + " " + $0.kind + " " + $0.code).localizedCaseInsensitiveContains(search))
        }
    }
    var selected: Product? { store.products.first { $0.id == selection } }
    var reportRows: [Product] { store.products.filter { !expiredOnly || $0.expired } }
    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Склад") {
                    ForEach(SectionID.allCases) { item in
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 15)).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.vertical, 9).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 235, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    Button { NSApp.terminate(nil) } label: {
                        Label("Выход", systemImage: "power").foregroundStyle(.red)
                            .font(.system(size: 15)).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Поиск товаров", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                if section == .reports {
                    HStack {
                        Picker("Состав отчёта", selection: $expiredOnly) {
                            Text("Все товары").tag(false)
                            Text("Просроченные").tag(true)
                        }.pickerStyle(.segmented).frame(maxWidth: 410)
                    }.padding(.horizontal, 28).padding(.vertical, 16)
                }
                List(selection: $selection) {
                    ForEach(filtered) { product in
                        ProductRow(product: product, showExpired: !(section == .reports && expiredOnly))
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(product.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = product.id }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                selection = product.id
                                editor = product
                            })
                            .contextMenu {
                                Button("Изменить товар…") { editor = product }
                                Button("Удалить товар…", role: .destructive) { delete(product) }
                            }
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Товары не найдены").foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Позиций: \(filtered.count)")
                        Spacer(minLength: 0)
                    }.font(.caption).foregroundStyle(.secondary)
                    if section == .reports {
                        if expiredOnly {
                            Text("Стоимость просроченных: \(totalMoney(reportRows)) ₽")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Spacer(minLength: 0)
                            Button("Сформировать отчёт") { printProducts(reportRows, expired: expiredOnly) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .frame(minWidth: 220, maxWidth: .infinity)
            .navigationSplitViewColumnWidth(min: 220, ideal: 650)
            .navigationTitle(section == .reports ? "Отчёты" : "Товары")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { editor = Product() } label: { Image(systemName: "plus.circle") }.help("Ввод нового товара")
                    Button { selecting = true } label: { Image(systemName: "minus.circle") }.help("Выбор товара для изменения или удаления")
                    Button { if let product = selected { delete(product) } } label: { Image(systemName: "trash.circle") }
                        .disabled(selected == nil).help("Удалить выделенный товар")
                    Button { printProducts(section == .reports ? reportRows : store.products, expired: section == .reports && expiredOnly) } label: { Image(systemName: "printer") }.help("Печать отчёта")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $editor) { ProductEditor(store: store, product: $0) }
        .sheet(isPresented: $selecting) { ProductSelector(store: store) }
        .onReceive(timer) { clock = $0 }
        .alert("Ошибка базы данных", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("ОК") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    func delete(_ product: Product) {
        if confirm("Удалить товар?", product.name, action: "Удалить", symbol: "trash") {
            do { try store.remove(product); selection = nil } catch { showError(error) }
        }
    }
}

struct ProductRow: View {
    let product: Product
    var showExpired = true
    var description: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(product.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
            Text(product.kind).foregroundStyle(.secondary).lineLimit(2)
            Label("Шифр: \(product.code)", systemImage: "barcode").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    var figures: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(money(product.priceKopecks)) ₽  ·  \(product.quantity) шт.")
            Text("Срок: \(displayDate(product.expiryDate))").font(.caption).foregroundStyle(.secondary)
            if showExpired && product.expired { Text("истек").font(.caption).foregroundColor(.red) }
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                description.frame(minWidth: 170, alignment: .leading)
                Spacer(minLength: 8)
                figures.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                description
                figures
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 4)
    }
}
struct ProductSelector: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int64?
    @State private var editor: Product?
    @State private var search = ""
    var rows: [Product] { store.products.filter { search.isEmpty || ($0.name + " " + $0.code).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выберите товар").font(.title2.bold())
            TextField("Поиск по наименованию или шифру", text: $search).textFieldStyle(.roundedBorder)
            List(rows, selection: $selection) { p in
                ProductRow(product: p)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(p.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = p.id }
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        selection = p.id
                        editor = p
                    })
            }
            HStack {
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Изменить / удалить") { editor = store.products.first { $0.id == selection } }
                    .disabled(selection == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 800, height: 550)
        .sheet(item: $editor) { ProductEditor(store: store, product: $0) }
    }
}
struct ProductEditor: View {
    @ObservedObject var store: Store
    let product: Product
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: String
    @State private var code: String
    @State private var price: String
    @State private var quantity: String
    @State private var expiry: Date
    init(store: Store, product: Product) {
        self.store = store; self.product = product
        _name = State(initialValue: product.name); _kind = State(initialValue: product.kind)
        _code = State(initialValue: product.code); _price = State(initialValue: money(product.priceKopecks))
        _quantity = State(initialValue: String(product.quantity)); _expiry = State(initialValue: parseISO(product.expiryDate) ?? Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(product.id == 0 ? "Новый товар" : "Изменение товара").font(.title2.bold())
            Form {
                TextField("Наименование", text: $name)
                TextField("Вид товара", text: $kind)
                TextField("Шифр", text: $code)
                TextField("Цена, ₽", text: $price)
                TextField("Количество", text: $quantity)
                DatePicker("Срок реализации", selection: $expiry, displayedComponents: .date)
                LabeledContent("PRIM") {
                    Text(isoDate(expiry) < isoDate(Date()) ? "истек" : " ")
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 25 * 8, height: 3 * 17, alignment: .topLeading)
                        .padding(7).background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                }
            }.formStyle(.grouped)
            HStack {
                if product.id != 0 {
                    Button("Удалить…", role: .destructive) {
                        if confirm("Удалить товар?", product.name, action: "Удалить", symbol: "trash") {
                            do { try store.remove(product); dismiss() } catch { showError(error) }
                        }
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
    func save() {
        do {
            let value = price.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            guard value.range(of: "^[0-9]+([.][0-9]{1,2})?$", options: .regularExpression) != nil,
                  let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
                  decimal >= 0, decimal <= 100_000_000 else { throw fail("Цена: число от 0 до 100000000, не более двух знаков после запятой.") }
            guard let count = Int64(quantity.trimmingCharacters(in: .whitespacesAndNewlines)), (0...1_000_000).contains(count) else { throw fail("Количество: целое число от 0 до 1000000.") }
            let p = Product(id: product.id, name: name, kind: kind, code: code, priceKopecks: NSDecimalNumber(decimal: decimal * 100).int64Value, quantity: count, expiryDate: isoDate(expiry))
            try store.save(p); dismiss()
        } catch { showError(error) }
    }
}

