// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — EngineManager.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Cycle de vie du moteur d'inférence llama-server (llama.cpp).
//    Dépend. : Foundation, SwiftUI
//  --------------------------------------------------------------------
//    Lance le llama-server embarqué (b8967 recompilé pour macOS 11) — ou,
//    à défaut, celui téléchargé depuis les releases GitHub (macOS 12+).
//    Il démarre un modèle GGUF sur un port libre, attend qu'il soit sain
//    (`/health`) et expose `state` (idle/ready/loading/running/failed) et
//    `chatURL`. Détecte `hasVision` (présence d'un .mmproj) et garantit un
//    arrêt propre du processus.
//  ====================================================================

import Darwin
import Foundation
import SwiftUI

/// Cœurs physiques, plafonnés à 8.
///
/// `activeProcessorCount` renvoie les cœurs logiques : sur un CPU Intel à
/// hyperthreading, les utiliser tous pour llama-server coûte ~35–40 % de
/// débit (mesuré sur i7-4850HQ 4C/8T : 25 tok/s à 8 threads, 40 à 4).
private func karenPhysicalCoreCount() -> Int {
    var count: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
        return min(Int(count), 8)
    }
    let logical = ProcessInfo.processInfo.activeProcessorCount
    return max(1, min(logical / 2, 8))
}

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
    /// Backend GPU réellement exposé par `llama-server` (ex. « Metal: Apple M… »).
    /// `nil` si le binaire ne compile aucun backend GPU (cas du build x64 ici).
    @Published private(set) var gpuBackend: String?

    private var process: Process?
    private var backendChecked = false

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

    /// Moteur embarqué dans le bundle (build recompilé pour macOS 11).
    /// Prioritaire sur l'archive officielle, qui exige macOS 13 : c'est lui
    /// qui permet à KarenOS de tourner sur Big Sur.
    private var bundledEngineExe: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidate = resources
            .appendingPathComponent("Engine", isDirectory: true)
            .appendingPathComponent("llama-server")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    var engineExe: URL {
        bundledEngineExe ?? extractedDir.appendingPathComponent("llama-server")
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

    /// Résumé lisible des ressources que le moteur exploite réellement.
    /// Sert d'infobulle au statut « pleine puissance » du chat.
    var resourceSummary: String {
        let cpus = ProcessInfo.processInfo.activeProcessorCount
        let ram = max(1, Int(Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0))
        var parts = ["CPU ×\(cpus)", "RAM \(ram) Go verrouillée"]
        if let gpuBackend {
            parts.append("GPU \(gpuBackend)")
        } else {
            parts.append("GPU non exposé par ce backend")
        }
        return parts.joined(separator: " · ")
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
    /// Le moteur embarqué (`Contents/Resources/Engine`) est prioritaire : il
    /// est compilé pour macOS 11. Sur macOS 12+, à défaut, l'archive officielle
    /// de llama.cpp (`b8967`) est téléchargée puis extraite. Idempotent.
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

        if #available(macOS 12.0, *) {
            // L'archive officielle (minos 13) reste utilisable sur macOS 12+.
        } else {
            state = .failed("Moteur local absent : cette version de KarenOS doit embarquer son propre llama-server pour Big Sur.")
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
        detectGpuBackendIfNeeded(exe: exe)

        try? FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        let logURL = AppPaths.serverLogURL
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        // Première tentative sur GPU s'il existe, puis repli CPU : un modèle
        // trop volumineux pour la VRAM ne doit jamais bloquer KarenOS.
        let attempts: [(gpu: Bool, label: String)] = gpuBackend == nil
            ? [(false, "CPU")]
            : [(true, "GPU"), (false, "CPU (repli)")]

        for attempt in attempts {
            if !attempt.gpu, gpuBackend != nil {
                Self.append(to: logURL, "\nKarenOS : repli CPU après échec du chargement GPU.\n")
            }

            let logHandle = FileHandle(forWritingAtPath: logURL.path)
            logHandle?.seekToEndOfFile()
            do {
                let proc = try launch(model: model, port: port, useGPU: attempt.gpu, logHandle: logHandle)
                self.process = proc
                let loaded = await waitForHealth(port: port, process: proc)
                try? logHandle?.close()

                if loaded {
                    state = .running(model.id)
                    hasVision = isVisionCapable(directory: model.directory)
                    return true
                }

                Self.append(to: logURL, "\nKarenOS : chargement \(attempt.label) non abouti — nouvel essai.\n")
                if proc.isRunning { proc.terminate() }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if proc.isRunning { proc.interrupt() }
                if self.process === proc { self.process = nil }
            } catch {
                try? logHandle?.close()
                state = .failed("Impossible de lancer le moteur : \(error.localizedDescription)")
                hasVision = false
                return false
            }
        }

        state = .failed("Le modèle n'a pas répondu au chargement.")
        hasVision = false
        return false
    }

    /// Lance `llama-server` avec le profil « pleine puissance » :
    ///
    /// - tous les cœurs logiques (`-t`, `-tb`) ;
    /// - priorité haute (`--prio 2`) et QoS `.userInteractive` ;
    /// - modèle lu en entier et verrouillé en RAM (`--no-mmap`, `--mlock`) ;
    /// - un seul slot de 8192 tokens dédié à la conversation (`-np 1`) ;
    /// - toutes les couches sur GPU (`-ngl all`) si un backend GPU existe.
    ///
    /// Le GPU n'est sollicité que lorsque `--list-devices` expose un
    /// périphérique : sur les builds x64 sans Metal, seul BLAS/Accelerate
    /// est disponible et `-ngl` n'aurait aucun effet.
    private func launch(model: LocalModel, port: Int, useGPU: Bool, logHandle: FileHandle?) throws -> Process {
        let proc = Process()
        proc.executableURL = engineExe

        let threads = karenPhysicalCoreCount()
        var arguments = [
            "-m", model.fileURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-c", "8192",
            "-np", "1",
            "-t", "\(threads)",
            "-tb", "\(threads)",
            "--prio", "2",
            "--flash-attn", "on",
            "--reasoning", "off",
            "-ctk", "q8_0",
            "-ctv", "q8_0",
            "--mlock",
            "--no-mmap"
        ]
        if useGPU {
            arguments += ["-ngl", "all"]
        }

        proc.arguments = arguments
        proc.currentDirectoryURL = engineExe.deletingLastPathComponent()
        proc.qualityOfService = .userInteractive
        proc.standardOutput = logHandle
        proc.standardError = logHandle
        proc.terminationHandler = { [weak self] terminated in
            let pid = terminated.processIdentifier
            Task { @MainActor [weak self] in
                if self?.process === terminated {
                    self?.process = nil
                }
                self?.engineProcess.clear(pid)
            }
        }
        try proc.run()
        engineProcess.set(proc.processIdentifier)
        return proc
    }

    /// Détecte les backends compilés dans `llama-server` via `--list-devices`.
    /// Le résultat conditionne l'offload GPU et l'infobulle des ressources.
    private func detectGpuBackendIfNeeded(exe: URL) {
        guard !backendChecked else { return }
        backendChecked = true

        let proc = Process()
        proc.executableURL = exe
        proc.arguments = ["--list-devices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            gpuBackend = nil
            return
        }
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        gpuBackend = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { line in
                line.hasPrefix("Metal") || line.hasPrefix("CUDA") ||
                line.hasPrefix("Vulkan") || line.hasPrefix("GPU")
            }
    }

    /// Ajoute une ligne au journal du serveur sans le tronquer.
    private static func append(to url: URL, _ text: String) {
        guard let data = text.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: data)
        try? handle.close()
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

    /// Arrête le sous-processus sans le laisser survivre à l'application.
    ///
    /// `llama-server` peut rester bloqué dans son propre arrêt « gracieux »
    /// (on l'a observé après un second SIGINT : le processus annonce qu'il
    /// se termine puis garde plusieurs Go de RAM). On envoie donc SIGTERM,
    /// on attend brièvement, puis SIGKILL. Sans cela, quitter KarenOS laissait
    /// un moteur orphelin qui monopolisait la mémoire.
    private func stopProcess() {
        guard let proc = process else { return }
        process = nil
        engineProcess.terminate()
        if proc.isRunning {
            proc.waitUntilExit()
        }
    }

    /// Filet de sécurité : garantit l'arrêt du moteur même si la vue racine
    /// n'est plus vivante (ou n'a jamais été affichée) lors de la fermeture.
    private var terminateObserver: NSObjectProtocol?

    /// Référence non isolée vers le PID du moteur.
    ///
    /// Pendant `applicationWillTerminate`, la boucle principale n'exécute
    /// plus de tâches `@MainActor` : impossible alors de lire `process`.
    /// Ce relais protégé par verrou reste accessible depuis n'importe quel
    /// contexte pour tuer le sous-processus sans le laisser orphelin.
    private final class EngineProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?

        func set(_ pid: pid_t?) {
            lock.lock()
            self.pid = pid
            lock.unlock()
        }

        /// Oublie le PID uniquement s'il correspond encore à celui du
        /// processus qui vient de se terminer (évite d'effacer un relais
        /// déjà remplacé par un lancement plus récent).
        func clear(_ pid: pid_t) {
            lock.lock()
            if self.pid == pid { self.pid = nil }
            lock.unlock()
        }

        /// SIGTERM, attente courte, puis SIGKILL si le processus s'enlise.
        func terminate() {
            lock.lock()
            let pid = self.pid
            self.pid = nil
            lock.unlock()
            guard let pid, pid > 0 else { return }

            kill(pid, SIGTERM)
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline {
                if kill(pid, 0) != 0 && errno == ESRCH { return }
                usleep(50_000)
            }
            if kill(pid, 0) == 0 || errno != ESRCH {
                kill(pid, SIGKILL)
            }
        }
    }

    private nonisolated let engineProcess = EngineProcessHandle()

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engineProcess.terminate()
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        engineProcess.terminate()
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