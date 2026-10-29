import Darwin
import Foundation

// Smoke test du moteur KarenOS contre llama.cpp.
// Compilation : Scripts/build-engine-cli.sh
// Usage : karen-engine-cli [basic|utf8|rolling|reuse|cancel|cycles|edge|all] <modele.gguf>
// Sans argument de modèle, KARENOS_MODEL est consulté.

let defaultModel = ProcessInfo.processInfo.environment["KARENOS_MODEL"] ?? ""

func rssMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}

func chatPrompt(system: String, user: String) -> String {
    """
    <|im_start|>system
    \(system)<|im_end|>
    <|im_start|>user
    \(user)<|im_end|>
    <|im_start|>assistant
    """
}

func makeEngine(model: String, context: Int, batch: Int, ubatch: Int, gpuLayers: Int32) async throws -> LlamaEngine {
    let config = LlamaConfiguration(
        modelPath: model,
        contextSize: context,
        batchSize: batch,
        microBatchSize: ubatch,
        gpuLayers: gpuLayers,
        useMmap: true,
        useMlock: false,
        flashAttention: .automatic,
        kvCacheTypeK: .f16,
        kvCacheTypeV: .f16
    )
    let start = Date()
    let engine = try await LlamaEngine.load(configuration: config)
    let elapsed = Date().timeIntervalSince(start)
    print("[load] \(await engine.modelDescription) · ctx=\(await engine.contextSize) · \(String(format: "%.2f", elapsed)) s · RSS=\(String(format: "%.0f", rssMB())) Mo")
    return engine
}

func collect(_ stream: AsyncThrowingStream<String, Error>, onFirst: (() -> Void)? = nil) async throws -> String {
    var output = ""
    var first = true
    for try await piece in stream {
        if first {
            first = false
            onFirst?()
        }
        output += piece
    }
    return output
}

func testBasic(model: String) async throws {
    print("\n=== 1. Streaming de base (greedy) ===")
    let engine = try await makeEngine(model: model, context: 1024, batch: 256, ubatch: 128, gpuLayers: 0)
    defer { Task { await engine.shutdown() } }

    let system = "Tu es KarenOS, un assistant local concis. Réponds en français."
    let keep = await engine.tokenCount(of: system)
    let prompt = chatPrompt(system: system, user: "Cite trois avantages d'un LLM exécuté en local.")
    print("[tokens] préfixe système = \(keep) · prompt complet = \(await engine.tokenCount(of: prompt))")

    var firstAt: Date?
    let start = Date()
    let text = try await collect(
        await engine.stream(
            prompt: prompt,
            keepTokens: keep,
            parameters: .init(temperature: 0, topK: 40, topP: 0.95, minP: 0.05, seed: 1, maxTokens: 64)
        )
    ) { firstAt = Date() }

    let first = firstAt.map { $0.timeIntervalSince(start) } ?? -1
    let metrics = await engine.lastMetrics
    print("[réponse] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    print(String(format: "[mesures] TTFT=%.3f s · %.1f tok/s · prompt=%d · générés=%d · réutilisés=%d",
                 first, metrics.tokensPerSecond, metrics.promptTokens,
                 metrics.generatedTokens, metrics.reusedTokens))
}

func testUTF8() async throws {
    print("\n=== 2. Reconstruction UTF-8 (emoji coupé) ===")
    var accumulator = UTF8Accumulator()
    let emoji = Array("😀".utf8) // F0 9F 98 80
    print("[octets] \(emoji.map { String(format: "%02X", $0) }.joined(separator: " "))")
    var pieces: [String] = []
    if let a = accumulator.append([emoji[0]]) { pieces.append(a) }
    if let b = accumulator.append(Array(emoji[1...2])) { pieces.append(b) }
    if let c = accumulator.append([emoji[3]]) { pieces.append(c) }
    if let d = accumulator.flush() { pieces.append(d) }
    let result = pieces.joined()
    print("[fragments] \(pieces) → \"\(result)\"")
    if result != "😀" { throw LlamaEngineError.decodeFailed(code: -2) }

    var invalid = UTF8Accumulator()
    let replacement = invalid.append([0x80]) ?? ""
    print("[octet invalide] \"\(replacement)\" (attendu U+FFFD)")
    if replacement != "\u{FFFD}" { throw LlamaEngineError.decodeFailed(code: -3) }
}

func testRolling(model: String) async throws {
    print("\n=== 3. Contexte saturé + KV cache roulant ===")
    let engine = try await makeEngine(model: model, context: 256, batch: 64, ubatch: 64, gpuLayers: 0)
    defer { Task { await engine.shutdown() } }

    let filler = String(repeating: "La mémoire locale est précieuse et le contexte est limité. ", count: 60)
    let prompt = chatPrompt(system: "Réponds brièvement.", user: "\(filler)\nRésume en une phrase.")
    print("[prompt] \(await engine.tokenCount(of: prompt)) tokens avant ajustement")

    let text = try await collect(
        await engine.stream(
            prompt: prompt,
            keepTokens: 0,
            parameters: .init(temperature: 0, seed: 7, maxTokens: 160)
        )
    )
    let metrics = await engine.lastMetrics
    print("[réponse] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("[mesures] prompt conservé=\(metrics.promptTokens) · générés=\(metrics.generatedTokens) · décalages KV=\(metrics.contextShiftCount)")
    if metrics.contextShiftCount == 0 { throw LlamaEngineError.decodeFailed(code: -4) }
    if metrics.generatedTokens < 64 { throw LlamaEngineError.decodeFailed(code: -5) }
}

func testReuse(model: String) async throws {
    print("\n=== 4. Réutilisation du préfixe (multi-tour) ===")
    let engine = try await makeEngine(model: model, context: 1024, batch: 256, ubatch: 128, gpuLayers: 0)
    defer { Task { await engine.shutdown() } }

    let system = "Tu es un assistant bref."
    let keep = await engine.tokenCount(of: system)
    let turn1 = chatPrompt(system: system, user: "Dis bonjour.")
    let answer1 = try await collect(
        await engine.stream(prompt: turn1, keepTokens: keep,
                            parameters: .init(temperature: 0, seed: 3, maxTokens: 16))
    )
    let turn2 = turn1 + answer1 + "\n<|im_end|>\n<|im_start|>user\nEt en anglais ?<|im_end|>\n<|im_start|>assistant\n"
    let answer2 = try await collect(
        await engine.stream(prompt: turn2, keepTokens: keep,
                            parameters: .init(temperature: 0, seed: 3, maxTokens: 16))
    )
    let answer3 = try await collect(
        await engine.stream(prompt: turn1, keepTokens: keep,
                            parameters: .init(temperature: 0, seed: 4, maxTokens: 8))
    )
    let metrics = await engine.lastMetrics
    print("[tour 1] \(answer1.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("[tour 2] \(answer2.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("[retour arrière] \(answer3.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("[mesures] prompt=\(metrics.promptTokens) · réutilisés=\(metrics.reusedTokens)")
    if metrics.reusedTokens <= keep { throw LlamaEngineError.decodeFailed(code: -6) }
}

func testCancel(model: String) async throws {
    print("\n=== 5. Annulation coopérative ===")
    let engine = try await makeEngine(model: model, context: 1024, batch: 256, ubatch: 128, gpuLayers: 0)
    defer { Task { await engine.shutdown() } }

    let prompt = chatPrompt(system: "Écris un long texte.", user: "Raconte une histoire de 500 mots.")
    let start = Date()
    var fragments = 0
    var cancelled = false
    do {
        for try await _ in await engine.stream(
            prompt: prompt,
            keepTokens: 0,
            parameters: .init(temperature: 0.8, seed: 9, maxTokens: 512)
        ) {
            fragments += 1
            if fragments == 2 {
                engine.cancel()
            }
        }
    } catch {
        cancelled = true
        print("[annulation] \(error.localizedDescription)")
    }
    let elapsed = Date().timeIntervalSince(start)
    print(String(format: "[mesures] %d fragments · %.3f s · annulé=%@",
                 fragments, elapsed, cancelled ? "oui" : "non"))
    if !cancelled { throw LlamaEngineError.decodeFailed(code: -7) }
}

func testCycles(model: String) async throws {
    print("\n=== 6. Chargement / libération répétés ===")
    var samples: [Double] = []
    for cycle in 1...3 {
        let engine = try await makeEngine(model: model, context: 512, batch: 128, ubatch: 64, gpuLayers: 0)
        let text = try await collect(
            await engine.stream(
                prompt: chatPrompt(system: "Réponds en un mot.", user: "Capitale de la France ?"),
                keepTokens: 0,
                parameters: .init(temperature: 0, seed: 1, maxTokens: 8)
            )
        )
        print("[cycle \(cycle)] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        await engine.shutdown()
        try await Task.sleep(nanoseconds: 300_000_000)
        let rss = rssMB()
        samples.append(rss)
        print(String(format: "[cycle %d] après shutdown · RSS=%.0f Mo", cycle, rss))
    }
    let growth = (samples.last ?? 0) - (samples.first ?? 0)
    print(String(format: "[mémoire] croissance entre cycle 1 et 3 : %.0f Mo", growth))
}

func testEdge(model: String) async throws {
    print("\n=== 7. Erreurs, concurrence et cycle de vie ===")

    do {
        _ = try await LlamaEngine.load(
            configuration: .init(modelPath: "/tmp/modele-inexistant.gguf")
        )
        throw LlamaEngineError.decodeFailed(code: -8)
    } catch let error as LlamaEngineError {
        if case .modelNotFound = error {
            print("[attendu] \(error.localizedDescription)")
        } else {
            throw error
        }
    }

    // gpuLayers = -1 : sur un Mac sans backend Metal, llama.cpp reste CPU.
    let engine = try await makeEngine(
        model: model, context: 512, batch: 128, ubatch: 64, gpuLayers: -1
    )

    let prompt = chatPrompt(system: "Réponds en un mot.", user: "Bonjour ?")
    let firstStream = await engine.stream(
        prompt: prompt,
        parameters: .init(temperature: 0, seed: 11, maxTokens: 64)
    )
    let firstTask = Task { try await collect(firstStream) }

    for _ in 0..<100 {
        if await engine.isGenerating { break }
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    let secondStream = await engine.stream(
        prompt: prompt,
        parameters: .init(temperature: 0, seed: 12, maxTokens: 4)
    )
    do {
        _ = try await collect(secondStream)
        throw LlamaEngineError.decodeFailed(code: -9)
    } catch let error as LlamaEngineError {
        if case .busy = error {
            print("[attendu] seconde génération refusée : \(error.localizedDescription)")
        } else {
            throw error
        }
    }

    // La seconde requête refusée ne doit pas annuler la première : son
    // CancelBox n'a pas encore d'époque et ne touche donc pas l'abort flag.
    try await Task.sleep(nanoseconds: 500_000_000)
    if await !engine.isGenerating {
        throw LlamaEngineError.decodeFailed(code: -11)
    }
    print("[attendu] la première génération survit au refus de la seconde")
    engine.cancel()
    do {
        _ = try await firstTask.value
    } catch let error as LlamaEngineError {
        if case .cancelled = error {
            print("[attendu] première génération annulée proprement")
        } else {
            throw error
        }
    }

    // Prompt vide et préfixe système impossible à conserver.
    do {
        _ = try await collect(await engine.stream(prompt: ""))
        throw LlamaEngineError.decodeFailed(code: -12)
    } catch let error as LlamaEngineError {
        if case .emptyPrompt = error {
            print("[attendu] prompt vide refusé")
        } else {
            throw error
        }
    }
    let huge = String(repeating: "contexte ", count: 2_000)
    do {
        _ = try await collect(
            await engine.stream(
                prompt: huge,
                keepTokens: 500,
                parameters: .init(temperature: 0, seed: 13, maxTokens: 64)
            )
        )
        throw LlamaEngineError.decodeFailed(code: -13)
    } catch let error as LlamaEngineError {
        if case .promptTooLong = error {
            print("[attendu] préfixe système trop grand : \(error.localizedDescription)")
        } else {
            throw error
        }
    }

    await engine.shutdown()
    let afterShutdown = await engine.stream(prompt: prompt)
    do {
        _ = try await collect(afterShutdown)
        throw LlamaEngineError.decodeFailed(code: -10)
    } catch let error as LlamaEngineError {
        if case .engineNotLoaded = error {
            print("[attendu] après shutdown : \(error.localizedDescription)")
        } else {
            throw error
        }
    }
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "all"
let model = arguments.count > 2 ? arguments[2] : defaultModel

if mode != "utf8", model.isEmpty {
    print("Usage : karen-engine-cli [basic|utf8|rolling|reuse|cancel|cycles|edge|all] <modele.gguf>")
    print("        (ou définir KARENOS_MODEL)")
    exit(2)
}

do {
    switch mode {
    case "basic": try await testBasic(model: model)
    case "utf8": try await testUTF8()
    case "rolling": try await testRolling(model: model)
    case "reuse": try await testReuse(model: model)
    case "cancel": try await testCancel(model: model)
    case "cycles": try await testCycles(model: model)
    case "edge": try await testEdge(model: model)
    default:
        try await testUTF8()
        try await testBasic(model: model)
        try await testRolling(model: model)
        try await testReuse(model: model)
        try await testCancel(model: model)
        try await testCycles(model: model)
        try await testEdge(model: model)
    }
    print("\nOK")
} catch {
    print("\nÉCHEC : \(error)")
    exit(1)
}
