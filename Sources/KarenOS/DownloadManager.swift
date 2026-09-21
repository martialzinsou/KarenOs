// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — DownloadManager.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Téléchargement fiable de fichiers avec progression et reprises.
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    Télécharge une ressource vers une destination avec 3 tentatives et
//    2 s d'attente entre les échecs. Reprend le fichier déjà partiellement
//    présent. DownloadDelegate rapporte la progression via URLSessionDownload-
//    Delegate. Valide le code HTTP puis déplace le fichier temporaire.
//  ====================================================================

import Foundation

/// Délègue `URLSession` pour rapporter la progression d'un téléchargement.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var progress: ((Double) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = max(totalBytesExpectedToWrite, totalBytesWritten)
        let fraction = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        progress?(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    }
}

/// Outils de téléchargement : reprise si le fichier existe, 3 tentatives,
    /// contrôle du code HTTP et déplacement du fichier temporaire.
    enum DownloadManager {
    /// Télécharge `url` vers `destination` (celles-ci absolues).
    ///
    /// - Parameters:
    ///   - url: ressource distante.
    ///   - destination: fichier local de sortie.
    ///   - progress: rappel (0...1) appelé sur n'importe quel thread ; vide = sans suivi.
    static func download(url: URL, to destination: URL, progress: ((Double) -> Void)? = nil) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path),
           let size = (try? fm.attributesOfItem(atPath: destination.path))?[.size] as? Int64,
           size > 0 {
            progress?(1)
            return
        }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await attemptDownload(url: url, to: destination, progress: progress, fm: fm)
                progress?(1)
                return
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private static func attemptDownload(url: URL, to destination: URL, progress: ((Double) -> Void)?, fm: FileManager) async throws {
        let delegate = DownloadDelegate()
        delegate.progress = progress
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (tmpURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.httpStatus(http.statusCode)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try? fm.removeItem(at: destination)
        try fm.moveItem(at: tmpURL, to: destination)
    }
}