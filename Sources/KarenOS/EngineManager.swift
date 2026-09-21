//  ====================================================================
//    KarenOS — EngineManager.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Cycle de vie du moteur d'inférence llama-server (llama.cpp).
//    Dépend. : Foundation, SwiftUI
//  --------------------------------------------------------------------
//    Télécharge et installe llama-server (b8967) au premier lancement,
//    le lance avec un modèle GGUF sur un port libre, attend qu'il soit sain
//    (`/health`) et expose `state` (idle/ready/loading/running/failed) et
//    `chatURL`. Détecte `hasVision` (présence d'un .mmproj) et garantit un
//    arrêt propre du processus.
//  ====================================================================

import Foundation
import SwiftUI

/// Supervise le moteur d'inférence `llama-server` (llama.cpp).
///
/// Responsabilités :
/// - télécharger et installer le moteur au premier lancement (`ensureEngine`) ;
/// - charger un modèle GGUF local dans un processus dédié (`load`) ;
/// - exposer l'état visible par l'interface (`state`, `activeModelID`, `hasVision`) ;
/// - libérer proprement le processus à l'arrêt (`stop`, `deinit`).
@MainActor
final class EngineManager: ObservableObject {
    /// Cycle de vie du moteur, observé par toute l'interface.
    enum State: Equatable {
        case idle
        case installingEngine(Double)
        case ready
        case loading
        case running(String)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published private(set) var port: Int = 0
    @Published private(set) var hasVision = false

    private var process: Process?

    private static let engineVersion = "b8967"

    private var archiveFileName: String {
        "llama-\(Self.engineVersion)-bin-macos-\(Self.machineArch).tar.gz"
    }

    private var archiveURL: URL {
        AppPaths.engineDir.appendingPathComponent(archiveFileName)
    }

    private var extractedDir: URL {
        AppPaths.engineDir.appendingPathComponent("llama-\(Self.engineVersion)")
    }

    var engineExe: URL {
        extractedDir.appendingPathComponent("llama-server")
    }

    var chatURL: URL? {
        guard case .running = state, port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    var isEngineInstalled: Bool {
        FileManager.default.fileExists(atPath: engineExe.path)
    }

    var activeModelID: String? {
        if case .running(let id) = state { return id }
        return nil
    }

    static var machineArch: String {
        var u = utsname()
        uname(&u)
        let mirror = Mirror(reflecting: u.machine)
        var bytes: [Int8] = []
        for child in mirror.children {
            bytes.append(child.value as! Int8)
        }
        let name = String(cString: bytes)
        return name == "arm64" ? "arm64" : "x64"
    }

    // MARK: - Moteur

    /// Installe `llama-server` s'il manque, sinon bascule à l'état `.ready`.
    ///
    /// Le moteur est téléchargé depuis les releases GitHub de llama.cpp
    /// (`b8967`) puis extrait dans le dossier Engine. Idempotent.
    func ensureEngine() async {
        if isEngineInstalled {
            if case .idle = state { state = .ready }
            return
        }
        switch state {
        case .idle, .failed:
            break
        default:
            return
        }

        state = .installingEngine(0)
        let destination = archiveURL
        let url = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(Self.engineVersion)/\(archiveFileName)")!

        do {
            try await DownloadManager.download(url: url, to: destination) { fraction in
                Task { @MainActor in
                    if case .installingEngine = self.state {
                        self.state = .installingEngine(fraction)
                    }
                }
            }
            try? FileManager.default.removeItem(at: extractedDir)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xzf", destination.path, "-C", AppPaths.engineDir.path]
            try tar.run()
            tar.waitUntilExit()
            try? FileManager.default.removeItem(at: destination)
            state = isEngineInstalled ? .ready : .failed("Moteur introuvable après extraction.")
        } catch {
            state = .failed("Impossible de télécharger le moteur : \(error.localizedDescription)")
        }
    }

    // MARK: - Chargement d'un modèle

    /// Charge un modèle dans le moteur (arrête le modèle précédent).
    ///
    /// - Parameter model: modèle local à charger.
    /// - Returns: `true` si le moteur répond sur `/health` ; sinon, l'état
    ///   passe à `.failed` et le résultat est `false`.
    @discardableResult
    func load(model: LocalModel) async -> Bool {
        await ensureEngine()

        if case .running(let runningID) = state, runningID == model.id {
            return true
        }

        stopProcess()

        guard let exe = engineExeExists() else { return false }

        state = .loading
        let port = freePort()
        self.port = port

        try? FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        let logURL = AppPaths.serverLogURL
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logURL.path)

        let proc = Process()
        proc.executableURL = exe
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
        proc.arguments = [
            "-m", model.fileURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-c", "2048",
            "-t", "\(threads)",
            "--flash-attn", "on",
            "-ctk", "q8_0",
            "-ctv", "q8_0",
            "--mlock"
        ]
        proc.currentDirectoryURL = extractedDir
        proc.standardOutput = logHandle
        proc.standardError = logHandle
        proc.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                if self?.process === terminated {
                    self?.process = nil
                }
            }
        }
        self.process = proc

        do {
            try proc.run()
        } catch {
            state = .failed("Impossible de lancer le moteur : \(error.localizedDescription)")
            try? logHandle?.close()
            return false
        }
        try? logHandle?.close()

        let loaded = await waitForHealth(port: port, process: proc)
        if proc.isRunning {
            state = loaded ? .running(model.id) : .failed("Le modèle n'a pas répondu au chargement.")
        }
        hasVision = loaded && isVisionCapable(directory: model.directory)
        return loaded
    }

    /// Retourne `true` si un fichier `.mmproj` (projecteur de vision) se trouve
    /// aux côtés du modèle GGUF : dans ce cas l'interface activera le mode
    /// vision (images envoyées au format OpenAI vision).
    private func isVisionCapable(directory: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        return files.contains { $0.lowercased().hasSuffix(".mmproj") }
    }

    private func engineExeExists() -> URL? {
        isEngineInstalled ? engineExe : nil
    }

    /// Interroge `GET /health` jusqu'à 120 s (150 essais espacés de 800 ms)
    /// pour détecter que le serveur a fini de charger le modèle.
    private func waitForHealth(port: Int, process: Process) async -> Bool {
        let health = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<150 {
            if process.isRunning == false { return false }
            do {
                var req = URLRequest(url: health)
                req.timeoutInterval = 2
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return true
                }
            } catch {
                // pas encore prêt
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return false
    }

    /// Arrête le moteur : tue le processus, repasse à l'état `.ready` et
    /// désactive la détection vision (le prochain chargement la recalcule).
    func stop() {
        stopProcess()
        state = .ready
        hasVision = false
    }

    private func stopProcess() {
        guard let proc = process else { return }
        process = nil
        if proc.isRunning {
            proc.interrupt()
            DispatchQueue.global().async {
                if proc.isRunning {
                    proc.terminate()
                }
            }
        }
    }

    deinit {
        if let process, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Port libre

    /// Laisse le système choisir un port TCP libre, sinon retombe sur 8391.
    private func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 8391 }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = (0x7f000001 as UInt32).bigEndian
        let didBind = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard didBind else { close(fd); return 8391 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var addr2 = sockaddr_in()
        let got = withUnsafeMutablePointer(to: &addr2) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len) == 0
            }
        }
        let port = got ? Int(UInt16(bigEndian: addr2.sin_port)) : 8391
        close(fd)
        return port
    }
}