//
//  DisplaySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct DisplaySettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    @Bindable var displaySettings: DisplaySettingsManager

    /// Per-display draft of the spacing slider, keyed by display UUID.
    /// Until the user clicks Apply, dragging the slider only updates this
    /// dictionary, it does not touch the saved configuration or trigger
    /// any relaunches.
    @State private var draftSpacing: [String: CGFloat] = [:]
    /// Pending spacing apply held while the confirmation alert is shown.
    /// Set by requestSpacingApply when a prompt is required; the alert binds
    /// to its non-nil state. Nil when no alert is showing.
    @State private var pendingSpacingApply: PendingSpacingApply?
    @State private var errorMessage: String?
    @State private var showingError = false

    /// A spacing apply request awaiting user confirmation.
    private struct PendingSpacingApply: Equatable {
        let displayID: String
        let displayName: String
        let offset: Double
        let isActiveDisplay: Bool
        let activeProfileID: UUID?
        let activeProfileName: String?
    }

    var body: some View {
        IceForm {
            IceSection("Tray") {
                globalSection()
            }
            if let display = spacingDisplay {
                IceSection("Menu bar item spacing") {
                    spacingRow(for: display)
                }
            }
            IceSection {
                confirmSpacingRelaunchControls
            }
        }
        .alert(
            String(localized: "Apply spacing change?"),
            isPresented: Binding(
                get: { pendingSpacingApply != nil },
                set: {
                    if !$0 {
                        pendingSpacingApply = nil
                    }
                }
            ),
            presenting: pendingSpacingApply,
            actions: { pending in spacingConfirmationButtons(for: pending) },
            message: { pending in Text(spacingConfirmationMessage(for: pending)) }
        )
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    /// The display whose row hosts the spacing slider. Tidybar keeps one
    /// configuration for every display, so this only decides which display
    /// name the confirmation mentions: the one with the active menu bar,
    /// else the first connected one.
    private var spacingDisplay: DisplaySettingsManager.DisplayInfo? {
        let displays = displaySettings.connectedDisplays()
        if let active = displaySettings.activeMenuBarDisplayUUID,
           let match = displays.first(where: { $0.id == active }) {
            return match
        }
        return displays.first ?? displaySettings.allDisplays().first
    }

    @ViewBuilder
    private var confirmSpacingRelaunchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Confirm before relaunching apps", isOn: $displaySettings.confirmSpacingRelaunch)
                .annotation("Before a display change or spacing edit relaunches your menu bar apps, Tidybar asks you to confirm. Turn this off to apply spacing changes and relaunch apps without confirmation.")

            SettingsWarningPill(
                title: "Apps may relaunch",
                message: "Changing menu bar spacing for a display can relaunch apps with menu bar items. Unsaved input, progress, or transient app state may be lost."
            )
        }

        if !displaySettings.confirmSpacingRelaunch {
            IcePicker(
                "Without confirmation, save spacing to",
                selection: $displaySettings.unconfirmedSpacingProfileScope
            ) {
                Text("Active profile").tag(SpacingProfileSaveScope.activeProfile)
                Text("All profiles").tag(SpacingProfileSaveScope.allProfiles)
            }
            .annotation("When a profile is active, choose whether spacing changes save to just the active profile or to every profile.")
        }
    }




    @ViewBuilder
    private func spacingRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let savedOffset = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
        let draft = draftSpacing[display.id] ?? CGFloat(savedOffset)
        let canApply = draft != CGFloat(savedOffset)

        let sliderBinding = Binding<CGFloat>(
            get: { draftSpacing[display.id] ?? CGFloat(savedOffset) },
            set: { draftSpacing[display.id] = $0 }
        )

        let labelKey: LocalizedStringKey = switch draft {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(draft.formatted())
        }

        LabeledContent {
            IceSlider(
                labelKey,
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            )
        } label: {
            LabeledContent {
                Button("Apply") {
                    requestSpacingApply(for: display, offset: Double(draft))
                }
                .help(Text("Apply the spacing for this display"))
                .disabled(!canApply)

                Button {
                    requestSpacingApply(for: display, offset: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Reset to the default spacing"))
                .disabled(savedOffset == 0 && draft == 0)
            } label: {
                Text("Menu bar item spacing")
            }
        }
        .annotation(
            "Apply briefly relaunches apps with menu bar items so they pick up the new spacing. Setting takes effect when this display is the active menu bar display."
        )
        .onChange(of: savedOffset) { _, newValue in
            // Sync draft when the saved value changes externally
            // (profile load, URI scheme, etc.).
            draftSpacing[display.id] = CGFloat(newValue)
        }
    }

    // MARK: - Spacing Apply Confirmation

    /// Routes both the Apply button and the inline reset button through a
    /// single decision point. When no profile is active and the change is
    /// for a non-active display, applies immediately (matches prior
    /// behaviour). Otherwise stages a PendingSpacingApply so the .alert
    /// can ask the user to choose between updating the active profile,
    /// updating every profile, or cancelling.
    private func requestSpacingApply(
        for display: DisplaySettingsManager.DisplayInfo,
        offset: Double
    ) {
        let activeID = appState.profileManager.activeProfileID
        let isActiveDisplay = displaySettings.activeMenuBarDisplayUUID == display.id

        if activeID == nil, !isActiveDisplay {
            commitSpacing(displayID: display.id, offset: offset)
            return
        }

        // Confirmations disabled: apply directly, saving to the profile
        // target the user picked instead of staging the alert.
        if !displaySettings.confirmSpacingRelaunch {
            commitSpacingWithoutConfirmation(
                displayID: display.id,
                offset: offset,
                activeProfileID: activeID
            )
            return
        }

        let activeName = activeID.flatMap { id in
            appState.profileManager.profiles.first(where: { $0.id == id })?.name
        }
        pendingSpacingApply = PendingSpacingApply(
            displayID: display.id,
            displayName: display.name,
            offset: offset,
            isActiveDisplay: isActiveDisplay,
            activeProfileID: activeID,
            activeProfileName: activeName
        )
    }

    /// Writes the new spacing to displaySettings.configurations. The
    /// Combine sink in DisplaySettingsManager picks this up and drives the
    /// relaunch wave on the next main-queue dispatch, so the caller is
    /// expected to have already written the profile file when persisting
    /// to a profile is desired.
    private func commitSpacing(displayID: String, offset: Double) {
        draftSpacing[displayID] = CGFloat(offset)
        displaySettings.updateConfiguration(forDisplayUUID: displayID) { config in
            config.withItemSpacingOffset(offset)
        }
    }

    /// Commits the spacing and, when a profile is active, persists it to the
    /// profile target chosen by unconfirmedSpacingProfileScope. Used when
    /// confirmations are disabled; mirrors the spacingConfirmationButtons
    /// actions including the rollback on a failed profile save.
    private func commitSpacingWithoutConfirmation(
        displayID: String,
        offset: Double,
        activeProfileID: UUID?
    ) {
        let previousOffset = displaySettings.configuration(forUUID: displayID).itemSpacingOffset
        commitSpacing(displayID: displayID, offset: offset)
        guard let id = activeProfileID else { return }
        do {
            switch displaySettings.unconfirmedSpacingProfileScope {
            case .activeProfile:
                try appState.profileManager.updateProfile(
                    id: id,
                    scope: .configurationOnly,
                    appState: appState
                )
            case .allProfiles:
                try appState.profileManager.updateAllProfilesItemSpacingOffset(
                    displayUUID: displayID,
                    offset: offset
                )
            }
        } catch {
            commitSpacing(displayID: displayID, offset: previousOffset)
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    @ViewBuilder
    private func spacingConfirmationButtons(for pending: PendingSpacingApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                if let id = pending.activeProfileID {
                    // updateProfile(scope:.configurationOnly) captures live
                    // state, so the in-memory configuration must hold the new
                    // value before the save. Snapshot the previous offset so
                    // a save failure can roll the live state back instead of
                    // leaving the new spacing applied without a matching
                    // profile entry, which the next reapply would revert.
                    let previousOffset = displaySettings
                        .configuration(forUUID: pending.displayID)
                        .itemSpacingOffset
                    commitSpacing(displayID: pending.displayID, offset: pending.offset)
                    do {
                        try appState.profileManager.updateProfile(
                            id: id,
                            scope: .configurationOnly,
                            appState: appState
                        )
                    } catch {
                        commitSpacing(displayID: pending.displayID, offset: previousOffset)
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                } else {
                    commitSpacing(displayID: pending.displayID, offset: pending.offset)
                }
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                let previousOffset = displaySettings
                    .configuration(forUUID: pending.displayID)
                    .itemSpacingOffset
                commitSpacing(displayID: pending.displayID, offset: pending.offset)
                do {
                    try appState.profileManager.updateAllProfilesItemSpacingOffset(
                        displayUUID: pending.displayID,
                        offset: pending.offset
                    )
                } catch {
                    commitSpacing(displayID: pending.displayID, offset: previousOffset)
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                draftSpacing[pending.displayID] = CGFloat(
                    displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
                )
            }
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                commitSpacing(displayID: pending.displayID, offset: pending.offset)
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                draftSpacing[pending.displayID] = CGFloat(
                    displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
                )
            }
        }
    }

    private func spacingConfirmationMessage(for pending: PendingSpacingApply) -> String {
        let profileName = pending.activeProfileName ?? ""
        switch (pending.isActiveDisplay, pending.activeProfileID != nil) {
        case (true, true):
            return String(
                format: String(localized: "Applying this spacing change will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost. Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (false, true):
            return String(
                format: String(localized: "Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (true, false):
            return String(localized: "Applying this spacing change will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
        case (false, false):
            return ""
        }
    }

    // MARK: - Global Section

    /// The Tray controls. Tidybar keeps one configuration for every display,
    /// so edits here apply everywhere immediately.
    @ViewBuilder
    private func globalSection() -> some View {
        let useIceBar = Binding<Bool>(
            get: { displaySettings.globalConfiguration.useIceBar },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withUseIceBar($0) }
        )
        let useThawBarForAlwaysHidden = Binding<Bool>(
            get: { displaySettings.globalConfiguration.useThawBarForAlwaysHidden },
            set: {
                displaySettings.globalConfiguration = displaySettings.globalConfiguration
                    .withUseThawBarForAlwaysHidden($0)
            }
        )
        let location = Binding<IceBarLocation>(
            get: { displaySettings.globalConfiguration.iceBarLocation },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withIceBarLocation($0) }
        )
        let alwaysShowHiddenItems = Binding<Bool>(
            get: { displaySettings.globalConfiguration.alwaysShowHiddenItems },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withAlwaysShowHiddenItems($0) }
        )
        let layout = Binding<IceBarLayout>(
            get: { displaySettings.globalConfiguration.iceBarLayout },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withIceBarLayout($0) }
        )
        let gridColumns = Binding<Int>(
            get: { displaySettings.globalConfiguration.gridColumns },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withGridColumns($0) }
        )

        IceBarConfigurationControls(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useIceBar: useIceBar,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: .globalTemplate
        ) {
            Toggle(
                "Show at mouse pointer on hotkey",
                isOn: Binding(
                    get: { appState.settings.general.iceBarLocationOnHotkey },
                    set: { appState.settings.general.iceBarLocationOnHotkey = $0 }
                )
            )
            .annotation("Always show the Tray at the mouse pointer's location when it is shown using a hotkey.")
        }
    }









}

private struct IceBarConfigurationControls<ExtraControls: View>: View {
    enum Context {
        case display
        case globalTemplate
    }

    @Binding var alwaysShowHiddenItems: Bool
    @Binding var useIceBar: Bool
    @Binding var useThawBarForAlwaysHidden: Bool
    @Binding var location: IceBarLocation
    @Binding var layout: IceBarLayout
    @Binding var gridColumns: Int

    private let context: Context
    private let extraControls: () -> ExtraControls
    @State private var maxSliderLabelWidth: CGFloat = 0

    /// Whether anything opens in the Tidybar Bar, and so whether its appearance
    /// controls apply.
    private var showsThawBar: Bool {
        useIceBar || useThawBarForAlwaysHidden
    }

    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useIceBar: Binding<Bool>,
        useThawBarForAlwaysHidden: Binding<Bool>,
        location: Binding<IceBarLocation>,
        layout: Binding<IceBarLayout>,
        gridColumns: Binding<Int>,
        context: Context,
        @ViewBuilder extraControls: @escaping () -> ExtraControls
    ) {
        _alwaysShowHiddenItems = alwaysShowHiddenItems
        _useIceBar = useIceBar
        _useThawBarForAlwaysHidden = useThawBarForAlwaysHidden
        _location = location
        _layout = layout
        _gridColumns = gridColumns
        self.context = context
        self.extraControls = extraControls
    }

    var body: some View {
        Toggle("Always show hidden items", isOn: $alwaysShowHiddenItems)
            .disabled(useIceBar)
            .annotation {
                if useIceBar {
                    switch context {
                    case .display:
                        Text("Not available because the Tray is enabled.")
                    case .globalTemplate:
                        Text("Not available because the Tray is enabled.")
                    }
                } else {
                    switch context {
                    case .display:
                        Text("Always show hidden menu bar items in the menu bar.")
                    case .globalTemplate:
                        Text("Always show hidden menu bar items in the menu bar.")
                    }
                }
            }

        Toggle("Use the Tray", isOn: $useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")

        Toggle("Always-hidden items only", isOn: $useThawBarForAlwaysHidden)
            .disabled(useIceBar)
            .annotation {
                if useIceBar {
                    Text("Not available because every section already opens in the Tray.")
                } else {
                    Text("""
                    Show always-hidden menu bar items in the Tray, \
                    while hidden items keep expanding in the menu bar.
                    """)
                }
            }

        extraControls()

        if showsThawBar {
            IcePicker("Location", selection: $location) {
                ForEach(IceBarLocation.allCases) { location in
                    Text(location.localized).tag(location)
                }
            }
            .annotation { locationAnnotation }

            IcePicker("Arrangement", selection: $layout) {
                ForEach(IceBarLayout.allCases) { layout in
                    Text(layout.localized).tag(layout)
                }
            }
            .annotation { layoutAnnotation }

            if layout == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns) },
                    set: { gridColumns = Int($0) }
                )
                LabeledContent {
                    IceSlider(value: gridColumnsDouble, in: 2 ... 10, step: 1) {
                        Text(verbatim: "\(gridColumns)")
                    }
                } label: {
                    Text("Columns")
                        .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                        .onAppear {
                            // Clear any stale accumulated width before the
                            // label is (re)measured below.
                            maxSliderLabelWidth = 0
                        }
                        .onFrameChange { frame in
                            maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                        }
                }
                .annotation("Maximum number of items per row in the grid arrangement.")
            }
        }
    }

    @ViewBuilder
    private var locationAnnotation: some View {
        switch location {
        case .dynamic:
            Text("The Tray's location changes based on context.")
        case .mousePointer:
            Text("The Tray is centered below the mouse pointer.")
        case .iceIcon:
            Text("The Tray is centered below the \(Constants.displayName) icon.")
        case .leftAligned:
            Text("The Tray is aligned to the left edge of the display.")
        case .rightAligned:
            Text("The Tray is aligned to the right edge of the display.")
        }
    }

    @ViewBuilder
    private var layoutAnnotation: some View {
        switch layout {
        case .horizontal:
            Text("Items are arranged in a single horizontal row.")
        case .vertical:
            Text("Items are stacked vertically in a single column.")
        case .grid:
            Text("Items are arranged in a grid with multiple columns.")
        }
    }
}

private extension IceBarConfigurationControls where ExtraControls == EmptyView {
    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useIceBar: Binding<Bool>,
        useThawBarForAlwaysHidden: Binding<Bool>,
        location: Binding<IceBarLocation>,
        layout: Binding<IceBarLayout>,
        gridColumns: Binding<Int>,
        context: Context
    ) {
        self.init(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useIceBar: useIceBar,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: context
        ) {
            EmptyView()
        }
    }
}
