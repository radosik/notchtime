import XCTest
@testable import NotchTimeCore

final class ReportExporterTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func secs(_ hms: String) -> TimeInterval {
        let p = hms.split(separator: ":").map { Double($0)! }
        return p[0] * 3600 + p[1] * 60 + p[2]
    }

    /// Two sample clients with round numbers so every expected value can be checked by hand.
    ///   Acme (Website), $50/h:  Contact form 0:45, Landing page 2:30 (tracked in two sessions)
    ///   Globex, $40/h:          Client's portal 0:20, Email setup 1:10, Server migration 4:00
    private func fixture() -> (clients: [Client], entries: [TimeEntry], range: DateInterval) {
        let acme = Client(name: "Acme", projects: ["Website"], hourlyRate: 50)
        let globex = Client(name: "Globex", hourlyRate: 40)
        let rows: [(Client, String?, String, String)] = [
            (acme, "Website", "Landing page", "01:00:00"),
            (acme, "Website", "Contact form", "00:45:00"),
            (globex, nil, "Server migration", "04:00:00"),
            (globex, nil, "Client's portal", "00:20:00"),
            (globex, nil, "Email setup", "01:10:00"),
            (acme, "Website", "Landing page", "01:30:00"),   // second session of the same task → merged
        ]
        var entries: [TimeEntry] = []
        for (i, r) in rows.enumerated() {
            let start = date(2026, 9, 1 + i * 4)
            entries.append(TimeEntry(title: r.2, clientID: r.0.id, project: r.1, start: start, end: start.addingTimeInterval(secs(r.3))))
        }
        let range = cal.dateInterval(of: .month, for: date(2026, 9, 15))!
        return ([acme, globex], entries, range)
    }

    func testGroupingMergesTasksAndTotals() {
        let f = fixture()
        let groups = ReportExporter.groups(entries: f.entries, clients: f.clients)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].clientName, "Acme")
        XCTAssertEqual(groups[0].project, "Website")
        XCTAssertEqual(groups[0].totalLabel, "Total Acme (Website)")
        XCTAssertEqual(groups[0].lines.map(\.title), ["Contact form", "Landing page"])
        XCTAssertEqual(DurationFormat.hms(groups[0].lines[1].seconds), "02:30:00")
        XCTAssertEqual(DurationFormat.hms(groups[0].seconds), "03:15:00")
        XCTAssertEqual(groups[0].amount!, 162.5, accuracy: 0.001)

        XCTAssertEqual(groups[1].clientName, "Globex")
        XCTAssertEqual(groups[1].totalLabel, "Total Globex")
        XCTAssertEqual(groups[1].lines.map(\.title), ["Client's portal", "Email setup", "Server migration"])
        XCTAssertEqual(DurationFormat.hms(groups[1].seconds), "05:30:00")
        XCTAssertEqual(groups[1].amount!, 220.0, accuracy: 0.001)

        let total = groups.reduce(0.0) { $0 + $1.seconds }
        XCTAssertEqual(DurationFormat.hms(total), "08:45:00")
        XCTAssertEqual(DurationFormat.decimalHours(total), 8.75, accuracy: 0.001)
    }

    func testSheetXMLContainsExpectedCells() {
        let f = fixture()
        let groups = ReportExporter.groups(entries: f.entries, clients: f.clients)
        let xml = ReportExporter.sheetXML(groups: groups, range: f.range, calendar: cal)
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">Total Acme (Website)</t>"))
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">Total Globex</t>"))
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">Total (01/09/2026 - 30/09/2026)</t>"))
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">08:45:00</t>"))
        XCTAssertTrue(xml.contains("<v>382.5</v>"))
        XCTAssertTrue(xml.contains("Client&apos;s portal"))
    }

    func testWorkbookIsZipAndWrittenForInspection() throws {
        let f = fixture()
        let data = ReportExporter.workbook(entries: f.entries, clients: f.clients, range: f.range, calendar: cal)
        XCTAssertGreaterThan(data.count, 2000)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])

        XCTAssertEqual(ReportExporter.suggestedFilename(reportName: "Sample", range: f.range, calendar: cal),
                       "Time_Report_Summary_Sample_01_09_2026-30_09_2026.xlsx")
        XCTAssertEqual(ReportExporter.suggestedFilename(reportName: "", range: f.range, calendar: cal),
                       "Time_Report_Summary_01_09_2026-30_09_2026.xlsx")

        // Written so CI can upload it and a human (or openpyxl) can open it.
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("test-export.xlsx"))
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormat.hms(secs("30:32:38")), "30:32:38")
        XCTAssertEqual(DurationFormat.compact(59), "00:59")
        XCTAssertEqual(DurationFormat.compact(3661), "1:01:01")
        XCTAssertEqual(DurationFormat.decimalHours(secs("02:30:00")), 2.5, accuracy: 0.0001)
        XCTAssertEqual(DurationFormat.decimalHours(secs("00:20:00")), 0.33, accuracy: 0.0001)
    }

    func testStoreRoundTripAndRunningTimer() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchtime-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = TimeStore(fileURL: tmp)
        XCTAssertTrue(store.clients.isEmpty)
        let acme = store.addClient(name: "Acme", rate: 50)
        let t0 = Date().addingTimeInterval(-600)
        store.start(title: "Landing page", clientID: acme.id, project: nil, at: t0)
        XCTAssertNotNil(store.running)

        // "Count from an earlier hour" while running
        store.setRunningStart(t0.addingTimeInterval(-1800))
        XCTAssertEqual(store.running!.start, t0.addingTimeInterval(-1800))

        // Survives relaunch
        let reloaded = TimeStore(fileURL: tmp)
        XCTAssertEqual(reloaded.clients.map(\.name), ["Acme"])
        XCTAssertNotNil(reloaded.running)
        XCTAssertEqual(reloaded.running?.title, "Landing page")
        reloaded.stop()
        XCTAssertNil(reloaded.running)
        XCTAssertEqual(reloaded.entries.count, 1)
    }
}
