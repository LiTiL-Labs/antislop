#if os(macOS)
import AntiSlopCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let notice = model.notice {
                    Text(notice).font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                shortcutSection
                Divider()
                connectionSection
                Divider()
                styleSection
                Divider()
                guideSection
                Divider()
                instructionsSection
                if !model.accessibilityTrusted {
                    Divider()
                    accessSection
                }
                footer
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .frame(width: 540)
        .frame(minHeight: 520, idealHeight: 820)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Keyboard shortcuts

    var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Keyboard shortcuts")
            shortcutRow(.rewrite, button: "Assign anti-slop key",
                        help: "Rewrites the selected text. Press it again in the panel to apply.")
            shortcutRow(.detect, button: "Assign slop-detection key",
                        help: "Points out slop in the selected text without changing it.")
            Text("Choose any key, a combination, or a modifier key on its own, such as Right ⌥.")
                .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
        }
    }

    func shortcutRow(_ action: HotKeyAction, button: String, help: String) -> some View {
        let current = model.binding(for: action)
        let isError = model.shortcutIsError[action] ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(current?.displayLabel ?? "Not set")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .frame(minWidth: 110)
                    .frame(height: 38)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.statusFill))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                    .accessibilityLabel("Current \(action.name): \(current?.displayLabel ?? "not set")")
                if model.recording == action {
                    Text(model.recorderHint ?? SettingsModel.idleHint)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 38)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.action, lineWidth: 1.5))
                    Button("Cancel") { model.cancelRecording() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button(action: { model.beginRecording(action) }) {
                        Text(button)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 38)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if current != nil {
                        Button("Remove") { model.removeShortcut(action) }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
            Text(help)
                .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
            if let msg = model.shortcutMessage[action] {
                Label(msg, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12.5))
                    .foregroundColor(isError ? Theme.warning : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.shortcutWarnings[action] ?? [], id: \.self) { w in
                Label(w, systemImage: "info.circle")
                    .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: AI connection

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("AI connection")
            SegmentedChoice(options: ProviderID.allCases.map { ($0, $0.displayName) },
                            selection: Binding(get: { model.draft.providerID }, set: {
                                model.providerChosenByUser = true
                                model.draft.providerID = $0
                            }))
            let provider = model.draft.providerID
            let state = model.state(for: provider)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(provider.accountLabel).font(.system(size: 15)).foregroundColor(Theme.primaryText)
                    Spacer()
                    ReadinessBadge(state: state)
                    Button("Manage") { model.manageExpanded.toggle() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("Manage \(provider.displayName) connection")
                }
                if model.manageExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if let detail = state.detail {
                            Text(detail).font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isUnavailable(state) {
                            Text(installHelp(provider)).font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            if showsSignIn(state) {
                                Button("Sign in with \(provider.displayName)…") { model.onSignIn(provider) }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            Button("Check again") { model.onCheck(provider) }
                                .buttonStyle(QuietButtonStyle())
                                .disabled(state == .checking)
                        }
                        Text("Sign-in happens in \(provider.displayName)'s own tool. Anti-slop never sees your password or tokens, and never switches to the other connection.")
                            .font(.system(size: 11.5)).foregroundColor(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            modelSection
            Text("Your selected text and a little nearby context are sent to the AI connection you choose.")
                .font(.system(size: 11.5)).foregroundColor(Theme.secondaryText)
        }
    }

    /// Model and reasoning level, from the list the connected runtime reports.
    var modelSection: some View {
        let provider = model.draft.providerID
        return VStack(alignment: .leading, spacing: 8) {
            switch model.catalogs[provider] {
            case .loaded(let models)?:
                modelPickers(models)
            case .failed(let why)?:
                HStack(alignment: .top) {
                    Text("Couldn't load \(provider.displayName)'s models: \(why) Anti-slop uses its default model.")
                        .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Try again") { model.onLoadModels(provider) }.buttonStyle(QuietButtonStyle())
                }
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Loading \(provider.displayName)'s models…").font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                }
            }
        }
        .onAppear { model.loadModelsIfNeeded(provider) }
        .onChange(of: provider) { model.loadModelsIfNeeded($0) }
    }

    @ViewBuilder
    func modelPickers(_ models: [ModelOption]) -> some View {
        let choices = model.modelChoices(models)
        let pref = model.preference
        let runtimeDefault = models.first(where: \.isRuntimeDefault)
        let levels = model.reasoningLevels(models)
        let selected = pref.model.flatMap { id in choices.first { $0.id == id } } ?? runtimeDefault
        PickerRow(title: "Model") {
            Picker("Model", selection: Binding(get: { pref.model ?? "" },
                                               set: { model.selectModel($0.isEmpty ? nil : $0, catalog: models) })) {
                Text(runtimeDefault?.displayName ?? "Default").tag("")
                ForEach(choices) { m in Text(m.displayName).tag(m.id) }
            }
        }
        PickerRow(title: "Reasoning") {
            Picker("Reasoning", selection: Binding(get: { pref.reasoning ?? "" },
                                                   set: { model.selectReasoning($0.isEmpty ? nil : $0) })) {
                Text(defaultReasoningLabel(pref.model.flatMap { id in models.first { $0.id == id } })).tag("")
                ForEach(levels, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .disabled(levels.isEmpty)
        }
        if let detail = selected?.detail {
            Text(detail).font(.system(size: 11.5)).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if levels.isEmpty {
            Text("This model doesn't offer a reasoning setting.").font(.system(size: 11.5)).foregroundColor(Theme.secondaryText)
        }
    }

    func defaultReasoningLabel(_ m: ModelOption?) -> String {
        if let d = m?.defaultReasoning { return "Default (\(d))" }
        return "Default"
    }

    func isUnavailable(_ s: ReadinessState) -> Bool {
        if case .unavailable = s { return true }
        return false
    }

    func showsSignIn(_ s: ReadinessState) -> Bool {
        switch s {
        case .signInNeeded, .constrained, .installed, .error: return true
        default: return false
        }
    }

    func installHelp(_ p: ProviderID) -> String {
        switch p {
        case .claudeCode: return "Install Claude Code (see claude.com/claude-code), sign in with your Claude account, then choose Check again."
        case .codex: return "Install Codex (for example with Homebrew: brew install codex), sign in with ChatGPT, then choose Check again."
        }
    }

    // MARK: Style

    var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Style guidance")
            SegmentedChoice(options: StyleProfileID.allCases.sorted { order($0) < order($1) }.map { ($0, $0.displayName) },
                            selection: Binding(get: { model.draft.styleProfileID }, set: { model.draft.styleProfileID = $0 }))
            Text(model.draft.styleProfileID.helperText)
                .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
            ToggleRow(title: "Simplify wording", help: "Prefer familiar words when precision stays the same.",
                      isOn: Binding(get: { model.draft.writingPreferences.simplifyWording },
                                    set: { model.draft.writingPreferences.simplifyWording = $0 }))
            ToggleRow(title: "Keep my tone", help: "Keep your register, rhythm and humor.",
                      isOn: Binding(get: { model.draft.writingPreferences.keepMyTone },
                                    set: { model.draft.writingPreferences.keepMyTone = $0 }))
            DisclosureGroup(isExpanded: $model.moreOptions) {
                ToggleRow(title: "Avoid em dashes", help: "Use other punctuation where meaning stays intact.",
                          isOn: Binding(get: { model.draft.writingPreferences.avoidEmDashes },
                                        set: { model.draft.writingPreferences.avoidEmDashes = $0 }))
                    .padding(.top, 6)
            } label: {
                Text("More writing options").font(.system(size: 13)).foregroundColor(Theme.secondaryText)
            }
        }
    }

    func order(_ p: StyleProfileID) -> Int {
        switch p {
        case .noAISlop: return 0
        case .humanizer: return 1
        case .none: return 2
        }
    }

    // MARK: Guide

    var guideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Style guide")
            HStack {
                let label = model.guideLabel.trimmingCharacters(in: .whitespaces)
                Text(label.isEmpty ? "None selected" : label)
                    .font(.system(size: 15)).foregroundColor(Theme.primaryText)
                Spacer()
                if model.guideExpanded || !label.isEmpty {
                    Button("Remove") { model.removeGuide() }.buttonStyle(QuietButtonStyle())
                }
                if !model.guideExpanded {
                    Button(label.isEmpty ? "Add guide" : "Edit") { model.addOrEditGuide() }.buttonStyle(QuietButtonStyle())
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            if model.guideExpanded {
                TextField("Guide name, e.g. Firm style guide", text: $model.guideLabel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Guide name")
                BoxedEditor(text: $model.guideText, placeholder: "Paste a short excerpt of the guide.",
                            limit: Limits.guideText, height: 110, label: "Guide excerpt")
            }
        }
    }

    // MARK: Custom instructions

    var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Custom writing instructions")
            BoxedEditor(text: Binding(get: { model.draft.customWriterInstructions },
                                      set: { model.draft.customWriterInstructions = $0 }),
                        placeholder: "How would you like your writing to sound?",
                        limit: Limits.customInstructions, height: 92, label: "Custom writing instructions")
        }
    }

    // MARK: OS access

    var accessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Mac access")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility access needed").font(.system(size: 14, weight: .medium))
                    Text("Lets Anti-slop read the text you select and replace it when you press Anti-slop. Nothing is read until you use your key.")
                        .font(.system(size: 12.5)).foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open Settings") { model.requestAccessibility() }.buttonStyle(QuietButtonStyle())
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12.5)).foregroundColor(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Acknowledgements") { model.onAcknowledgements() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Button("Done") { model.done() }
                    .buttonStyle(PrimaryButtonStyle(enabled: true))
                    .accessibilityHint("Saves your settings")
            }
        }
        .padding(.top, 6)
    }
}

struct PickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundColor(Theme.primaryText)
            Spacer()
            content.labelsHidden().pickerStyle(.menu).frame(maxWidth: 280)
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.primaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SegmentedChoice<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let selected = value == selection
                Button { selection = value } label: {
                    Text(options[i].1)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundColor(Theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.white : Color.clear)
                                .shadow(color: selected ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.statusFill))
    }
}

struct ToggleRow: View {
    let title: String
    let help: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundColor(Theme.primaryText)
                Text(help).font(.system(size: 11.5)).foregroundColor(Theme.secondaryText)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.action)
    }
}

struct ReadinessBadge: View {
    let state: ReadinessState
    var body: some View {
        HStack(spacing: 6) {
            if state == .checking {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
            } else {
                Circle().fill(color).frame(width: 9, height: 9)
            }
            Text(state.label).font(.system(size: 13)).foregroundColor(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(state.label)")
    }

    var color: Color {
        switch state {
        case .ready: return Theme.ready
        case .fixtureOnly, .installed: return Theme.warning.opacity(0.6)
        case .checking: return Theme.skeleton
        default: return Theme.warning
        }
    }
}

struct BoxedEditor: View {
    @Binding var text: String
    let placeholder: String
    let limit: Int
    let height: CGFloat
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .accessibilityLabel(label)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText.opacity(0.8))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            let count = text.unicodeScalars.count
            Text("\(count) / \(limit)")
                .font(.system(size: 11))
                .foregroundColor(count > limit ? Theme.warning : Theme.secondaryText)
        }
    }
}
#endif
