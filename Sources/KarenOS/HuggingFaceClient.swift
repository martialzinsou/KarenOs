import Foundation

enum HFError: LocalizedError {
    case http(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Erreur serveur (code \(code))."
        case .decoding(let msg): return "Réponse incompréhensible (\(msg))."
        }
    }
}

enum HuggingFaceClient {
    static let api = URL(string: "https://huggingface.co/api/models")!

    private static func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw HFError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HFError.decoding("\(error)")
        }
    }

    static func search(_ query: String, limit: Int = 20) async throws -> [RemoteModel] {
        var comps = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        return try await getJSON(comps.url!)
    }

    static func detail(id: String) async throws -> RemoteModel {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = URL(string: "https://huggingface.co/api/models/\(encoded)?blobs=true")!
        return try await getJSON(url)
    }

    static let curatedIDs: [String] = [
        "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
        "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
        "Qwen/Qwen2.5-3B-Instruct-GGUF",
        "HuggingFaceTB/SmolLM2-360M-Instruct-GGUF",
        "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF",
        "microsoft/Phi-3-mini-4k-instruct-gguf"
    ]
}