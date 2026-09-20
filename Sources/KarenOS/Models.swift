//  KarenOS
//  Par Martial Zinsou

import Foundation

struct RemoteModel: Identifiable, Hashable, Codable {
    let id: String
    var downloads: Int?
    var likes: Int?
    var gated: GatedValue?
    var cardData: CardData?
    var gguf: GGUFInfo?
    var siblings: [Sibling]?

    struct CardData: Codable, Hashable {
        var license: FlexibleString?
    }

    struct FlexibleString: Codable, Hashable {
        var values: [String] = []

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                values = [single]
            } else if let array = try? container.decode([String].self) {
                values = array
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(values)
        }
    }

    struct GatedValue: Codable, Hashable {
        var isGated: Bool = false

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                isGated = bool
            } else if let string = try? container.decode(String.self) {
                isGated = !string.isEmpty && string != "false"
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(isGated)
        }
    }

    struct GGUFInfo: Codable, Hashable {
        var total: Int?
        var context_length: Int?
    }

    struct Sibling: Codable, Hashable, Identifiable {
        var rfilename: String
        var size: Int64?

        var id: String { rfilename }
        var isGGUF: Bool { rfilename.lowercased().hasSuffix(".gguf") }
    }

    var author: String {
        id.components(separatedBy: "/").first ?? id
    }

    var displayName: String {
        let parts = id.components(separatedBy: "/")
        guard parts.count > 1 else { return id }
        return parts[1]
    }

    var downloadCountText: String {
        guard let d = downloads else { return "" }
        if d >= 1_000_000 { return String(format: "%.1f M", Double(d) / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1f k", Double(d) / 1_000) }
        return "\(d)"
    }

    var licenseLabel: String {
        cardData?.license?.values.first ?? ""
    }

    var totalSize: Int64? {
        siblings?.filter(\.isGGUF).map { $0.size ?? 0 }.reduce(0, +)
    }

    var contextTokens: Int? {
        gguf?.context_length
    }

    var prettyContext: String {
        guard let ctx = contextTokens else { return "" }
        if ctx >= 1000 { return "\(ctx / 1000) k" }
        return "\(ctx)"
    }

    var ggufSiblings: [Sibling] {
        siblings?.filter(\.isGGUF) ?? []
    }

    var defaultFile: Sibling? {
        let files = ggufSiblings
        if files.isEmpty { return nil }
        for pattern in ["q4_k_m", "q4_0", "q4", "q5_k_m", "q3_k_m", "q8_0"] {
            if let hit = files.first(where: { $0.rfilename.lowercased().contains(pattern) }) {
                return hit
            }
        }
        return files.min(by: { ($0.size ?? 0) < ($1.size ?? 0) })
    }

    func downloadURL(for file: Sibling) -> URL? {
        let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let name = file.rfilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.rfilename
        return URL(string: "https://huggingface.co/\(path)/resolve/main/\(name)")
    }

    func quantLabel(from file: Sibling) -> String {
        let name = file.rfilename
        for part in name.components(separatedBy: ".") {
            if part.lowercased().hasPrefix("q") && part.count < 8 {
                return part
            }
        }
        return "gguf"
    }
}