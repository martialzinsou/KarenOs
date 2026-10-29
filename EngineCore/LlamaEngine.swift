// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — LlamaEngine.swift
//    Moteur d'inférence local · llama.cpp C API · Swift 6 strict
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : encapsuler llama_model / llama_context / llama_batch dans
//              un actor isolé, streamer les tokens vers le MainActor.
//  --------------------------------------------------------------------
//    Points clés :
//      · ressources C en RAII (classe non Sendable possédée par l'actor) ;
//      · tokenisation et batch préalloués, zéro malloc par token ;
//      · ingestion par chunks ≤ n_batch, logits uniquement sur le dernier ;
//      · KV cache roulant (seq_rm + seq_add), préfixe système conservé ;
//      · sampler llama.cpp (temp / top-k / top-p / min-p / dist) ;
//      · reconstruction UTF-8 incrémentale (emojis coupés entre tokens) ;
//      · annulation non isolée + abort_callback CPU.
//  ====================================================================

import CLlama
import Darwin
import Foundation

// MARK: - Configuration

/// Paramètres de chargement du modèle et du contexte.
public struct LlamaConfiguration: Sendable {
    public enum FlashAttention: Sendable {
        case automatic
        case disabled
        case enabled
    }

    /// Type de stockage du KV cache. `.q8_0` divise la VRAM par ~2 mais
    /// exige Flash Attention.
    public enum KVCacheType: Sendable {
        case f16
        case q8_0
        case q4_0
    }

    /// Chemin absolu du fichier GGUF.
    public var modelPath: String
    /// Taille de contexte (tokens). 0 = valeur du modèle.
    public var contextSize: Int
    /// Taille logique maximale d'un batch soumis à `llama_decode`.
    public var batchSize: Int
    /// Taille physique d'un micro-batch (mémoire de pic).
    public var microBatchSize: Int
    /// Couches sur GPU. -1 = toutes (llama.cpp b8967), 0 = CPU pur.
    public var gpuLayers: Int32
    /// Threads de génération. 0 = cœurs physiques (plafonné à 8).
    public var threads: Int32
    /// Threads d'ingestion du prompt. 0 = cœurs physiques (plafonné à 8).
    public var batchThreads: Int32
    public var useMmap: Bool
    public var useMlock: Bool
    public var flashAttention: FlashAttention
    public var kvCacheTypeK: KVCacheType
    public var kvCacheTypeV: KVCacheType
    /// Ajoute BOS/EOS par le vocabulaire au début du prompt tokenisé.
    public var addSpecialTokens: Bool
    /// Interprète les tokens spéciaux présents dans le prompt (ChatML…).
    public var parseSpecialTokens: Bool

    public init(
        modelPath: String,
        contextSize: Int = 8_192,
        batchSize: Int = 2_048,
        microBatchSize: Int = 512,
        gpuLayers: Int32 = -1,
        threads: Int32 = 0,
        batchThreads: Int32 = 0,
        useMmap: Bool = true,
        useMlock: Bool = false,
        flashAttention: FlashAttention = .automatic,
        kvCacheTypeK: KVCacheType = .f16,
        kvCacheTypeV: KVCacheType = .f16,
        addSpecialTokens: Bool = false,
        parseSpecialTokens: Bool = true
    ) {
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.batchSize = batchSize
        self.microBatchSize = microBatchSize
        self.gpuLayers = gpuLayers
        self.threads = threads
        self.batchThreads = batchThreads
        self.useMmap = useMmap
        self.useMlock = useMlock
        self.flashAttention = flashAttention
        self.kvCacheTypeK = kvCacheTypeK
        self.kvCacheTypeV = kvCacheTypeV
        self.addSpecialTokens = addSpecialTokens
        self.parseSpecialTokens = parseSpecialTokens
    }

    /// Profil de production CPU/BLAS, validé sur cette machine.
    ///
    /// - `gpuLayers = 0` : aucun offload, donc aucun repli implicite ;
    /// - threads = cœurs physiques : sur un CPU à hyperthreading, utiliser
    ///   les cœurs logiques coûte ~35–40 % de débit (mesuré sur Haswell
    ///   4C/8T : 25 tok/s à 8 threads contre 40 tok/s à 4) ;
    /// - Flash Attention automatique : b8967 l'active sur CPU et le débit
    ///   progresse de 5 à 10 % ;
    /// - KV en f16 : la quantification q8_0 divise l'empreinte mais coûte
    ///   ~20 % sur le prefill, sans gain mesurable en décodage ;
    /// - mmap activé, mlock désactivé : le cache de pages suffit pour un
    ///   modèle de quelques centaines de Mo à quelques Go.
    public static func cpuProduction(
        modelPath: String,
        contextSize: Int = 8_192
    ) -> LlamaConfiguration {
        LlamaConfiguration(
            modelPath: modelPath,
            contextSize: contextSize,
            gpuLayers: 0,
            threads: 0,
            batchThreads: 0,
            useMmap: true,
            useMlock: false,
            flashAttention: .automatic,
            kvCacheTypeK: .f16,
            kvCacheTypeV: .f16
        )
    }
}

/// Cœurs physiques, plafonnés à 8.
///
/// Sur un CPU Intel à hyperthreading, `activeProcessorCount` renvoie les
/// cœurs logiques. Les utiliser tous pour `llama_decode` provoque une
/// contention mémoire : sur un i7-4850HQ (4C/8T), le décodage passe de
/// ~40 tok/s à 4 threads à ~25 tok/s à 8. On s'aligne sur `hw.physicalcpu`.
private func karenPhysicalCoreCount() -> Int32 {
    var count: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
        return min(count, 8)
    }
    let logical = Int32(ProcessInfo.processInfo.activeProcessorCount)
    return max(1, min(logical / 2, 8))
}

/// Paramètres d'échantillonnage d'une requête.
public struct LlamaSamplingParameters: Sendable {
    /// 0 = greedy déterministe.
    public var temperature: Float
    public var topK: Int32
    public var topP: Float
    public var minP: Float
    /// `UInt32.max` = graine aléatoire à chaque requête.
    public var seed: UInt32
    public var maxTokens: Int

    public init(
        temperature: Float = 0.7,
        topK: Int32 = 40,
        topP: Float = 0.95,
        minP: Float = 0.05,
        seed: UInt32 = .max,
        maxTokens: Int = 512
    ) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.seed = seed
        self.maxTokens = maxTokens
    }
}

/// Mesures de la dernière génération.
public struct LlamaRunMetrics: Sendable {
    public var promptTokens: Int = 0
    public var generatedTokens: Int = 0
    /// Tokens du prompt déjà présents dans le KV cache (préfixe commun).
    public var reusedTokens: Int = 0
    /// Délai entre le début de la requête et le premier fragment restitué.
    public var timeToFirstToken: TimeInterval = 0
    /// Débit de génération, premier token exclu.
    public var tokensPerSecond: Double = 0
    /// Durée d'ingestion du prompt.
    public var promptEvaluation: TimeInterval = 0
    public var contextShiftCount: Int = 0
}

// MARK: - Erreurs

public enum LlamaEngineError: Error, LocalizedError, Sendable, Equatable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextCreationFailed(String)
    case unsupportedArchitecture
    case tokenizationFailed
    case promptTooLong(required: Int, available: Int)
    case emptyPrompt
    case decodeFailed(code: Int32)
    case noKVCacheSlot
    case samplerCreationFailed
    case cancelled
    case busy
    case engineNotLoaded

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Modèle introuvable : \(path)"
        case .modelLoadFailed(let message):
            return "Chargement du modèle impossible : \(message)"
        case .contextCreationFailed(let message):
            return "Création du contexte impossible : \(message)"
        case .unsupportedArchitecture:
            return "Les modèles encodeur-décodeur ne sont pas pris en charge par ce moteur."
        case .tokenizationFailed:
            return "La tokenisation du prompt a échoué."
        case .promptTooLong(let required, let available):
            return "Prompt trop long : \(required) tokens requis, \(available) disponibles."
        case .emptyPrompt:
            return "Le prompt ne contient aucun token."
        case .decodeFailed(let code):
            return "llama_decode a échoué (code \(code))."
        case .noKVCacheSlot:
            return "Plus aucun emplacement KV disponible : réduisez le contexte ou le batch."
        case .samplerCreationFailed:
            return "Création de la chaîne d'échantillonnage impossible."
        case .cancelled:
            return "Génération annulée."
        case .busy:
            return "Une génération est déjà en cours sur ce moteur."
        case .engineNotLoaded:
            return "Le moteur a été libéré."
        }
    }
}

// MARK: - Drapeau d'annulation partagé avec le C

/// Petit drapeau atomique (NSLock) lisible depuis le thread de calcul de
/// llama.cpp via `ggml_abort_callback`. Le jeton d'époque empêche une
/// annulation tardive de tuer la génération suivante.
final class AbortFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var aborted = false

    func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        aborted = false
        return epoch
    }

    func cancel(epoch target: UInt64) {
        lock.lock()
        if target == epoch { aborted = true }
        lock.unlock()
    }

    func isAborted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return aborted
    }
}

/// Callback C : ne capture rien, convertible en `@convention(c)`.
private func karenAbortCallback(_ data: UnsafeMutableRawPointer?) -> Bool {
    guard let data else { return false }
    return Unmanaged<AbortFlag>.fromOpaque(data).takeUnretainedValue().isAborted()
}

/// Annulation d'un flux : consultée par l'actor et par le callback C.
final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private let abort: AbortFlag
    private var cancelled = false
    private var epoch: UInt64?

    init(abort: AbortFlag) {
        self.abort = abort
    }

    /// À appeler au démarrage de la génération (thread de l'actor).
    func beginEpoch() {
        let newEpoch = abort.begin()
        lock.lock()
        epoch = newEpoch
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled {
            abort.cancel(epoch: newEpoch)
        }
    }

    /// Appelable depuis n'importe quel thread (onTermination, bouton Stop).
    func cancel() {
        lock.lock()
        cancelled = true
        let currentEpoch = epoch
        lock.unlock()
        if let currentEpoch {
            abort.cancel(epoch: currentEpoch)
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Relais non isolé vers le flux actif, pour `LlamaEngine.cancel()`.
final class CancelRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var box: CancelBox?

    func set(_ box: CancelBox) {
        lock.lock()
        self.box = box
        lock.unlock()
    }

    func clear(_ box: CancelBox) {
        lock.lock()
        if self.box === box { self.box = nil }
        lock.unlock()
    }

    func cancelCurrent() {
        lock.lock()
        let current = box
        lock.unlock()
        current?.cancel()
    }
}

// MARK: - Reconstruction UTF-8

/// Les tokens llama.cpp sont des fragments d'octets : un emoji peut être
/// réparti sur plusieurs tokens. On accumule les octets et on ne rend une
/// `String` que lorsqu'une séquence complète est disponible.
public struct UTF8Accumulator {
    private var pending: [UInt8] = []

    public init() {
        pending.reserveCapacity(8)
    }

    public mutating func append(_ bytes: UnsafeRawBufferPointer) -> String? {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return nil }
        pending.append(contentsOf: UnsafeRawBufferPointer(start: base, count: bytes.count))
        return drain(final: false)
    }

    public mutating func append(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        pending.append(contentsOf: bytes)
        return drain(final: false)
    }

    public mutating func flush() -> String? {
        drain(final: true)
    }

    private mutating func drain(final: Bool) -> String? {
        guard !pending.isEmpty else { return nil }

        var output = ""
        output.reserveCapacity(pending.count)
        var index = 0

        while index < pending.count {
            let lead = pending[index]
            let length: Int
            switch lead {
            case 0x00...0x7F: length = 1
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default:
                // Octet de continuation orphelin ou séquence interdite.
                output.append("\u{FFFD}")
                index += 1
                continue
            }

            if index + length > pending.count {
                if final {
                    output.append("\u{FFFD}")
                    index = pending.count
                }
                break
            }

            let slice = pending[index..<(index + length)]
            if let scalar = String(bytes: slice, encoding: .utf8) {
                output.append(scalar)
                index += length
            } else {
                output.append("\u{FFFD}")
                index += 1
            }
        }

        if index >= pending.count {
            pending.removeAll(keepingCapacity: true)
        } else if index > 0 {
            pending.removeFirst(index)
        }

        return output.isEmpty ? nil : output
    }
}

// MARK: - Ressources C (RAII)

/// Possède les objets C et les buffers préalloués.
///
/// Classe `@unchecked Sendable` : elle n'est jamais partagée entre deux
/// générations ; l'actor `LlamaEngine` en garantit l'accès exclusif. Le
/// `deinit` libère les objets même si `shutdown()` n'est pas appelé.
final class LlamaResources: @unchecked Sendable {
    let model: OpaquePointer
    let ctx: OpaquePointer
    let vocab: OpaquePointer
    let abortFlag: AbortFlag

    var batch: llama_batch
    let batchCapacity: Int
    let contextSize: Int
    let modelDescription: String

    /// Tokens du prompt en cours (capacité = contexte).
    let tokenBuffer: UnsafeMutableBufferPointer<llama_token>
    /// Miroir exact des tokens présents dans le KV cache.
    let cachedTokens: UnsafeMutableBufferPointer<llama_token>
    /// Buffer de conversion token → octets UTF-8.
    let pieceBuffer: UnsafeMutableBufferPointer<CChar>

    init(
        model: OpaquePointer,
        ctx: OpaquePointer,
        vocab: OpaquePointer,
        batch: llama_batch,
        batchCapacity: Int,
        contextSize: Int,
        modelDescription: String,
        abortFlag: AbortFlag
    ) {
        self.model = model
        self.ctx = ctx
        self.vocab = vocab
        self.batch = batch
        self.batchCapacity = batchCapacity
        self.contextSize = contextSize
        self.modelDescription = modelDescription
        self.abortFlag = abortFlag
        self.tokenBuffer = .allocate(capacity: contextSize + 1)
        self.cachedTokens = .allocate(capacity: contextSize + 1)
        self.pieceBuffer = .allocate(capacity: 256)
        self.pieceBuffer.initialize(repeating: 0)
    }

    deinit {
        // Le batch ne contient que des tableaux hôtes : le libérer avant
        // le contexte est sans conséquence, mais reste l'ordre naturel.
        llama_batch_free(batch)
        llama_free(ctx)
        llama_model_free(model)
        tokenBuffer.deallocate()
        cachedTokens.deallocate()
        pieceBuffer.deallocate()
    }

    // MARK: Tokenisation

    /// Tokenise sans écrire, pour connaître la taille exacte.
    func tokenCount(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> Int {
        let byteCount = Int32(text.utf8.count)
        let result = text.withCString { pointer in
            llama_tokenize(vocab, pointer, byteCount, nil, 0, addSpecial, parseSpecial)
        }
        if result == Int32.min { return Int.max }
        return result < 0 ? Int(-result) : Int(result)
    }

    /// Tokenise dans un buffer fourni. Retourne -1 si le buffer est trop petit.
    func tokenize(
        _ text: String,
        into buffer: UnsafeMutablePointer<llama_token>?,
        capacity: Int,
        addSpecial: Bool,
        parseSpecial: Bool
    ) -> Int {
        let byteCount = Int32(text.utf8.count)
        let result = text.withCString { pointer in
            llama_tokenize(vocab, pointer, byteCount, buffer, Int32(capacity), addSpecial, parseSpecial)
        }
        if result < 0 || result == Int32.min { return -1 }
        return Int(result)
    }

    /// Convertit un token en octets UTF-8 et les pousse dans l'accumulateur.
    func appendPiece(
        token: llama_token,
        to accumulator: inout UTF8Accumulator
    ) -> String? {
        guard let base = pieceBuffer.baseAddress else { return nil }
        let written = llama_token_to_piece(
            vocab, token, base, Int32(pieceBuffer.count), 0, false
        )
        guard written > 0 else { return nil }

        if Int(written) <= pieceBuffer.count {
            return accumulator.append(
                UnsafeRawBufferPointer(start: base, count: Int(written))
            )
        }

        // Token exceptionnellement long : chemin froid, une allocation.
        var temporary = [CChar](repeating: 0, count: Int(written))
        let again = temporary.withUnsafeMutableBufferPointer { slice in
            llama_token_to_piece(
                vocab, token, slice.baseAddress, Int32(slice.count), 0, false
            )
        }
        guard again > 0 else { return nil }
        return temporary.withUnsafeBytes { raw in
            accumulator.append(
                UnsafeRawBufferPointer(start: raw.baseAddress, count: Int(again))
            )
        }
    }

    // MARK: Fabrique

    static func make(configuration: LlamaConfiguration) throws -> LlamaResources {
        guard FileManager.default.fileExists(atPath: configuration.modelPath) else {
            throw LlamaEngineError.modelNotFound(configuration.modelPath)
        }

        initializeBackendOnce()

        let contextSize = max(256, configuration.contextSize)
        let batchCapacity = max(1, min(configuration.batchSize, contextSize))
        let microBatch = max(1, min(configuration.microBatchSize, batchCapacity))
        let threads = configuration.threads > 0
            ? configuration.threads
            : karenPhysicalCoreCount()
        let batchThreads = configuration.batchThreads > 0
            ? configuration.batchThreads
            : threads

        let abortFlag = AbortFlag()

        var model: OpaquePointer?
        var ctx: OpaquePointer?
        var batch = llama_batch()
        var finished = false

        defer {
            if !finished {
                if batch.token != nil { llama_batch_free(batch) }
                if let ctx { llama_free(ctx) }
                if let model { llama_model_free(model) }
            }
        }

        func loadModel(layers: Int32) -> OpaquePointer? {
            var params = llama_model_default_params()
            params.n_gpu_layers = layers
            params.use_mmap = configuration.useMmap
            params.use_mlock = configuration.useMlock
            return configuration.modelPath.withCString { path in
                llama_model_load_from_file(path, params)
            }
        }

        func makeContext(for model: OpaquePointer) -> OpaquePointer? {
            var params = llama_context_default_params()
            params.n_ctx = UInt32(contextSize)
            params.n_batch = UInt32(batchCapacity)
            params.n_ubatch = UInt32(microBatch)
            params.n_seq_max = 1
            params.n_threads = threads
            params.n_threads_batch = batchThreads
            params.flash_attn_type = flashAttentionType(configuration.flashAttention)
            params.type_k = ggmlType(configuration.kvCacheTypeK)
            params.type_v = ggmlType(configuration.kvCacheTypeV)
            params.offload_kqv = configuration.gpuLayers != 0
            params.kv_unified = true
            params.no_perf = true
            params.abort_callback = karenAbortCallback
            params.abort_callback_data = Unmanaged.passUnretained(abortFlag).toOpaque()
            return llama_init_from_model(model, params)
        }

        // 1. Chargement GPU demandé, repli CPU si le contexte ne peut pas
        //    être créé (VRAM insuffisante, backend absent).
        model = loadModel(layers: configuration.gpuLayers)
        if model == nil, configuration.gpuLayers != 0 {
            // Certains backends refusent le modèle avant même la création du
            // contexte : second essai CPU avant d'abandonner.
            model = loadModel(layers: 0)
        }
        guard let firstModel = model else {
            throw LlamaEngineError.modelLoadFailed(
                "llama_model_load_from_file a renvoyé NULL (fichier corrompu ou quantisation non prise en charge)."
            )
        }

        if !llama_model_has_encoder(firstModel) {
            ctx = makeContext(for: firstModel)
        }

        if ctx == nil, configuration.gpuLayers != 0 {
            llama_model_free(firstModel)
            model = loadModel(layers: 0)
            guard let cpuModel = model else {
                throw LlamaEngineError.modelLoadFailed("repli CPU impossible.")
            }
            if llama_model_has_encoder(cpuModel) {
                throw LlamaEngineError.unsupportedArchitecture
            }
            ctx = makeContext(for: cpuModel)
        }

        guard let finalModel = model else {
            throw LlamaEngineError.modelLoadFailed("modèle NULL après repli.")
        }
        if llama_model_has_encoder(finalModel) {
            throw LlamaEngineError.unsupportedArchitecture
        }
        guard let finalContext = ctx else {
            throw LlamaEngineError.contextCreationFailed(
                "llama_init_from_model a renvoyé NULL (mémoire ou backend insuffisant)."
            )
        }
        guard let vocab = llama_model_get_vocab(finalModel) else {
            // Le defer libère contexte et modèle une seule fois.
            throw LlamaEngineError.modelLoadFailed("vocabulaire indisponible.")
        }

        // 2. Batch réutilisé : une seule allocation pour toute la session.
        batch = llama_batch_init(Int32(batchCapacity), 0, 1)
        guard batch.token != nil, batch.pos != nil,
              batch.n_seq_id != nil, batch.seq_id != nil, batch.logits != nil else {
            throw LlamaEngineError.contextCreationFailed("allocation du batch impossible.")
        }

        // 3. Description lisible (une seule allocation).
        var description = [CChar](repeating: 0, count: 256)
        let descLength = description.withUnsafeMutableBufferPointer { slice in
            llama_model_desc(finalModel, slice.baseAddress, slice.count)
        }
        let modelDescription = descLength > 0
            ? String(cString: description)
            : "modèle local"

        let actualContext = Int(llama_n_ctx(finalContext))
        guard actualContext > 0 else {
            throw LlamaEngineError.contextCreationFailed("contexte de taille nulle.")
        }

        let resources = LlamaResources(
            model: finalModel,
            ctx: finalContext,
            vocab: vocab,
            batch: batch,
            batchCapacity: batchCapacity,
            contextSize: actualContext,
            modelDescription: modelDescription,
            abortFlag: abortFlag
        )
        finished = true
        return resources
    }

    private static func flashAttentionType(
        _ value: LlamaConfiguration.FlashAttention
    ) -> llama_flash_attn_type {
        switch value {
        case .automatic: return LLAMA_FLASH_ATTN_TYPE_AUTO
        case .disabled: return LLAMA_FLASH_ATTN_TYPE_DISABLED
        case .enabled: return LLAMA_FLASH_ATTN_TYPE_ENABLED
        }
    }

    private static func ggmlType(_ value: LlamaConfiguration.KVCacheType) -> ggml_type {
        switch value {
        case .f16: return GGML_TYPE_F16
        case .q8_0: return GGML_TYPE_Q8_0
        case .q4_0: return GGML_TYPE_Q4_0
        }
    }

    private static func initializeBackendOnce() {
        _ = BackendToken.once
    }

    private enum BackendToken {
        static let once: Void = llama_backend_init()
    }
}

// MARK: - Moteur

/// Moteur d'inférence sérialisé. Toutes les opérations llama.cpp ont lieu
/// sur l'exécuteur de l'actor ; l'interface consomme le flux sur le
/// MainActor sans jamais bloquer.
public actor LlamaEngine {
    private var resources: LlamaResources?
    private var activeBox: CancelBox?
    private let relay = CancelRelay()

    public let configuration: LlamaConfiguration

    /// Tokens actuellement dans le KV cache.
    public private(set) var tokensInContext: Int = 0
    /// Nombre de tokens générés lors de la dernière requête.
    public private(set) var lastMetrics = LlamaRunMetrics()

    private var cachedCount = 0
    private var keepTokens = 0
    private var contextShiftCount = 0

    private init(resources: LlamaResources, configuration: LlamaConfiguration) {
        self.resources = resources
        self.configuration = configuration
    }

    // MARK: Cycle de vie

    /// Charge le modèle hors du MainActor (I/O disque + mmap + init Metal).
    public static func load(configuration: LlamaConfiguration) async throws -> LlamaEngine {
        let config = configuration
        return try await Task.detached(priority: .userInitiated) {
            let resources = try LlamaResources.make(configuration: config)
            return LlamaEngine(resources: resources, configuration: config)
        }.value
    }

    /// Libère modèle, contexte et buffers. Appeler `cancel()` avant si une
    /// génération est en cours : l'acteur est sérialisé, donc cette méthode
    /// attend la fin de la boucle avant de rendre la mémoire.
    public func shutdown() {
        relay.cancelCurrent()
        resources = nil
        tokensInContext = 0
        cachedCount = 0
        keepTokens = 0
    }

    /// Annulation non isolée : utilisable depuis un bouton SwiftUI.
    public nonisolated func cancel() {
        relay.cancelCurrent()
    }

    /// Arrêt immédiat, sans bloquer l'appelant : annule la boucle puis libère
    /// les ressources dès que l'acteur redevient disponible.
    public nonisolated func shutdownAsynchronously() {
        relay.cancelCurrent()
        Task { await self.shutdown() }
    }

    public var isLoaded: Bool { resources != nil }
    public var isGenerating: Bool { activeBox != nil }
    public var contextSize: Int { resources?.contextSize ?? 0 }
    public var modelDescription: String { resources?.modelDescription ?? "" }

    /// Compte les tokens d'un texte (ex. préfixe système pour `keepTokens`).
    public func tokenCount(of text: String) -> Int {
        guard let resources else { return 0 }
        return resources.tokenCount(
            text,
            addSpecial: configuration.addSpecialTokens,
            parseSpecial: configuration.parseSpecialTokens
        )
    }

    /// Vide le KV cache et oublie l'historique.
    public func resetContext() {
        guard activeBox == nil, let resources else { return }
        karen_llama_kv_clear(resources.ctx, false)
        tokensInContext = 0
        cachedCount = 0
    }

    // MARK: Streaming

    /// Génère une réponse en streaming.
    ///
    /// - Parameters:
    ///   - prompt: prompt complet, déjà formaté avec le template de chat.
    ///   - keepTokens: nombre de tokens initiaux intouchables (préfixe
    ///     système). Calculable avec `tokenCount(of:)`.
    ///   - parameters: échantillonnage et budget de génération.
    /// - Returns: flux de fragments texte. Une seule génération à la fois.
    public func stream(
        prompt: String,
        keepTokens: Int = 0,
        parameters: LlamaSamplingParameters = LlamaSamplingParameters()
    ) -> AsyncThrowingStream<String, Error> {
        guard let resources else {
            return AsyncThrowingStream { $0.finish(throwing: LlamaEngineError.engineNotLoaded) }
        }
        guard activeBox == nil else {
            return AsyncThrowingStream { $0.finish(throwing: LlamaEngineError.busy) }
        }
        let box = CancelBox(abort: resources.abortFlag)

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: LlamaEngineError.engineNotLoaded)
                    return
                }
                do {
                    try await self.execute(
                        prompt: prompt,
                        keepTokens: keepTokens,
                        parameters: parameters,
                        box: box,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                box.cancel()
                task.cancel()
            }
        }
    }

    // MARK: Boucle de génération

    private func execute(
        prompt: String,
        keepTokens requestedKeep: Int,
        parameters: LlamaSamplingParameters,
        box: CancelBox,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let resources else { throw LlamaEngineError.engineNotLoaded }
        guard activeBox == nil else { throw LlamaEngineError.busy }

        activeBox = box
        relay.set(box)
        box.beginEpoch()
        defer {
            relay.clear(box)
            activeBox = nil
        }
        guard !box.isCancelled, !Task.isCancelled else {
            throw LlamaEngineError.cancelled
        }

        var metrics = LlamaRunMetrics()
        let shiftStart = contextShiftCount
        let started = DispatchTime.now().uptimeNanoseconds
        defer { lastMetrics = metrics }

        // 1. Tokenisation et ajustement au budget du contexte.
        let budget = promptBudget(resources: resources, parameters: parameters)
        let count = try tokenizePrompt(
            prompt,
            resources: resources,
            budget: budget,
            keep: max(0, requestedKeep)
        )
        metrics.promptTokens = count
        if count == 0 { throw LlamaEngineError.emptyPrompt }

        keepTokens = min(max(0, requestedKeep), count)

        // 2. Réutilisation du KV : plus long préfixe commun.
        let common = try prepareContext(
            count: count,
            keep: keepTokens,
            resources: resources
        )
        metrics.reusedTokens = common

        // 3. Ingestion par chunks, logits uniquement sur le dernier token.
        let promptStart = DispatchTime.now().uptimeNanoseconds
        var offset = common
        while offset < count {
            try checkCancellation(box)
            let chunk = min(resources.batchCapacity, count - offset)
            let base = resources.tokenBuffer.baseAddress! + offset
            try decodeChunk(
                resources: resources,
                tokens: base,
                count: chunk,
                finalLogits: offset + chunk == count
            )
            // Le KV et le miroir avancent ensemble.
            memcpy(
                resources.cachedTokens.baseAddress! + offset,
                base,
                chunk * MemoryLayout<llama_token>.stride
            )
            cachedCount += chunk
            offset += chunk
            await Task.yield()
        }
        metrics.promptEvaluation =
            Double(DispatchTime.now().uptimeNanoseconds - promptStart) / 1_000_000_000

        // 4. Échantillonnage et restitution.
        guard let sampler = makeSampler(parameters) else {
            throw LlamaEngineError.samplerCreationFailed
        }
        defer { llama_sampler_free(sampler) }

        var accumulator = UTF8Accumulator()
        var generated = 0
        var firstTokenTime: UInt64 = 0

        while generated < parameters.maxTokens {
            try checkCancellation(box)

            // Les logits courants proviennent du dernier decode (prompt ou
            // token précédent). On échantillonne avant tout décalage KV.
            let token = llama_sampler_sample(sampler, resources.ctx, -1)
            guard token >= 0 else { throw LlamaEngineError.decodeFailed(code: token) }

            if llama_vocab_is_eog(resources.vocab, token) {
                break
            }
            llama_sampler_accept(sampler, token)

            if let text = resources.appendPiece(token: token, to: &accumulator) {
                if firstTokenTime == 0 {
                    firstTokenTime = DispatchTime.now().uptimeNanoseconds
                }
                continuation.yield(text)
            }

            // Place pour le token suivant ; décale la moitié ancienne du KV
            // si le contexte est saturé.
            if tokensInContext + 1 > resources.contextSize - 1 {
                try shiftContext(resources: resources)
            }
            var sampled = token
            try decodeChunk(
                resources: resources,
                tokens: &sampled,
                count: 1,
                finalLogits: true
            )
            resources.cachedTokens[tokensInContext] = token
            cachedCount += 1
            generated += 1
            // Rend la main à l'acteur : arrêt, statistiques et refus d'une
            // seconde requête restent réactifs sans bloquer la boucle.
            if generated & 3 == 0 {
                await Task.yield()
            }
        }

        if let tail = accumulator.flush() {
            continuation.yield(tail)
        }

        let end = DispatchTime.now().uptimeNanoseconds
        metrics.generatedTokens = generated
        metrics.contextShiftCount = contextShiftCount - shiftStart
        if firstTokenTime > 0 {
            metrics.timeToFirstToken =
                Double(firstTokenTime - started) / 1_000_000_000
        } else {
            metrics.timeToFirstToken =
                Double(end - started) / 1_000_000_000
        }
        if generated > 1, firstTokenTime > 0 {
            let elapsed = Double(end - firstTokenTime) / 1_000_000_000
            metrics.tokensPerSecond = elapsed > 0 ? Double(generated - 1) / elapsed : 0
        }

        continuation.finish()
    }

    // MARK: Prompt

    /// Budget de tokens du prompt : laisse de la place à la génération.
    private func promptBudget(
        resources: LlamaResources,
        parameters: LlamaSamplingParameters
    ) -> Int {
        let hardLimit = resources.contextSize - 1
        let reserve = min(
            max(0, parameters.maxTokens),
            max(16, resources.contextSize / 4)
        )
        return min(hardLimit, resources.contextSize - reserve)
    }

    /// Tokenise le prompt et, s'il dépasse le budget, conserve le préfixe
    /// système + la fin la plus récente de l'historique.
    private func tokenizePrompt(
        _ prompt: String,
        resources: LlamaResources,
        budget: Int,
        keep: Int
    ) throws -> Int {
        let required = resources.tokenCount(
            prompt,
            addSpecial: configuration.addSpecialTokens,
            parseSpecial: configuration.parseSpecialTokens
        )
        guard required != Int.max else { throw LlamaEngineError.tokenizationFailed }

        if required <= budget {
            let written = resources.tokenize(
                prompt,
                into: resources.tokenBuffer.baseAddress,
                capacity: budget,
                addSpecial: configuration.addSpecialTokens,
                parseSpecial: configuration.parseSpecialTokens
            )
            guard written >= 0 else { throw LlamaEngineError.tokenizationFailed }
            return written
        }

        // Chemin froid : prompt plus long que le contexte. On tokenise en
        // entier (une allocation temporaire) puis on garde système + queue.
        guard keep + 8 <= budget else {
            throw LlamaEngineError.promptTooLong(
                required: required,
                available: max(0, budget - keep)
            )
        }
        let tail = budget - keep
        let temporary = UnsafeMutableBufferPointer<llama_token>
            .allocate(capacity: required)
        defer { temporary.deallocate() }

        let written = resources.tokenize(
            prompt,
            into: temporary.baseAddress,
            capacity: required,
            addSpecial: configuration.addSpecialTokens,
            parseSpecial: configuration.parseSpecialTokens
        )
        guard written >= tail else { throw LlamaEngineError.tokenizationFailed }

        let base = resources.tokenBuffer.baseAddress!
        memcpy(base, temporary.baseAddress!, keep * MemoryLayout<llama_token>.stride)
        memcpy(
            base + keep,
            temporary.baseAddress! + (written - tail),
            tail * MemoryLayout<llama_token>.stride
        )
        return keep + tail
    }

    /// Aligne le KV sur le prompt : réutilise le préfixe commun, retire le
    /// reste, ou repart de zéro si le préfixe système a changé.
    private func prepareContext(
        count: Int,
        keep: Int,
        resources: LlamaResources
    ) throws -> Int {
        var common = 0
        let limit = min(cachedCount, count)
        let cached = resources.cachedTokens.baseAddress!
        let incoming = resources.tokenBuffer.baseAddress!
        while common < limit, cached[common] == incoming[common] {
            common += 1
        }

        if common < keep {
            // Le préfixe système a changé : tout reconstruire.
            karen_llama_kv_clear(resources.ctx, false)
            tokensInContext = 0
            cachedCount = 0
            return 0
        }

        if common < cachedCount {
            // Si le prompt est un préfixe strict du KV, les logits en mémoire
            // correspondent au dernier token supprimé. On retire aussi le
            // dernier token conservé pour le re-décoder et régénérer des
            // logits valides à la bonne position.
            let removalStart = common == count ? max(0, count - 1) : common
            let removed = karen_llama_kv_seq_rm(
                resources.ctx, 0, llama_pos(removalStart), -1
            )
            if !removed {
                karen_llama_kv_clear(resources.ctx, false)
                tokensInContext = 0
                cachedCount = 0
                return 0
            }
            tokensInContext = removalStart
            cachedCount = removalStart
            return removalStart
        }
        tokensInContext = cachedCount
        return common
    }

    // MARK: Décodage

    /// Remplit le batch préalloué et appelle `llama_decode`.
    ///
    /// - `explicitPosition` : position du premier token ; `nil` = position
    ///   courante du KV (`tokensInContext`).
    /// - `finalLogits` : n'active la sortie de logits que sur le dernier
    ///   token du chunk, ce qui évite de calculer toute la matrice de sortie
    ///   pour les tokens intermédiaires.
    private func decodeChunk(
        resources: LlamaResources,
        tokens: UnsafePointer<llama_token>,
        count: Int,
        finalLogits: Bool,
        explicitPosition: Int? = nil
    ) throws {
        guard count > 0, count <= resources.batchCapacity else {
            throw LlamaEngineError.decodeFailed(code: -1)
        }

        var attempt = 0
        while true {
            let start = explicitPosition ?? tokensInContext
            guard start + count <= resources.contextSize else {
                throw LlamaEngineError.noKVCacheSlot
            }

            for index in 0..<count {
                resources.batch.token[index] = tokens[index]
                resources.batch.pos[index] = llama_pos(start + index)
                resources.batch.n_seq_id[index] = 1
                resources.batch.seq_id[index]![0] = 0
                resources.batch.logits[index] = (finalLogits && index == count - 1) ? 1 : 0
            }
            resources.batch.n_tokens = Int32(count)

            let code = llama_decode(resources.ctx, resources.batch)
            if code == 0 {
                tokensInContext = start + count
                return
            }
            if code == 2 {
                throw LlamaEngineError.cancelled
            }
            if code == 1 {
                // Un seul token et un KV fragmenté : on décale une fois.
                if count == 1, attempt == 0, explicitPosition == nil {
                    attempt += 1
                    try shiftContext(resources: resources)
                    continue
                }
                throw LlamaEngineError.noKVCacheSlot
            }
            throw LlamaEngineError.decodeFailed(code: code)
        }
    }

    /// Réduit le KV de moitié (hors préfixe système) puis décale les
    /// positions restantes : aucune copie VRAM, seules les métadonnées
    /// changent.
    private func shiftContext(resources: LlamaResources) throws {
        let keep = min(keepTokens, tokensInContext)
        guard tokensInContext - keep > 8 else {
            throw LlamaEngineError.noKVCacheSlot
        }

        let discard = max(1, (tokensInContext - keep) / 2)
        let start = keep
        let end = keep + discard

        let removed = karen_llama_kv_seq_rm(
            resources.ctx, 0, llama_pos(start), llama_pos(end)
        )
        if !removed {
            // Architecture à état récurrent : la suppression partielle est
            // refusée. On repart du préfixe système uniquement.
            karen_llama_kv_clear(resources.ctx, false)
            tokensInContext = 0
            cachedCount = 0
            contextShiftCount += 1
            throw LlamaEngineError.noKVCacheSlot
        }

        karen_llama_kv_seq_add(
            resources.ctx, 0, llama_pos(end), -1, llama_pos(-discard)
        )

        let remaining = tokensInContext - end
        if remaining > 0 {
            memmove(
                resources.cachedTokens.baseAddress! + start,
                resources.cachedTokens.baseAddress! + end,
                remaining * MemoryLayout<llama_token>.stride
            )
        }
        tokensInContext -= discard
        cachedCount -= discard
        contextShiftCount += 1
    }

    private func checkCancellation(_ box: CancelBox) throws {
        if box.isCancelled || Task.isCancelled {
            throw LlamaEngineError.cancelled
        }
    }

    // MARK: Sampler

    private func makeSampler(
        _ parameters: LlamaSamplingParameters
    ) -> UnsafeMutablePointer<llama_sampler>? {
        if parameters.temperature <= 0 {
            return llama_sampler_init_greedy()
        }

        var chainParams = llama_sampler_chain_default_params()
        chainParams.no_perf = true
        guard let chain = llama_sampler_chain_init(chainParams) else { return nil }

        if let topK = llama_sampler_init_top_k(parameters.topK) {
            llama_sampler_chain_add(chain, topK)
        }
        if let topP = llama_sampler_init_top_p(parameters.topP, 1) {
            llama_sampler_chain_add(chain, topP)
        }
        if let minP = llama_sampler_init_min_p(parameters.minP, 1) {
            llama_sampler_chain_add(chain, minP)
        }
        if let temperature = llama_sampler_init_temp(parameters.temperature) {
            llama_sampler_chain_add(chain, temperature)
        }

        let seed = parameters.seed == .max
            ? UInt32.random(in: 0..<UInt32.max)
            : parameters.seed
        if let distribution = llama_sampler_init_dist(seed) {
            llama_sampler_chain_add(chain, distribution)
        }
        return chain
    }
}
