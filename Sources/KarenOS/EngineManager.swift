//  KarenOS
//  Par Martial Zinsou

import Foundation
import SwiftUI

@MainActor
final class EngineManager: ObservableObject {
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
        proc.arguments = [
            "-m", model.fileURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-c", "2048"
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
        return loaded
    }

    private func engineExeExists() -> URL? {
        isEngineInstalled ? engineExe : nil
    }

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

    func stop() {
        stopProcess()
        state = .ready
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