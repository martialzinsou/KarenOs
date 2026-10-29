// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — ChatService.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Construction de l'historique et streaming des réponses du modèle.
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    ChatMessage est l'élément de l'historique (rôle, contenu, pièces jointes).
//    ChatService.streamReply appelle POST /v1/chat/completions en streaming
//    SSE et rend chaque morceau de texte. En mode vision, le contenu devient
//    multi-part (texte + images encodées en base64, format OpenAI).
//    L'annulation de la lecture arrête proprement la tâche d'arrière-plan.
//  ====================================================================

import Foundation

/// Un message de l'historique de conversation.
///
/// - `system` : consigne (personnalité, compétence…), non affichée ;
/// - `user`  : message de l'utilisateur, éventuellement accompagné de fichiers ;
/// - `assistant` : réponse du modèle, remplie progressivement en streaming.
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

/// Client SSE compatible macOS 11 (Big Sur).
///
/// `URLSession.bytes(for:)` et `AsyncLineSequence` n'existent qu'à partir de
/// macOS 12. Ce délégué lit les octets au fil de l'eau, recompose les lignes
/// et pousse le texte (réponse ou réflexion) dans le flux asynchrone.
private final class SSEClient: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var finished = false
    private var sawReasoning = false
    private var sawContent = false

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func start(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        let session = self.session
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        finish(nil)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        session?.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(ChatError.badStatus(http.statusCode))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            handle(line)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        if !buffer.isEmpty {
            var lineData = buffer
            if lineData.last == 0x0D { lineData.removeLast() }
            if let line = String(data: lineData, encoding: .utf8) { handle(line) }
            buffer.removeAll()
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                finish(nil)
            } else {
                finish(error)
            }
        } else {
            finish(nil)
        }
    }

    private func handle(_ line: String) {
        guard line.hasPrefix("data:") else { return }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            finish(nil)
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return }

        // Gemma 4 et les modèles « thinking » streament leur réflexion dans
        // `reasoning_content` et la réponse dans `content`. Ignorer la
        // réflexion laissait la bulle vide puis « C'est » quand le budget de
        // tokens était consommé par le raisonnement. On affiche la réflexion
        // tant qu'aucune réponse n'est disponible, puis la réponse.
        if let text = delta["content"] as? String, !text.isEmpty {
            if sawReasoning && !sawContent {
                continuation.yield("\n\nRéponse :\n")
            }
            sawContent = true
            continuation.yield(text)
        } else if let thought = (delta["reasoning_content"] as? String)
            ?? (delta["reasoning"] as? String), !thought.isEmpty {
            if !sawReasoning {
                sawReasoning = true
                continuation.yield("Réflexion :\n")
            }
            continuation.yield(thought)
        }
    }
}

/// Sert le dialogue avec le moteur : envoi de l'historique et lecture
/// streaming des réponses `data:` (SSE).
enum ChatService {
    /// Appelle `POST /v1/chat/completions` en streaming.
    ///
    /// - Parameters:
    ///   - history: messages précédents (`system`/`user`/`assistant`).
    ///   - baseURL: adresse HTTP du moteur (ex. `http://127.0.0.1:8391`).
    ///   - vision: si `true`, les images jointes sont encodées en base64 dans
    ///     le format multi-part OpenAI (nécessite un `.mmproj` côté modèle).
    /// - Returns: un flux qui rend chaque fragment de texte généré.
    static func streamReply(_ history: [ChatMessage], baseURL: URL, vision: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let client = SSEClient(continuation: continuation)
            continuation.onTermination = { _ in client.cancel() }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                    req.httpMethod = "POST"
                    req.timeoutInterval = 300
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let guardText = """
                    Tu es un modèle de texte uniquement : tu ne peux PAS lire d'images, de fichiers ni de captures d'écran (pas de vision).
                    Ne tente jamais de lire ni d'ouvrir un fichier quelconque, n'invente pas son contenu et ne génère jamais de message d'erreur du type « ERROR: Cannot read … (this model does not support image input) ».
                    Si l'utilisateur joint un fichier, réponds simplement (en français) que tu ne peux pas le voir.
                    """
                    var prepared = history
                    if let first = prepared.firstIndex(where: { $0.role == "system" }) {
                        prepared[first].content += "\n\n" + guardText
                    } else {
                        prepared.insert(ChatMessage.system(guardText), at: 0)
                    }
                    let payload: [String: Any] = [
                        "model": "local",
                        "messages": prepared.map { ["role": $0.role, "content": Self.apiContent(for: $0, vision: vision)] },
                        "stream": true,
                        "max_tokens": 512,
                        "temperature": 0.7
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    client.start(req)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Construit le `content` d'un message pour l'API :
    /// - simple chaîne si aucun fichier (ou vision inactivée) ;
    /// - sinon un tableau multi-part `[{"type":"text"...},{"type":"image_url"...}]`
    ///   où chaque image est lue et encodée en base64 depuis le disque.
    ///
    /// - Parameter vision: passe à `false` si le modèle n'est pas vision
    ///   (lecture des images évitée et pièces jointes ignorées).
    ///
    /// Toute pièce jointe non transmise au modèle (image sans vision, ou
    /// vidéo/audio/fichier quelconque) est signalée au modèle sous forme de
    /// texte : il sait ainsi à quoi correspond la pièce jointe au lieu de
    /// l'ignorer ou d'inventer une erreur.
    private static func apiContent(for message: ChatMessage, vision: Bool) -> Any {
        let transmittedImages = vision ? message.attachments.filter { $0.kind == .image } : []
        let untransmitted = message.attachments.filter { $0.kind != .image || !vision }

        var text = message.content
        for _ in untransmitted {
            if !text.isEmpty { text += "\n\n" }
            text += "[Pièce jointe : l'utilisateur a joint un fichier que tu ne peux pas voir. Ne tente jamais de le lire et n'invente pas son contenu.]"
        }

        guard !transmittedImages.isEmpty else { return text }

        var parts: [[String: Any]] = []
        if !text.isEmpty {
            parts.append(["type": "text", "text": text])
        }
        for image in transmittedImages {
            if let data = try? Data(contentsOf: image.fileURL) {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"]
                ])
            } else {
                parts.append(["type": "text", "text": "[Image jointe illisible, ne tente pas de la lire]"])
            }
        }
        return parts
    }
}