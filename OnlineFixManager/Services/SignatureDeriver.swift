import Foundation

/// Derives a Steam signature profile for an unsupported client build by carrying
/// the newest bundled profile forward. Only PC-relative instruction words are
/// masked; every remaining byte must match exactly once.
enum SignatureDeriver {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Section {
        let bytes: [UInt8]
    }

    private struct Token {
        let value: UInt8?
    }

    static func derive(client: URL, reference: URL) throws -> Data {
        let build = try clientBuild(client: client)
        let raw = try Data(contentsOf: client, options: .mappedIfSafe)
        let section = try textSection(raw)
        let referenceData = try Data(contentsOf: reference)
        guard var profile = try JSONSerialization.jsonObject(with: referenceData) as? [String: Any],
              profile["arch"] as? String == "arm64",
              profile["platform"] as? String == "macos",
              profile["schema_version"] as? Int == 3,
              let signatures = profile["signatures"] as? [[String: Any]],
              !signatures.isEmpty else {
            throw Failure(message: "The reference profile is not a schema 3 macOS ARM64 profile.")
        }
        var names = Set<String>()
        var targets = Set<UInt64>()
        var updated: [[String: Any]] = []
        for entry in signatures {
            guard let name = entry["name"] as? String, !name.isEmpty, names.insert(name).inserted,
                  let pattern = entry["aob_hex"] as? String else {
                throw Failure(message: "The reference profile contains an invalid or duplicate target.")
            }
            let tokens = try portablePattern(pattern)
            let hit = try uniqueMatch(section.bytes, tokens)
            let adjustment = entry["match_offset"] as? Int ?? 0
            guard adjustment >= 0, adjustment <= hit, adjustment % 4 == 0 else {
                throw Failure(message: "\(name): invalid match_offset.")
            }
            let target = UInt64(hit - adjustment)
            guard targets.insert(target).inserted else {
                throw Failure(message: "\(name): two targets resolve to the same address.")
            }
            var copy = entry
            copy["aob_hex"] = serialize(tokens)
            updated.append(copy)
        }
        profile["steam_build"] = Int(build)
        profile["steam_build_date"] = buildDate(build)
        profile["profile_version"] = (profile["profile_version"] as? Int ?? 0) + 1
        profile["signatures"] = updated
        return try JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys])
    }

    /// Steam stores the client build beside the client as a manifest. The plain
    /// manifest describes the installed files; signed manifests can be newer when
    /// an update is pending but inhibited by steam.cfg.
    static func clientBuild(client: URL) throws -> UInt32 {
        let package = client.deletingLastPathComponent().appendingPathComponent("package", isDirectory: true)
        let names = ["steam_client_osx", "steam_client_signed-2_osx", "steam_client_signed_osx"]
        for name in names {
            let url = package.appendingPathComponent("\(name).manifest")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                return try manifestBuild(url)
            } catch {
                // An invalid installed manifest is fatal; a bad pending signed
                // manifest is skipped in favour of the next available one.
                if name == "steam_client_osx" { throw error }
            }
        }
        throw Failure(message: "No Steam build manifest beside the client.")
    }

    private static func manifestBuild(_ manifest: URL) throws -> UInt32 {
        let raw = try Data(contentsOf: manifest)
        guard raw.count > 0, raw.count <= 1024 * 1024, !raw.contains(0),
              let text = String(data: raw, encoding: .utf8) else {
            throw Failure(message: "Invalid Steam build manifest: \(manifest.lastPathComponent)")
        }
        let expression = try NSRegularExpression(pattern: #""version"\s*"([^"]*)""#)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: text) else {
            throw Failure(message: "Invalid Steam build in \(manifest.lastPathComponent).")
        }
        let value = String(text[range])
        guard value.range(of: #"^[1-9][0-9]{0,9}$"#, options: .regularExpression) != nil,
              let build = UInt32(value) else {
            throw Failure(message: "Invalid Steam build in \(manifest.lastPathComponent).")
        }
        return build
    }

    private static func buildDate(_ build: UInt32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(build)))
    }

    private static func textSection(_ data: Data) throws -> Section {
        var slice = [UInt8](data)
        if slice.count >= 8, slice[0] == 0xca, slice[1] == 0xfe, slice[2] == 0xba,
           slice[3] == 0xbe || slice[3] == 0xbf {
            let wide = slice[3] == 0xbf
            let count = Int(readBig(UInt32.self, slice, 4))
            let stride = wide ? 32 : 20
            guard count > 0, count <= (slice.count - 8) / stride else {
                throw Failure(message: "Invalid universal Mach-O header.")
            }
            var found: [UInt8]?
            for index in 0..<count {
                let offset = 8 + index * stride
                let cpu = readBig(UInt32.self, slice, offset)
                let start = wide ? Int(readBig(UInt64.self, slice, offset + 8)) : Int(readBig(UInt32.self, slice, offset + 8))
                let size = wide ? Int(readBig(UInt64.self, slice, offset + 16)) : Int(readBig(UInt32.self, slice, offset + 12))
                guard start >= 0, size >= 0, start <= slice.count, size <= slice.count - start else {
                    throw Failure(message: "A Mach-O slice is outside the file.")
                }
                if cpu == 0x0100000c {
                    guard found == nil else { throw Failure(message: "Expected exactly one ARM64 slice.") }
                    found = Array(slice[start..<start + size])
                }
            }
            guard let arm = found else { throw Failure(message: "The client has no ARM64 slice.") }
            slice = arm
        }
        guard slice.count >= 32, slice[0] == 0xcf, slice[1] == 0xfa, slice[2] == 0xed, slice[3] == 0xfe,
              readLE(UInt32.self, slice, 4) == 0x0100000c else {
            throw Failure(message: "Expected an ARM64 Mach-O client.")
        }
        let count = Int(readLE(UInt32.self, slice, 16))
        let size = Int(readLE(UInt32.self, slice, 20))
        guard size <= slice.count - 32 else { throw Failure(message: "Truncated Mach-O load commands.") }
        var offset = 32
        let end = 32 + size
        var sections: [Section] = []
        for _ in 0..<count {
            guard offset + 8 <= end else { throw Failure(message: "Truncated load command.") }
            let command = readLE(UInt32.self, slice, offset)
            let length = Int(readLE(UInt32.self, slice, offset + 4))
            guard length >= 8, offset + length <= end else { throw Failure(message: "Invalid load command size.") }
            if command == 0x19 {
                guard length >= 72 else { throw Failure(message: "Truncated segment command.") }
                let nsects = Int(readLE(UInt32.self, slice, offset + 64))
                guard nsects <= (length - 72) / 80 else { throw Failure(message: "Truncated section table.") }
                for index in 0..<nsects {
                    let base = offset + 72 + index * 80
                    let name = String(decoding: slice[(base + 0)..<(base + 16)], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    let segment = String(decoding: slice[(base + 16)..<(base + 32)], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    let address = readLE(UInt64.self, slice, base + 32)
                    let length = Int(readLE(UInt64.self, slice, base + 40))
                    let start = Int(readLE(UInt32.self, slice, base + 48))
                    if name == "__text", segment == "__TEXT" {
                        guard length > 0, start >= 0, start <= slice.count, length <= slice.count - start,
                              address % 4 == 0 else {
                            throw Failure(message: "Invalid __TEXT,__text section.")
                        }
                        sections.append(Section(bytes: Array(slice[start..<start + length])))
                    }
                }
            }
            offset += length
        }
        guard sections.count == 1 else { throw Failure(message: "Expected exactly one __TEXT,__text section.") }
        return sections[0]
    }

    private static func portablePattern(_ pattern: String) throws -> [Token] {
        let parts = pattern.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard !parts.isEmpty, parts.count <= 4096, parts.count % 4 == 0 else {
            throw Failure(message: "Expected aligned hex bytes or ?? (maximum 4096 bytes).")
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(parts.count)
        for part in parts {
            if part == "??" { tokens.append(Token(value: nil)); continue }
            guard part.count == 2, let value = UInt8(part, radix: 16) else {
                throw Failure(message: "Invalid byte in the reference signature.")
            }
            tokens.append(Token(value: value))
        }
        for index in stride(from: 0, to: tokens.count, by: 4) {
            if tokens[index..<index + 4].contains(where: { $0.value == nil }) { continue }
            var word: UInt32 = 0
            for offset in 0..<4 {
                word |= UInt32(tokens[index + offset].value!) << (8 * offset)
            }
            // B/BL and ADR/ADRP encode addresses that move between builds.
            if (word & 0x7c000000) == 0x14000000 ||
               (word & 0x9f000000) == 0x10000000 ||
               (word & 0x9f000000) == 0x90000000 {
                for offset in 0..<4 { tokens[index + offset] = Token(value: nil) }
            }
        }
        guard tokens.compactMap({ $0.value }).count >= 16 else {
            throw Failure(message: "Too few fixed bytes after masking relative addresses.")
        }
        return tokens
    }

    private static func serialize(_ tokens: [Token]) -> String {
        tokens.map { $0.value.map { String(format: "%02X", $0) } ?? "??" }.joined(separator: " ")
    }

    private static func uniqueMatch(_ code: [UInt8], _ tokens: [Token]) throws -> Int {
        var offsets: [Int] = []
        var bytes: [UInt8] = []
        for (index, token) in tokens.enumerated() {
            if let value = token.value { offsets.append(index); bytes.append(value) }
        }
        guard !offsets.isEmpty, offsets.count >= 16 else {
            throw Failure(message: "Too few fixed bytes after masking relative addresses.")
        }
        let length = tokens.count
        let anchor = offsets[0]
        let anchorByte = bytes[0]
        var found: Int?
        var index = 0
        let limit = code.count - length
        while index <= limit {
            if code[index + anchor] == anchorByte {
                var same = true
                for position in 1..<offsets.count where code[index + offsets[position]] != bytes[position] {
                    same = false; break
                }
                if same {
                    if found != nil { throw Failure(message: "A signature is ambiguous; manual analysis is required.") }
                    found = index
                }
            }
            index += 4
        }
        guard let hit = found else { throw Failure(message: "A signature is missing; manual analysis is required.") }
        return hit
    }

    private static func readLE<T: FixedWidthInteger>(_ type: T.Type, _ bytes: [UInt8], _ offset: Int) -> T {
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value |= T(bytes[offset + index]) << (8 * index)
        }
        return value
    }

    private static func readBig<T: FixedWidthInteger>(_ type: T.Type, _ bytes: [UInt8], _ offset: Int) -> T {
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value = (value << 8) | T(bytes[offset + index])
        }
        return value
    }
}
