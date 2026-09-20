//  KarenOS
//  Par Martial Zinsou

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String
    var content: String
    var attachments: [ChatAttachment] = []

    static func system(_ text: String) -> ChatMessage { ChatMessage(role: "system", content: text) }
    static func user(_ text: String, files: [ChatAttachment] = []) -> ChatMessage {
        ChatMessage(role: "user", content: text, attachments: files)
    }
    static func assistant(_ text: String = "") -> ChatMessage { ChatMessage(role: "assistant", content: text) }
}

enum ChatError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Le modèle a renvoyé une erreur (code \(code))."
        }
    }
}

enum ChatService {
    private final class TaskBox {
        var task: Task<Void, Never>?
    }

    static func streamReply(_ history: [ChatMessage], baseURL: URL, vision: Bool = false) -> AsyncThrowingStream<String, Error> {
        let box = TaskBox()
        return AsyncThrowingStream { continuation in
            box.task = Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                    req.httpMethod = "POST"
                    req.timeoutInterval = 300
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let payload: [String: Any] = [
                        "model": "local",
                        "messages": history.map { ["role": $0.role, "content": Self.apiContent(for: $0, vision: vision)] },
                        "stream": true,
                        "max_tokens": 512,
                        "temperature": 0.7
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ChatError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    for try await line in bytes.lines {
                        if box.task?.isCancelled == true { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in box.task?.cancel() }
        }
    }

    private static func apiContent(for message: ChatMessage, vision: Bool) -> Any {
        let images = vision ? message.attachments.filter { $0.kind == .image } : []
        guard !images.isEmpty else { return message.content }

        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for image in images {
            if let data = try? Data(contentsOf: image.fileURL) {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"]
                ])
            } else {
                parts.append(["type": "text", "text": "[Image illisible : \(image.fileName)]"])
            }
        }
        return parts
    }
}