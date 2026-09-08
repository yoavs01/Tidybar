//
//  DebugSignals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Tidybar addition (2026-09-07): two Unix signals that let a headless
//  operator exercise and *see* the menu bar without screen access of their own.
//
//    kill -USR1 <pid>   photograph the top strip of the active menu bar display
//                       to ~/Library/Logs/Tidybar/snapshot-<timestamp>.png
//                       (uses the app's own Screen Recording grant)
//    kill -USR2 <pid>   toggle the hidden section, as a click on the icon would
//
//  Signals need no authorization prompt, unlike the tidybar:// URL scheme, and
//  they cannot be sent from another user account. Nothing here is reachable from
//  the UI.

import AppKit
import ScreenCaptureKit

@MainActor
enum DebugSignals {
    private static let diagLog = DiagLog(category: "DebugSignals")
    private static var sources: [DispatchSourceSignal] = []

    /// The strip photographed by SIGUSR1, in points from the top of the display:
    /// the menu bar plus enough room below it for the Tray.
    static let snapshotHeight: CGFloat = 140

    static func install(appState: AppState) {
        guard sources.isEmpty else { return }
        for (sig, name) in [(SIGUSR1, "USR1"), (SIGUSR2, "USR2")] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak appState] in
                guard let appState else { return }
                Task { @MainActor in
                    switch name {
                    case "USR1":
                        await snapshot(appState: appState)
                    default:
                        appState.menuBarManager.section(withName: .hidden)?.toggle()
                        diagLog.info("SIGUSR2: toggled the hidden section")
                    }
                }
            }
            source.resume()
            sources.append(source)
        }
        diagLog.info("Debug signals installed (USR1 snapshot, USR2 toggle hidden)")
    }

    private static func snapshot(appState: AppState) async {
        do {
            let content = try await ScreenCapture.getShareableContent()
            let activeID = Bridging.getActiveMenuBarDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == activeID }) ?? content.displays.first else {
                diagLog.error("SIGUSR1: no display to capture")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = NSScreen.screens.first(where: { $0.displayID == display.displayID })?.backingScaleFactor ?? 2
            config.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: snapshotHeight)
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(snapshotHeight * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Tidybar", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = dir.appendingPathComponent("snapshot-\(stamp).png")
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                diagLog.error("SIGUSR1: could not encode PNG")
                return
            }
            try png.write(to: url)
            // Also keep a stable name so a driver script does not have to guess.
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("snapshot-latest.png"))
            try png.write(to: dir.appendingPathComponent("snapshot-latest.png"))
            diagLog.info("SIGUSR1: wrote \(url.path) (\(image.width)x\(image.height), display \(display.displayID))")
        } catch {
            diagLog.error("SIGUSR1: snapshot failed: \(error)")
        }
    }
}
