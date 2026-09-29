import Foundation
import Network

enum KVMEndpoint {
    static func fromMAC(_ mac: String, scope: String, port: UInt16) -> NWEndpoint? {
        let hex = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard hex.count == 6 else { return nil }
        var b = [UInt8]()
        for part in hex {
            guard let v = UInt8(part, radix: 16) else { return nil }
            b.append(v)
        }
        b[0] ^= 0x02
        let eui = [b[0], b[1], b[2], 0xff, 0xfe, b[3], b[4], b[5]]
        var words: [String] = []
        for i in stride(from: 0, to: 8, by: 2) {
            words.append(String(format: "%x", (Int(eui[i]) << 8) | Int(eui[i + 1])))
        }
        let host = "fe80::\(words.joined(separator: ":"))%\(scope)"
        return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
    }

    static func fromHost(_ host: String, defaultPort: UInt16) -> NWEndpoint? {
        var addr = host
        var port = defaultPort
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return nil }
            addr = String(host[host.index(after: host.startIndex)..<close])
            let rest = host[host.index(after: close)...]
            if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { port = p }
        } else if let colon = host.lastIndex(of: ":"), !host.contains("]"),
            host.filter({ $0 == ":" }).count == 1 || host.contains("%")
        {
            let tail = host[host.index(after: colon)...]
            if let p = UInt16(tail) {
                addr = String(host[..<colon])
                port = p
            }
        }
        return .hostPort(host: NWEndpoint.Host(addr), port: NWEndpoint.Port(rawValue: port)!)
    }

    static func cacheURL(name: String) -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/awdlkvm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).endpoint")
    }

    static func loadCached(name: String) -> String? {
        try? String(contentsOf: cacheURL(name: name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func saveCached(name: String, host: String) {
        try? host.write(to: cacheURL(name: name), atomically: true, encoding: .utf8)
    }
}
