import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal ZIP writer/reader with no third-party dependencies.
///
/// - Writer: streams entries to disk, optional raw-deflate compression (Apple platforms),
///   and optional 64-byte data alignment, which is what the USDZ container format requires.
/// - Reader: stored and deflated entries (enough for archives made by FrameScout, Finder and Files).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt16) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    mutating func appendLE(_ v: UInt32) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }

    func readLE16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func readLE32(_ offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(self[startIndex + offset + i]) << (8 * UInt32(i)) }
        return v
    }
}

enum ZipError: LocalizedError {
    case cannotCreate(String)
    case corrupt(String)
    case unsupportedMethod(UInt16)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .cannotCreate(let p): return "Cannot create archive at \(p)."
        case .corrupt(let why): return "The ZIP archive is damaged (\(why))."
        case .unsupportedMethod(let m): return "Unsupported ZIP compression method \(m)."
        case .tooLarge: return "Archive entry exceeds 4 GB (ZIP64 is not supported)."
        }
    }
}

final class ZipWriter {
    private struct CentralEntry {
        var name: Data
        var method: UInt16
        var crc: UInt32
        var compressedSize: UInt32
        var size: UInt32
        var offset: UInt32
        var time: UInt16
        var date: UInt16
    }

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var entries: [CentralEntry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ZipError.cannotCreate(url.path)
        }
        handle = try FileHandle(forWritingTo: url)
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let date: Int = (year << 9) | (month << 5) | day
        dosTime = UInt16(truncatingIfNeeded: time)
        dosDate = UInt16(truncatingIfNeeded: date)
    }

    /// Adds an entry. `alignment` pads the local header so the file data starts on that byte boundary.
    func add(path: String, data: Data, compress: Bool = true, alignment: Int? = nil) throws {
        guard data.count < Int(UInt32.max) else { throw ZipError.tooLarge }
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        var method: UInt16 = 0
        var payload = data
        if compress, alignment == nil, data.count > 64, let deflated = Self.deflate(data), deflated.count < data.count {
            method = 8
            payload = deflated
        }

        var extra = Data()
        if let alignment, alignment > 1 {
            let base = Int(offset) + 30 + name.count
            var pad = (alignment - base % alignment) % alignment
            if pad > 0 && pad < 4 { pad += alignment }
            if pad >= 4 {
                extra.appendLE(UInt16(0x1986))
                extra.appendLE(UInt16(pad - 4))
                extra.append(Data(count: pad - 4))
            }
        }

        var header = Data()
        header.appendLE(UInt32(0x04034b50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0x0800)) // UTF-8 names
        header.appendLE(method)
        header.appendLE(dosTime)
        header.appendLE(dosDate)
        header.appendLE(crc)
        header.appendLE(UInt32(payload.count))
        header.appendLE(UInt32(data.count))
        header.appendLE(UInt16(name.count))
        header.appendLE(UInt16(extra.count))
        header.append(name)
        header.append(extra)

        guard offset < UInt64(UInt32.max) else { throw ZipError.tooLarge }
        entries.append(CentralEntry(name: name, method: method, crc: crc,
                                    compressedSize: UInt32(payload.count), size: UInt32(data.count),
                                    offset: UInt32(offset), time: dosTime, date: dosDate))
        handle.write(header)
        handle.write(payload)
        offset += UInt64(header.count + payload.count)
    }

    func add(path: String, fileURL: URL, compress: Bool = true) throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        try add(path: path, data: data, compress: compress)
    }

    /// Recursively adds a folder's contents under `prefix/`.
    func addDirectory(_ dir: URL, prefix: String) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let basePath = dir.standardizedFileURL.path
        var files: [URL] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir { files.append(url) }
        }
        for url in files.sorted(by: { $0.path < $1.path }) {
            var relative = String(url.standardizedFileURL.path.dropFirst(basePath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            let alreadyCompressed = ["jpg", "jpeg", "png", "heic", "usdz", "glb", "zip"].contains(url.pathExtension.lowercased())
            try add(path: prefix.isEmpty ? relative : "\(prefix)/\(relative)", fileURL: url, compress: !alreadyCompressed)
        }
    }

    func finish() throws {
        let cdStart = offset
        var cd = Data()
        for e in entries {
            cd.appendLE(UInt32(0x02014b50))
            cd.appendLE(UInt16(0x0314)) // made by: Unix, spec 2.0
            cd.appendLE(UInt16(20))
            cd.appendLE(UInt16(0x0800))
            cd.appendLE(e.method)
            cd.appendLE(e.time)
            cd.appendLE(e.date)
            cd.appendLE(e.crc)
            cd.appendLE(e.compressedSize)
            cd.appendLE(e.size)
            cd.appendLE(UInt16(e.name.count))
            cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0))
            cd.appendLE(UInt32(0o100644) << 16)
            cd.appendLE(e.offset)
            cd.append(e.name)
        }
        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(cd.count))
        end.appendLE(UInt32(cdStart))
        end.appendLE(UInt16(0))
        handle.write(cd)
        handle.write(end)
        try handle.close()
    }

    static func deflate(_ data: Data) -> Data? {
        #if canImport(Compression)
        let capacity = data.count + data.count / 10 + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        output.count = written
        return output
        #else
        return nil
        #endif
    }
}

final class ZipReader {
    struct Entry {
        var path: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localHeaderOffset: Int
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    private let data: Data
    private(set) var entries: [Entry] = []

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        try parse()
    }

    init(data: Data) throws {
        self.data = data
        try parse()
    }

    private func parse() throws {
        guard data.count >= 22 else { throw ZipError.corrupt("too small") }
        var eocd = -1
        let searchStart = max(0, data.count - 22 - 65535)
        var i = data.count - 22
        while i >= searchStart {
            if data.readLE32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.corrupt("no end of central directory") }
        let count = Int(data.readLE16(eocd + 10))
        var p = Int(data.readLE32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= data.count, data.readLE32(p) == 0x02014b50 else {
                throw ZipError.corrupt("bad central directory")
            }
            let method = data.readLE16(p + 10)
            let csize = Int(data.readLE32(p + 20))
            let size = Int(data.readLE32(p + 24))
            let nameLen = Int(data.readLE16(p + 28))
            let extraLen = Int(data.readLE16(p + 30))
            let commentLen = Int(data.readLE16(p + 32))
            let local = Int(data.readLE32(p + 42))
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(path: name, method: method, compressedSize: csize, size: size, localHeaderOffset: local))
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func data(for entry: Entry) throws -> Data {
        let h = entry.localHeaderOffset
        guard h + 30 <= data.count, data.readLE32(h) == 0x04034b50 else { throw ZipError.corrupt("bad local header") }
        let start = h + 30 + Int(data.readLE16(h + 26)) + Int(data.readLE16(h + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("truncated entry") }
        let payload = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, size: entry.size)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    static func inflate(_ payload: Data, size: Int) throws -> Data {
        #if canImport(Compression)
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            payload.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt("inflate failed") }
        return output
        #else
        throw ZipError.unsupportedMethod(8)
        #endif
    }
}
