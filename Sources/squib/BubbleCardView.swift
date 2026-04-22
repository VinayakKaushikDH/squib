import SwiftUI
import SquibCore

// MARK: - Color(hex:)

private extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let n = UInt64(s, radix: 16) ?? 0
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8)  & 0xFF) / 255,
            blue:  Double(n & 0xFF)          / 255
        )
    }
}

// MARK: - Pure helpers

private func pillColor(for name: String) -> Color {
    switch name {
    case "Bash":         return Color(hex: "#d97757")
    case "Edit":         return Color(hex: "#5b8dd9")
    case "Write":        return Color(hex: "#8b7ec7")
    case "Read":         return Color(hex: "#5a9e6f")
    case "Glob", "Grep": return Color(hex: "#5a9eab")
    case "Agent":        return Color(hex: "#c47a9a")
    default:             return Color(hex: "#52525b")
    }
}

private func extractDetail(toolName: String, input: [String: Any]?) -> String {
    guard let inp = input else { return "" }
    switch toolName {
    case "Bash":                  return inp["command"]   as? String ?? ""
    case "Edit", "Write", "Read": return inp["file_path"] as? String ?? ""
    case "Glob", "Grep":          return inp["pattern"]   as? String ?? ""
    default:
        for v in inp.values { if let s = v as? String, !s.isEmpty { return s } }
        return (try? String(
            data: JSONSerialization.data(withJSONObject: inp, options: .prettyPrinted),
            encoding: .utf8)) ?? ""
    }
}

private func suggestionLabel(_ s: [String: Any]) -> String {
    switch s["type"] as? String {
    case "setMode":
        switch s["mode"] as? String {
        case "acceptEdits": return "Auto-accept edits"
        case "plan":        return "Switch to plan mode"
        default:            return s["mode"] as? String ?? "setMode"
        }
    case "addRules":
        let rule = (s["rules"] as? [[String: Any]])?.first ?? s
        let rc   = rule["ruleContent"] as? String ?? s["ruleContent"] as? String
        let tn   = rule["toolName"]    as? String ?? s["toolName"]    as? String ?? ""
        if let rc {
            if rc.contains("**") {
                let prefix  = rc.components(separatedBy: "**").first ?? ""
                let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
                let dir     = trimmed.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? trimmed
                return "Allow \(tn) in \(dir.isEmpty ? trimmed : dir)/"
            }
            let short = rc.count > 30 ? String(rc.prefix(29)) + "…" : rc
            return "Always allow `\(short)`"
        }
        return "Always allow"
    default:
        return "Always allow"
    }
}

/// Normalises a raw suggestion object into the format Claude Code expects in `updatedPermissions`.
/// Ported verbatim from BubbleMsgHandler.resolveSuggestion — kept here so BubbleCardView is self-contained.
private func resolveSuggestion(_ s: [String: Any]) -> [String: Any]? {
    guard let type = s["type"] as? String else { return nil }
    switch type {
    case "addRules":
        let rules: [[String: Any]]
        if let r = s["rules"] as? [[String: Any]], !r.isEmpty {
            rules = r
        } else {
            var rule: [String: Any] = [:]
            if let tn = s["toolName"]    as? String { rule["toolName"]    = tn }
            if let rc = s["ruleContent"] as? String { rule["ruleContent"] = rc }
            rules = [rule]
        }
        return [
            "type":        "addRules",
            "destination": s["destination"] as? String ?? "localSettings",
            "behavior":    s["behavior"]    as? String ?? "allow",
            "rules":       rules,
        ]
    case "setMode":
        guard let mode = s["mode"] as? String else { return nil }
        return [
            "type":        "setMode",
            "mode":        mode,
            "destination": s["destination"] as? String ?? "localSettings",
        ]
    default:
        return nil
    }
}

// MARK: - BubbleCardView

struct BubbleCardView: View {
    @ObservedObject var model: BubbleViewModel
    @State private var appeared    = false
    @State private var elicAnswers: [Int: Set<String>] = [:]

    private var request: PermissionRequest { model.request }

    private var parsedInput: [String: Any]? {
        guard let raw  = request.toolInput,
              let data = raw.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private var sessionTag: String? {
        var parts: [String] = []
        if let cwd = request.cwd, !cwd.isEmpty {
            let folder = URL(fileURLWithPath: cwd).lastPathComponent
            if !folder.isEmpty { parts.append(folder) }
        }
        if let sid = request.sessionId, !sid.isEmpty {
            parts.append("#" + String(sid.suffix(3)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Deduplicated suggestions with original index preserved for the decision payload.
    private var dedupedSuggestions: [(index: Int, raw: [String: Any], label: String)] {
        var seen = Set<String>()
        return request.suggestions.enumerated().compactMap { i, s in
            let label = suggestionLabel(s)
            guard seen.insert(label).inserted else { return nil }
            return (i, s, label)
        }
    }

    private var canSubmit: Bool {
        guard request.isElicitation else { return false }
        let questions = (parsedInput?["questions"] as? [[String: Any]]) ?? []
        guard !questions.isEmpty else { return false }
        return questions.indices.allSatisfy { !(elicAnswers[$0]?.isEmpty ?? true) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            modeContent
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
            model.onHeightMeasured?(h)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 40)
        .animation(.easeOut(duration: 0.28), value: appeared)
        .onAppear { appeared = true }
        .onChange(of: model.pendingKeyAction) { _, action in
            guard let action, !model.isDecided else {
                model.pendingKeyAction = nil; return
            }
            switch action {
            case .allow:        handleAllow()
            case .deny:         handleDeny()
            case .allowSession: handleAllowSession()
            }
            model.pendingKeyAction = nil
        }
    }

    // MARK: - Mode dispatch

    @ViewBuilder
    private var modeContent: some View {
        if request.isElicitation {
            elicitationContent
        } else if request.toolName == "ExitPlanMode" {
            planReviewContent
        } else {
            regularContent
        }
    }

    // MARK: - Regular permission

    @ViewBuilder
    private var regularContent: some View {
        HStack(spacing: 0) {
            Text("Permission Request")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            ToolPill(name: request.toolName)
        }

        if let tag = sessionTag {
            SessionTagLabel(text: tag)
        }

        let detail = extractDetail(toolName: request.toolName, input: parsedInput)
        if !detail.isEmpty {
            CommandBlock(text: detail)
        }

        HStack(spacing: 8) {
            BubbleActionButton("Deny",  hint: "⌘⇧N", role: .deny)  { handleDeny() }
            BubbleActionButton("Allow", hint: "⌘⇧Y", role: .allow) { handleAllow() }
        }
        .disabled(model.isDecided)

        if !dedupedSuggestions.isEmpty {
            VStack(spacing: 5) {
                BubbleSuggestionButton(label: "Allow Session", hint: "⌘⇧S") {
                    handleAllowSession()
                }
                ForEach(dedupedSuggestions, id: \.index) { item in
                    BubbleSuggestionButton(label: item.label) {
                        if let resolved = resolveSuggestion(item.raw) {
                            model.decide(.allowWithPermissions(updatedPermissions: [resolved]))
                        } else {
                            model.decide(.allow)
                        }
                    }
                }
            }
            .disabled(model.isDecided)
        }
    }

    // MARK: - Plan review

    @ViewBuilder
    private var planReviewContent: some View {
        Text("Plan Review")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

        if let tag = sessionTag {
            SessionTagLabel(text: tag)
        }

        let detail = extractDetail(toolName: request.toolName, input: parsedInput)
        if !detail.isEmpty {
            CommandBlock(text: detail)
        }

        BubbleActionButton("Approve", hint: "⌘⇧Y", role: .allow) { handleAllow() }
            .disabled(model.isDecided)

        BubbleSuggestionButton(label: "Go to Terminal") { handleDeny() }
            .disabled(model.isDecided)
    }

    // MARK: - Elicitation

    @ViewBuilder
    private var elicitationContent: some View {
        Text("Needs Input")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

        if let tag = sessionTag {
            SessionTagLabel(text: tag)
        }

        let questions = (parsedInput?["questions"] as? [[String: Any]]) ?? []
        if !questions.isEmpty {
            ElicitationForm(questions: questions, answers: $elicAnswers)
        }

        HStack(spacing: 8) {
            BubbleActionButton("Go to Terminal", hint: "⌘⇧N", role: .deny)  { handleDeny() }
            BubbleActionButton("Submit Answer",  hint: "⌘⇧Y", role: .allow) { handleSubmit() }
                .disabled(!canSubmit)
        }
        .disabled(model.isDecided)
    }

    // MARK: - Handlers

    private func handleAllow() {
        guard !model.isDecided else { return }
        model.decide(.allow)
    }

    private func handleDeny() {
        guard !model.isDecided else { return }
        model.decide(.deny)
    }

    private func handleAllowSession() {
        guard !model.isDecided else { return }
        if !dedupedSuggestions.isEmpty {
            model.trustSession()
        } else {
            model.decide(.allow)   // fallback: no suggestions → plain allow
        }
    }

    private func handleSubmit() {
        guard !model.isDecided, canSubmit else { return }
        let questions = (parsedInput?["questions"] as? [[String: Any]]) ?? []
        var collected: [String: String] = [:]
        for (i, q) in questions.enumerated() {
            guard let qText = q["question"] as? String else { continue }
            collected[qText] = elicAnswers[i]?.sorted().joined(separator: ", ") ?? ""
        }
        var base = parsedInput ?? [:]
        base["answers"] = collected
        model.decide(.allowWithUpdatedInput(updatedInput: base))
    }
}

// MARK: - ToolPill

private struct ToolPill: View {
    let name: String
    var body: some View {
        Text(name.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(pillColor(for: name), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - SessionTagLabel

private struct SessionTagLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .opacity(0.8)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

// MARK: - CommandBlock

private struct CommandBlock: View {
    let text: String
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxHeight: 100)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - BubbleActionButton

private enum BubbleButtonRole { case allow, deny }

private struct BubbleActionButton: View {
    let label:  String
    let hint:   String?
    let role:   BubbleButtonRole
    let action: () -> Void

    init(_ label: String, hint: String? = nil, role: BubbleButtonRole, action: @escaping () -> Void) {
        self.label  = label
        self.hint   = hint
        self.role   = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                if let hint {
                    Text("[\(hint)]")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.45)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(BubbleActionButtonStyle(role: role))
    }
}

private struct BubbleActionButtonStyle: ButtonStyle {
    let role: BubbleButtonRole
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                role == .allow
                    ? Color(hex: "#d97757")
                    : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(role == .allow ? Color.white : Color.primary)
            .overlay {
                if role == .deny {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                }
            }
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.78 : 1.0)
    }
}

// MARK: - BubbleSuggestionButton

private struct BubbleSuggestionButton: View {
    let label:  String
    let hint:   String?
    let action: () -> Void
    @State   private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    init(label: String, hint: String? = nil, action: @escaping () -> Void) {
        self.label  = label
        self.hint   = hint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let hint {
                        Text("[\(hint)]")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.45)
                    }
                }
                Spacer(minLength: 8)
                Text("→")
                    .font(.system(size: 11.5))
                    .opacity(isHovered && isEnabled ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0.03),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(isHovered && isEnabled ? 0.15 : 0.06), lineWidth: 1)
        }
        .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
        .onHover { isHovered = isEnabled ? $0 : false }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - ElicitationForm

private struct ElicitationForm: View {
    let questions: [[String: Any]]
    @Binding var answers: [Int: Set<String>]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(questions.indices, id: \.self) { i in
                QuestionCard(question: questions[i], index: i, answers: $answers)
            }
        }
    }
}

private struct QuestionCard: View {
    let question: [String: Any]
    let index:    Int
    @Binding var answers: [Int: Set<String>]

    private var isMultiSelect: Bool          { (question["multiSelect"] as? Bool) ?? false }
    private var options: [[String: Any]]     { (question["options"]     as? [[String: Any]]) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = question["header"] as? String {
                Text(header.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.85)
            }
            if let q = question["question"] as? String {
                Text(q)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(isMultiSelect ? "Multi-select, choose at least one" : "Choose one option")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .opacity(0.85)

            VStack(spacing: 5) {
                ForEach(options.indices, id: \.self) { j in
                    let optLabel  = options[j]["label"] as? String ?? ""
                    let isSelected = answers[index]?.contains(optLabel) ?? false
                    OptionRow(option: options[j], isMultiSelect: isMultiSelect, isSelected: isSelected) {
                        var current = answers[index] ?? []
                        if isMultiSelect {
                            if current.contains(optLabel) { current.remove(optLabel) }
                            else                          { current.insert(optLabel) }
                        } else {
                            current = [optLabel]
                        }
                        answers[index] = current
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OptionRow: View {
    let option:        [String: Any]
    let isMultiSelect: Bool
    let isSelected:    Bool
    let onTap:         () -> Void

    private var label:       String  { option["label"]       as? String ?? "" }
    private var description: String? { option["description"] as? String }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isMultiSelect
                      ? (isSelected ? "checkmark.square.fill" : "square")
                      : (isSelected ? "circle.fill"           : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color(hex: "#d97757") : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    if let desc = description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
