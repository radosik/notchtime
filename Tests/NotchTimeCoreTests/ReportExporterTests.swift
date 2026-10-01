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

    /// September 2026 data from the real Clockify report, so the numbers can be checked
    /// against the hand-made reference workbook.
    private func septemberFixture() -> (clients: [Client], entries: [TimeEntry], range: DateInterval) {
        let josh = Client(name: "JOSH", hourlyRate: 20)
        let david = Client(name: "DavidF", projects: ["Solestra"], hourlyRate: 20)
        let rows: [(Client, String?, String, String)] = [
            (david, "Solestra", "AWS Workspace", "13:15:27"),
            (david, "Solestra", "SPF record config", "00:31:26"),
            (josh, nil, "abc buy all error", "01:01:13"),
            (josh, nil, "abc not working", "00:30:00"),
            (josh, nil, "abc website update", "08:46:23"),
            (josh, nil, "all logins red, search not working", "00:30:00"),
            (josh, nil, "download yesterdays log file", "00:37:45"),
            (josh, nil, "mck error on buy all, context destroyed", "02:32:51"),
            (josh, nil, "missing cart error", "01:10:31"),
            (josh, nil, "proxy 10 isn't working", "01:37:02"),
        ]
        var entries: [TimeEntry] = []
        for (i, r) in rows.enumerated() {
            let start = date(2026, 9, 1 + i)
            entries.append(TimeEntry(title: r.2, clientID: r.0.id, project: r.1, start: start, end: start.addingTimeInterval(secs(r.3))))
        }
        // The AWS Workspace block was really several sessions – split one to prove merging works.
        let aws = entries[0]
        entries[0].end = aws.start.addingTimeInterval(secs("03:05:45"))
        let rest = TimeEntry(title: "AWS Workspace", clientID: david.id, project: "Solestra",
                             start: date(2026, 9, 29, 16), end: date(2026, 9, 29, 16).addingTimeInterval(secs("13:15:27") - secs("03:05:45")))
        entries.append(rest)

        let range = cal.dateInterval(of: .month, for: date(2026, 9, 15))!
        return ([josh, david], entries, range)
    }

    func testGroupingMatchesReferenceNumbers() {
        let f = septemberFixture()
        let groups = ReportExporter.groups(entries: f.entries, clients: f.clients)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].clientName, "DavidF")
        XCTAssertEqual(groups[0].project, "Solestra")
        XCTAssertEqual(groups[0].totalLabel, "Total DavidF (Solestra)")
        XCTAssertEqual(groups[0].lines.map(\.title), ["AWS Workspace", "SPF record config"])
        XCTAssertEqual(DurationFormat.hms(groups[0].seconds), "13:46:53")
        XCTAssertEqual(groups[0].amount!, 275.6, accuracy: 0.001)

        XCTAssertEqual(groups[1].clientName, "JOSH")
        XCTAssertEqual(groups[1].totalLabel, "Total JOSH")
        XCTAssertEqual(groups[1].lines.count, 8)
        XCTAssertEqual(DurationFormat.hms(groups[1].seconds), "16:45:45")
        XCTAssertEqual(groups[1].amount!, 335.4, accuracy: 0.001)

        let total = groups.reduce(0.0) { $0 + $1.seconds }
        XCTAssertEqual(DurationFormat.hms(total), "30:32:38")
        XCTAssertEqual(DurationFormat.decimalHours(total), 30.54, accuracy: 0.001)
    }

    func testSheetXMLContainsExpectedCells() {
        let f = septemberFixture()
        let groups = ReportExporter.groups(entries: f.entries, clients: f.clients)
        let xml = ReportExporter.sheetXML(groups: groups, range: f.range, calendar: cal)
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">Total DavidF (Solestra)</t>"))
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">Total (01/09/2026 - 30/09/2026)</t>"))
        XCTAssertTrue(xml.contains("<t xml:space=\"preserve\">30:32:38</t>"))
        XCTAssertTrue(xml.contains("<v>611</v>"))
        XCTAssertTrue(xml.contains("proxy 10 isn&apos;t working"))
    }

    func testWorkbookIsZipAndWrittenForInspection() throws {
        let f = septemberFixture()
        let data = ReportExporter.workbook(entries: f.entries, clients: f.clients, range: f.range, calendar: cal)
        XCTAssertGreaterThan(data.count, 2000)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])

        // Written so CI can upload it and a human (or openpyxl) can open it.
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = ReportExporter.suggestedFilename(reportName: "Radomyr", range: f.range, calendar: cal)
        XCTAssertEqual(name, "Time_Report_Summary_Radomyr_01_09_2026-30_09_2026.xlsx")
        try data.write(to: dir.appendingPathComponent("test-export.xlsx"))
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormat.hms(secs("30:32:38")), "30:32:38")
        XCTAssertEqual(DurationFormat.compact(59), "00:59")
        XCTAssertEqual(DurationFormat.compact(3661), "1:01:01")
        XCTAssertEqual(DurationFormat.decimalHours(secs("13:15:27")), 13.26, accuracy: 0.0001)
    }

    func testStoreRoundTripAndRunningTimer() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchtime-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = TimeStore(fileURL: tmp)
        XCTAssertEqual(store.clients.map(\.name), ["JOSH", "DavidF"])
        let josh = store.clients[0]
        let t0 = Date().addingTimeInterval(-600)
        store.start(title: "imap fails", clientID: josh.id, project: nil, at: t0)
        XCTAssertNotNil(store.running)

        // "Count from an earlier hour" while running
        store.setRunningStart(t0.addingTimeInterval(-1800))
        XCTAssertEqual(store.running!.start, t0.addingTimeInterval(-1800))

        // Survives relaunch
        let reloaded = TimeStore(fileURL: tmp)
        XCTAssertNotNil(reloaded.running)
        XCTAssertEqual(reloaded.running?.title, "imap fails")
        reloaded.stop()
        XCTAssertNil(reloaded.running)
        XCTAssertEqual(reloaded.entries.count, 1)
    }
}
