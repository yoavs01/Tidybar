//
//  MacOSCompatibilityWarning.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Tidybar: the alpha-update-channel offer went away with Sparkle. The alert
//  now says only what it knows and opens the repository.

import AppKit

enum MacOSCompatibilityWarning {
    /// The first macOS this build does not support.
    static nonisolated let firstUnsupportedMajorVersion = 27

    static nonisolated func shouldShow(for version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= firstUnsupportedMajorVersion
    }

    /// The alert an unsupported system is owed.
    nonisolated struct Prompt: Equatable {
        let title: String
        let message: String
        let confirmButtonTitle: String
    }

    /// The prompt for a system, or `nil` when the system is supported.
    static nonisolated func prompt(for version: OperatingSystemVersion) -> Prompt? {
        guard shouldShow(for: version) else {
            return nil
        }
        let release = version.majorVersion
        return Prompt(
            title: String(localized: "macOS \(release) Is Not Yet Supported"),
            message: String(
                localized: """
                This build of Tidybar was made for macOS 26 and has not been checked against macOS \(release). Menu bar management may not work until Tidybar is rebuilt from a macOS \(release)-ready base.
                """
            ),
            confirmButtonTitle: String(localized: "Open Repository")
        )
    }

    /// Warns about the running macOS and offers the repository.
    @MainActor
    static func showIfNeeded() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard let prompt = prompt(for: version) else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.confirmButtonTitle)
        alert.addButton(withTitle: String(localized: "Continue"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        NSWorkspace.shared.open(Constants.repositoryURL)
    }
}
