import Foundation

/// Builds the monthly summary workbook (Clockify-style summary with per-client totals):
///
///   Project | Description | Time (h) | Time (decimal) | (amount)
///   Acme    | Landing page | 02:30:00 | 2.50 | $125.00
///   ...
///   Total Acme (Website)  | 03:15:00 | 3.25 | $162.50   (bold, 14pt red amount)
///   (blank)
///   Total Globex ...
///   (blank)
///   Total (01/09/2026 - 30/09/2026) | 08:45:00 | 8.75 | $382.50  (bold, 20pt red amount)
///
/// Identical descriptions inside a group are merged (summed), like Clockify's summary report.
public enum ReportExporter {

    public struct Line: Equatable {
        public var title: String
        public var seconds: TimeInterval
        public var amount: Double?
    }

    public struct Group: Equatable {
        public var clientName: String
        public var project: String?
        public var lines: [Line]
        public var seconds: TimeInterval { lines.reduce(0) { $0 + $1.seconds } }
        public var amount: Double? {
            let amounts = lines.compactMap { $0.amount }
            return amounts.isEmpty ? nil : amounts.reduce(0, +)
        }
        public var totalLabel: String {
            if let p = project, !p.isEmpty { return "Total \(clientName) (\(p))" }
            return "Total \(clientName)"
        }
    }

    // MARK: - Grouping

    public static func groups(entries: [TimeEntry], clients: [Client], now: Date = Date()) -> [Group] {
        struct Key: Hashable { let client: String; let project: String }
        var buckets: [Key: [String: Line]] = [:]
        var rates: [Key: Double?] = [:]

        for e in entries {
            let client = clients.first { $0.id == e.clientID }
            let clientName = client?.name ?? "(No client)"
            let project = (e.project ?? "").trimmingCharacters(in: .whitespaces)
            let key = Key(client: clientName, project: project)
            rates[key] = client?.hourlyRate
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleKey = title.lowercased()
            var line = buckets[key, default: [:]][titleKey] ?? Line(title: title.isEmpty ? "(No description)" : title, seconds: 0, amount: nil)
            line.seconds += e.duration(now: now)
            buckets[key, default: [:]][titleKey] = line
        }

        var out: [Group] = []
        for (key, lines) in buckets {
            let rate = rates[key] ?? nil
            let sorted = lines.values
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { l -> Line in
                    var l = l
                    if let rate {
                        let dec = DurationFormat.decimalHours(l.seconds)
                        l.amount = (dec * rate * 100).rounded() / 100
                    }
                    return l
                }
            out.append(Group(clientName: key.client, project: key.project.isEmpty ? nil : key.project, lines: sorted))
        }
        out.sort {
            let c = $0.clientName.localizedCaseInsensitiveCompare($1.clientName)
            if c != .orderedSame { return c == .orderedAscending }
            return ($0.project ?? "").localizedCaseInsensitiveCompare($1.project ?? "") == .orderedAscending
        }
        return out
    }

    // MARK: - Workbook

    public static func workbook(entries: [TimeEntry], clients: [Client], range: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> Data {
        let gs = groups(entries: entries, clients: clients, now: now)
        var zip = ZipWriter(date: now)
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("xl/workbook.xml", Data(workbookXML.utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8))
        zip.add("xl/styles.xml", Data(stylesXML.utf8))
        zip.add("xl/worksheets/sheet1.xml", Data(sheetXML(groups: gs, range: range, calendar: calendar).utf8))
        return zip.finish()
    }

    public static func suggestedFilename(reportName: String, range: DateInterval, calendar: Calendar = .current) -> String {
        let name = reportName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        let (from, to) = rangeLabels(range, separator: "_", calendar: calendar)
        let prefix = name.isEmpty ? "Time_Report_Summary" : "Time_Report_Summary_\(name)"
        return "\(prefix)_\(from)-\(to).xlsx"
    }

    static func rangeLabels(_ range: DateInterval, separator: String, calendar: Calendar) -> (String, String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "dd\(separator)MM\(separator)yyyy"
        let last = range.end.addingTimeInterval(-1)
        return (f.string(from: range.start), f.string(from: last))
    }

    // MARK: - Sheet

    static func sheetXML(groups: [Group], range: DateInterval, calendar: Calendar = .current) -> String {
        var rows: [String] = []
        var r = 1

        func s(_ col: String, _ text: String, _ style: Int) -> String {
            "<c r=\"\(col)\(r)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(text))</t></is></c>"
        }
        func n(_ col: String, _ value: Double, _ style: Int) -> String {
            "<c r=\"\(col)\(r)\" s=\"\(style)\"><v>\(fmt(value))</v></c>"
        }
        func blank(_ col: String, _ style: Int) -> String {
            "<c r=\"\(col)\(r)\" s=\"\(style)\"/>"
        }
        func row(_ cells: [String]) {
            rows.append("<row r=\"\(r)\">\(cells.joined())</row>")
            r += 1
        }

        // Header (E header intentionally empty, like the reference file)
        row([s("A", "Project", 1), s("B", "Description", 1), s("C", "Time (h)", 9), s("D", "Time (decimal)", 9), blank("E", 9)])

        var totalSeconds: TimeInterval = 0
        var totalAmount: Double = 0

        for g in groups {
            for l in g.lines {
                var cells = [s("A", g.clientName, 0), s("B", l.title, 0), s("C", DurationFormat.hms(l.seconds), 2), n("D", DurationFormat.decimalHours(l.seconds), 3)]
                if let a = l.amount { cells.append(n("E", a, 4)) } else { cells.append(blank("E", 4)) }
                row(cells)
            }
            var cells = [s("A", g.totalLabel, 1), blank("B", 1), s("C", DurationFormat.hms(g.seconds), 5), n("D", DurationFormat.decimalHours(g.seconds), 6)]
            if let a = g.amount { cells.append(n("E", a, 7)) } else { cells.append(blank("E", 7)) }
            row(cells)
            row([])   // spacer
            totalSeconds += g.seconds
            totalAmount += g.amount ?? 0
        }

        let (from, to) = rangeLabels(range, separator: "/", calendar: calendar)
        row([s("A", "Total (\(from) - \(to))", 1), blank("B", 1), s("C", DurationFormat.hms(totalSeconds), 5), n("D", DurationFormat.decimalHours(totalSeconds), 6), n("E", (totalAmount * 100).rounded() / 100, 8)])

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheetViews><sheetView workbookViewId="0"/></sheetViews>
        <sheetFormatPr defaultRowHeight="12.8"/>
        <cols><col min="1" max="5" width="27.34" customWidth="1"/></cols>
        <sheetData>\(rows.joined())</sheetData>
        </worksheet>
        """
    }

    private static func fmt(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - Static parts

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Summary report" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    /// Fonts: 0 regular, 1 bold, 2 bold 14 red, 3 bold 20 red.
    /// Styles: 0 text, 1 bold text, 2 time, 3 decimal, 4 amount, 5 time bold, 6 decimal bold,
    ///         7 subtotal amount (14 red), 8 grand total amount (20 red), 9 bold header right.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="3">
    <numFmt numFmtId="164" formatCode="hh:mm:ss"/>
    <numFmt numFmtId="165" formatCode="#,##0.00"/>
    <numFmt numFmtId="166" formatCode="[$$-409]#,##0.00;[RED]\\-[$$-409]#,##0.00"/>
    </numFmts>
    <fonts count="4">
    <font><sz val="10"/><name val="DejaVu Sans"/><family val="2"/></font>
    <font><b/><sz val="10"/><name val="DejaVu Sans"/><family val="2"/></font>
    <font><b/><sz val="14"/><color rgb="FFC9211E"/><name val="DejaVu Sans"/><family val="2"/></font>
    <font><b/><sz val="20"/><color rgb="FFC9211E"/><name val="DejaVu Sans"/><family val="2"/></font>
    </fonts>
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="10">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="166" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="166" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}
