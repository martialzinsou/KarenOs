//  ====================================================================
//    KarenOS — Multimodal.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Entrées non textuelles : pièces jointes et dictée vocale.
//    Dépend. : Foundation, AppKit, Speech, AVFoundation, UniformTypeIdentifiers
//  --------------------------------------------------------------------
//    ChatAttachment normalise un fichier joint (catégorisé image/vidéo/audio/
//    autre + type MIME). AttachmentPanel ouvre un NSOpenPanel ciblé.
//    SpeechInputController gère la dictée locale : SFSpeechRecognizer avec
//    préférence on-device et repli automatique si le modèle local échoue.
//  ====================================================================

import Foundation
import AppKit
import Speech
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Pièces jointes

/// Un fichier joint à un message, catégorisé par type.
///
/// L'init depuis une URL infère la catégorie (`.image`, `.video`, `.audio`,
/// `.file`) via l'extension, et `mimeType` fournit le type MIME utile à
/// l'encodage vision (data URI).
struct ChatAttachment: Identifiable, Equatable {
    /// Nature du fichier, choisie par l'utilisateur ou déduite de l'extension.
    enum Kind: String {
        case image
        case video
        case audio
        case file
    }

    let id = UUID()
    var kind: Kind
    var fileName: String
    var fileURL: URL

    var mimeType: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "aiff": return "audio/aiff"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    init(url: URL) {
        self.fileURL = url
        self.fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"].contains(ext) {
            kind = .image
        } else if ["mp4", "m4v", "mov", "avi", "mkv", "webm"].contains(ext) {
            kind = .video
        } else if ["mp3", "m4a", "wav", "aiff", "aif", "caf", "flac", "ogg"].contains(ext) {
            kind = .audio
        } else {
            kind = .file
        }
    }
}

/// Ouvre un `NSOpenPanel` filtré par type (image, vidéo, audio ou fichier).
    enum AttachmentPanel {
    /// Panneau de sélection multiple; retourne les URLs choisies (vide si annulé).
    static func pick(kind: ChatAttachment.Kind) -> [URL] {
        var types: [UTType]
        switch kind {
        case .image: types = [.image]
        case .video: types = [.movie]
        case .audio: types = [.audio]
        case .file: types = [.data]
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = types
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func pickAnyFile() -> [URL] {
        pick(kind: .file)
    }
}

// MARK: - Saisie vocale (dictée locale)

/// Dictée vocale locale via le framework `Speech` (`SFSpeechRecognizer`).
///
/// - Demande l'autorisation au premier usage (Microphone + Reconnaissance
///   vocale, décrites dans `Info.plist`).
/// - Privilégie la reconnaissance sur l'appareil (`requiresOnDeviceRecognition`),
///   avec repli automatique côté serveur si le modèle local échoue.
/// - Expose `liveText` (transcription en direct) et délègue le texte final
///   par `onFinalText` (inséré dans le champ de saisie du chat).
final class SpeechInputController: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var liveText = ""
    @Published var errorMessage: String?

    var onFinalText: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onDeviceFailed = false
    private var deliveredFinal = false

    func start() {
        guard !isListening else { return }
        stopSession()
        deliveredFinal = false
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .authorized:
                    self.startSession()
                default:
                    self.errorMessage = "Reconnaissance vocale non autorisée (Réglages → Confidentialité → Microphone & Dictée)."
                }
            }
        }
    }

    func stop() {
        stopSession()
    }

    private func startSession() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            errorMessage = "Reconnaissance vocale indisponible pour la langue « \(Locale.current.identifier) »."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 10.15, *) {
            request.requiresOnDeviceRecognition = !onDeviceFailed
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    if result.isFinal {
                        let text = result.bestTranscription.formattedString
                        if !text.isEmpty && !self.deliveredFinal {
                            self.deliveredFinal = true
                            self.onFinalText?(text)
                        }
                        self.stopSession()
                    }
                } else if let error {
                    if !self.onDeviceFailed {
                        self.onDeviceFailed = true
                        self.retryWithoutOnDevice()
                    } else {
                        self.errorMessage = "La dictée a échoué : \(error.localizedDescription)"
                        self.stopSession()
                    }
                }
            }
        }

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            liveText = ""
        } catch {
            errorMessage = "Impossible de démarrer le micro : \(error.localizedDescription)"
            stopSession()
        }
    }

    private func retryWithoutOnDevice() {
        stopSession()
        startSession()
    }

    private func stopSession() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        liveText = ""
    }
}