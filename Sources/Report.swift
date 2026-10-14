import AppKit

// Табличная ведомость. Один и тот же документ используется для предпросмотра,
// печати и сохранения через стандартное меню PDF системного диалога.
final class InventoryReportView: NSView {
    struct Row {
        var cells: [[String]]
        var number: Int
        var height: CGFloat { CGFloat(cells.map { $0.count }.max() ?? 1) * 12 + 12 }
    }
    let products: [Product]
    let expired: Bool
    let created = Date()
    private(set) var pages: [[Row]] = []
    private var pageSize = NSSize(width: 770, height: 523)
    private var widths: [CGFloat] = []
    private let headings = ["№", "Шифр", "Наименование", "Вид товара", "Цена, руб.", "Кол-во", "Срок реализации", "Стоимость, руб."]
    private let fractions: [CGFloat] = [0.04, 0.10, 0.24, 0.14, 0.11, 0.08, 0.13, 0.16]
    private let tableTop: CGFloat = 98
    private let headerHeight: CGFloat = 32
    override var isFlipped: Bool { true }

    init(products: [Product], expired: Bool) {
        self.products = products; self.expired = expired
        super.init(frame: .zero)
        paginate(size: pageSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func wrapped(_ text: String, width: CGFloat) -> [String] {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 9)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(10,width), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, range, _ in
            let chars = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: chars).trimmingCharacters(in: .newlines))
        }
        return lines.isEmpty ? [""] : lines
    }
    func paginate(size: NSSize) {
        pageSize = NSSize(width: max(240, size.width), height: max(260,size.height))
        widths = fractions.map { $0 * pageSize.width / fractions.reduce(0,+) }
        let capacity = pageSize.height - tableTop - headerHeight - 78
        var current: [Row] = []
        var used: CGFloat = 0
        pages = []
        func flush() { pages.append(current); current = []; used = 0 }
        for (index, p) in products.enumerated() {
            let values = [String(index+1),p.code,p.name,p.kind,money(p.priceKopecks),String(p.quantity),displayDate(p.expiryDate),money(p.total)]
            let cells = zip(values,widths).map { wrapped($0.0, width: $0.1-12) }
            let row = Row(cells: cells, number: index+1)
            if row.height <= capacity {
                if used + row.height > capacity && !current.isEmpty { flush() }
                current.append(row); used += row.height
            } else {
                // Очень длинные поля продолжаются на следующем листе без потери текста.
                if !current.isEmpty { flush() }
                let chunk = max(1,Int((capacity-12)/12))
                let count = cells.map { $0.count }.max() ?? 1
                var offset = 0
                while offset < count {
                    let parts = cells.map { Array($0.dropFirst(offset).prefix(chunk)) }
                    let fragment = Row(cells: parts, number: index+1)
                    current.append(fragment); used += fragment.height; offset += chunk
                    if offset < count { flush() }
                }
            }
        }
        if !current.isEmpty || pages.isEmpty { pages.append(current) }
        frame = NSRect(origin: .zero, size: NSSize(width: pageSize.width, height: pageSize.height * CGFloat(pages.count)))
    }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        if let info = NSPrintOperation.current?.printInfo {
            let size = NSSize(width: info.paperSize.width-info.leftMargin-info.rightMargin,
                              height: info.paperSize.height-info.topMargin-info.bottomMargin)
            if abs(size.width-pageSize.width)>0.5 || abs(size.height-pageSize.height)>0.5 { paginate(size: size) }
        }
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }
    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page-1)*pageSize.height, width: pageSize.width, height: pageSize.height)
    }
    private func text(_ string: String, rect: NSRect, size: CGFloat = 9, bold: Bool = false, right: Bool = false, gray: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = right ? .right : .left
        paragraph.lineBreakMode = .byWordWrapping
        (string as NSString).draw(in: rect, withAttributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
            .foregroundColor: gray ? NSColor(white: 0.38, alpha: 1) : NSColor.black,
            .paragraphStyle: paragraph
        ])
    }
    private func line(_ from: NSPoint, _ to: NSPoint) {
        NSColor(white: 0.78, alpha: 1).setStroke()
        let path = NSBezierPath(); path.lineWidth = 0.5; path.move(to: from); path.line(to: to); path.stroke()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); dirtyRect.fill()
        for index in pages.indices {
            let rect = rectForPage(index+1)
            guard rect.intersects(dirtyRect) else { continue }
            let origin = rect.minY
            text("СКЛАД  /  ТОВАРНАЯ ВЕДОМОСТЬ", rect: NSRect(x:0,y:origin,width:pageSize.width,height:14), size:9, gray:true)
            let title = expired ? "Отчёт о просроченных товарах" : "Отчёт о наличии товаров"
            text(title, rect:NSRect(x:0,y:origin+20,width:pageSize.width,height:46),size:18,bold:true)
            let condition = expired ? "Срок реализации ранее даты отчёта" : "Все товары, имеющиеся на складе"
            text("По состоянию на \(displayDate(isoDate(created)))  ·  \(condition)",rect:NSRect(x:0,y:origin+68,width:pageSize.width,height:25),size:9,gray:true)
            var y = origin+tableTop
            NSColor(white:0.93,alpha:1).setFill()
            NSRect(x:0,y:y,width:pageSize.width,height:headerHeight).fill()
            var x: CGFloat = 0
            for column in headings.indices {
                text(headings[column],rect:NSRect(x:x+6,y:y+5,width:widths[column]-12,height:headerHeight-8),bold:true,right:[4,5,7].contains(column))
                x += widths[column]
            }
            line(NSPoint(x:0,y:y),NSPoint(x:pageSize.width,y:y))
            y += headerHeight
            for row in pages[index] {
                if row.number % 2 == 0 {
                    NSColor(white:0.975,alpha:1).setFill(); NSRect(x:0,y:y,width:pageSize.width,height:row.height).fill()
                }
                x = 0
                for column in row.cells.indices {
                    for (n, value) in row.cells[column].enumerated() {
                        text(value,rect:NSRect(x:x+6,y:y+6+CGFloat(n)*12,width:widths[column]-12,height:14),right:[4,5,7].contains(column))
                    }
                    line(NSPoint(x:x,y:y),NSPoint(x:x,y:y+row.height))
                    x += widths[column]
                }
                y += row.height
                line(NSPoint(x:0,y:y),NSPoint(x:pageSize.width,y:y))
            }
            x = 0
            for width in widths {
                line(NSPoint(x:x,y:origin+tableTop),NSPoint(x:x,y:y)); x += width
            }
            line(NSPoint(x:pageSize.width,y:origin+tableTop),NSPoint(x:pageSize.width,y:y))
            line(NSPoint(x:0,y:origin+tableTop+headerHeight),NSPoint(x:pageSize.width,y:origin+tableTop+headerHeight))
            if products.isEmpty { text("Товары, соответствующие условиям отчёта, отсутствуют.",rect:NSRect(x:6,y:y+12,width:pageSize.width-12,height:26)); y += 35 }
            if index == pages.count-1 {
                text("Всего позиций: \(products.count)",rect:NSRect(x:0,y:y+14,width:pageSize.width,height:16),size:10)
                text("Итоговая стоимость: \(totalMoney(products)) руб.",rect:NSRect(x:0,y:y+34,width:pageSize.width,height:20),size:11,bold:true,right:true)
            }
            line(NSPoint(x:0,y:origin+pageSize.height-20),NSPoint(x:pageSize.width,y:origin+pageSize.height-20))
            text("Склад · \(displayDate(isoDate(created)))",rect:NSRect(x:0,y:origin+pageSize.height-15,width:pageSize.width/2,height:14),size:8,gray:true)
            text("Страница \(index+1) из \(pages.count)",rect:NSRect(x:pageSize.width/2,y:origin+pageSize.height-15,width:pageSize.width/2,height:14),size:8,right:true,gray:true)
        }
    }
}

func printProducts(_ products: [Product], expired: Bool) {
    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
    info.paperSize = NSSize(width: 595.28, height: 841.89)
    info.orientation = .landscape
    info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
    info.isVerticallyCentered = false; info.isHorizontallyCentered = false
    info.horizontalPagination = .fit; info.verticalPagination = .automatic
    info.jobDisposition = .spool
    let view = InventoryReportView(products: products, expired: expired)
    let operation = NSPrintOperation(view: view, printInfo: info)
    operation.jobTitle = expired ? "Просроченные товары" : "Все товары"
    operation.showsPrintPanel = true; operation.showsProgressPanel = true
    operation.printPanel.options.insert(.showsPreview)
    operation.run()
}
