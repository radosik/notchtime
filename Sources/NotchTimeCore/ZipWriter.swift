import Foundation

/// Minimal ZIP container writer (method 0 = stored). Enough for an .xlsx,
/// which is just a zip of XML files. No external dependencies.
struct ZipWriter {
    private struct Entry {
        let name: [UInt8]
        let data: Data
        let crc: UInt32
        let offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(date: Date = Date()) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        dosDate = UInt16(((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
    }

    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(body.count)

        body.append(le32(0x04034b50))          // local file header signature
        body.append(le16(20))                  // version needed
        body.append(le16(0))                   // flags
        body.append(le16(0))                   // method: stored
        body.append(le16(dosTime))
        body.append(le16(dosDate))
        body.append(le32(crc))
        body.append(le32(UInt32(data.count)))  // compressed size
        body.append(le32(UInt32(data.count)))  // uncompressed size
        body.append(le16(UInt16(nameBytes.count)))
        body.append(le16(0))                   // extra length
        body.append(contentsOf: nameBytes)
        body.append(data)

        entries.append(Entry(name: nameBytes, data: data, crc: crc, offset: offset))
    }

    func finish() -> Data {
        var out = body
        let cdStart = UInt32(out.count)
        for e in entries {
            out.append(le32(0x02014b50))       // central directory header
            out.append(le16(20))               // version made by
            out.append(le16(20))               // version needed
            out.append(le16(0))                // flags
            out.append(le16(0))                // method
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(e.crc))
            out.append(le32(UInt32(e.data.count)))
            out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(e.name.count)))
            out.append(le16(0))                // extra
            out.append(le16(0))                // comment
            out.append(le16(0))                // disk number
            out.append(le16(0))                // internal attrs
            out.append(le32(0))                // external attrs
            out.append(le32(e.offset))
            out.append(contentsOf: e.name)
        }
        let cdSize = UInt32(out.count) - cdStart
        out.append(le32(0x06054b50))           // end of central directory
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(cdSize))
        out.append(le32(cdStart))
        out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])
    }

    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
