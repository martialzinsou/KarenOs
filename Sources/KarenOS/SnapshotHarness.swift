// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — SnapshotHarness.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Capture de l'interface pour la vérification visuelle.
//    Dépend. : AppKit, Foundation
//  --------------------------------------------------------------------
//    Outil de développement, inactif par défaut : si la variable
//    d'environnement KARENOS_SNAPSHOT_DIR est définie, l'app parcourt les
//    quatre onglets puis les fenêtres À propos et Aide, enregistre un PNG
//    de chacune et quitte. Aucun effet en usage normal.
//  ====================================================================

import AppKit
import Foundation

enum SnapshotHarness {
    static func startIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["KARENOS_SNAPSHOT_DIR"],
              !raw.isEmpty else { return }
        let directory = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if ProcessInfo.processInfo.environment["KARENOS_SNAPSHOT_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            captureTabs(directory: directory, index: 0)
        }
    }

    private static func captureTabs(directory: URL, index: Int) {
        guard index < 4 else {
            captureMinimumSize(directory: directory)
            return
        }

        NotificationCenter.default.post(name: .karenSelectTab, object: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let window = mainWindow() {
                save(window: window, to: directory.appendingPathComponent("tab-\(index).png"))
            }
            captureTabs(directory: directory, index: index + 1)
        }
    }

    /// Capture le chat à la taille minimale autorisée (1060 × 700).
    private static func captureMinimumSize(directory: URL) {
        guard ProcessInfo.processInfo.environment["KARENOS_SNAPSHOT_MIN"] == "1",
              let window = mainWindow() else {
            showSupportWindow(directory: directory, about: true)
            return
        }
        let previous = window.frame
        NotificationCenter.default.post(name: .karenSelectTab, object: 0)
        window.setContentSize(NSSize(width: 1060, height: 700))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            save(window: window, to: directory.appendingPathComponent("min.png"))
            window.setFrame(previous, display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showSupportWindow(directory: directory, about: true)
            }
        }
    }

    private static func showSupportWindow(directory: URL, about: Bool) {
        NotificationCenter.default.post(name: about ? .karenShowAbout : .karenShowHelp, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let name = about ? "about" : "help"
            // Depuis le portage Big Sur, À propos et Aide sont des feuilles
            // rattachées à la fenêtre principale (macOS 11 n'a pas
            // `Window(id:)`), plus des fenêtres indépendantes.
            if let sheet = mainWindow()?.attachedSheet {
                save(window: sheet, to: directory.appendingPathComponent("\(name).png"))
            } else {
                print("[snapshot] feuille introuvable : \(name)")
                listWindows()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let sheet = mainWindow()?.attachedSheet {
                    sheet.sheetParent?.endSheet(sheet)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if about {
                        showSupportWindow(directory: directory, about: false)
                    } else {
                        print("[snapshot] terminé")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "KarenOS" && $0.isVisible && $0.contentView != nil }
            ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
    }

    private static func listWindows() {
        for window in NSApp.windows {
            print("[snapshot] window « \(window.title) » visible=\(window.isVisible) frame=\(window.frame) class=\(type(of: window))")
        }
    }

    private static func save(window: NSWindow, to url: URL) {
        let layerImage = layerImage(window: window)
        let windowImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
        print("[snapshot] \(url.lastPathComponent) layer=\(layerImage.map { "\($0.width)x\($0.height)" } ?? "nil") window=\(windowImage.map { "\($0.width)x\($0.height)" } ?? "nil")")

        let chosen = [layerImage, windowImage].compactMap { $0 }.first { !isBlank($0) }
        guard let image = chosen else {
            print("[snapshot] échec de rendu : \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("[snapshot] échec d'encodage : \(url.lastPathComponent)")
            return
        }
        do {
            try data.write(to: url)
            print("[snapshot] écrit \(url.path) \(Int(image.width))x\(Int(image.height))")
        } catch {
            print("[snapshot] erreur d'écriture : \(error)")
        }
    }

    /// Rendu direct du layer de contenu, indépendant de la capture d'écran.
    private static func layerImage(window: NSWindow) -> CGImage? {
        guard let view = window.contentView, let layer = view.layer else { return nil }
        view.layoutSubtreeIfNeeded()
        let scale = window.backingScaleFactor
        let width = max(1, Int(view.bounds.width * scale))
        let height = max(1, Int(view.bounds.height * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: view.bounds.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        return context.makeImage()
    }

    /// Détecte une capture uniforme (fenêtre non composée).
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let providerData = image.dataProvider?.data else { return true }
        let bytes = [UInt8](providerData as Data)
        guard bytes.count > 64 else { return true }
        let stride = max(4, bytes.count / 4096)
        var minValue = 255
        var maxValue = 0
        var index = 0
        while index < bytes.count {
            let value = Int(bytes[index])
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
            index += stride
        }
        return maxValue - minValue < 6
    }
}
