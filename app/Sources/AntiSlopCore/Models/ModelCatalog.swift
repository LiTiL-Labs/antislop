import Foundation

/// One model the connected runtime offers to this account, as the runtime
/// itself reports it (Claude Code's initialize handshake, `codex debug models`).
public struct ModelOption: Equatable, Sendable, Identifiable {
    /// The value passed back to the runtime (`--model` / `-m`). Claude Code's
    /// "default" entry means "pass no model flag".
    public let id: String
    public let displayName: String
    public let detail: String?
    /// The full model the runtime says an alias resolves to, when it says so.
    public let resolvedModel: String?
    /// Reasoning/effort levels this model accepts, in the runtime's order.
    public let reasoningLevels: [String]
    public let defaultReasoning: String?

    public init(id: String, displayName: String, detail: String? = nil, resolvedModel: String? = nil,
                reasoningLevels: [String] = [], defaultReasoning: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.resolvedModel = resolvedModel
        self.reasoningLevels = reasoningLevels
        self.defaultReasoning = defaultReasoning
    }

    /// Claude Code lists its own default as a model entry.
    public var isRuntimeDefault: Bool { id == "default" }
}

/// The writer's model and reasoning choice for one provider. nil means "let the
/// runtime use its own default" and sends no flag.
public struct ModelPreference: Equatable, Sendable {
    public var model: String?
    public var reasoning: String?

    public init(model: String? = nil, reasoning: String? = nil) {
        self.model = model
        self.reasoning = reasoning
    }

    public static let runtimeDefault = ModelPreference()

    /// Only well-formed values ever reach a runtime's argument list.
    public var isValid: Bool {
        (model.map(ModelIdentifier.isValidModel) ?? true) && (reasoning.map(ModelIdentifier.isValidLevel) ?? true)
    }
}

extension ModelPreference: Codable {
    enum CodingKeys: String, CodingKey { case model, reasoning }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNullable(model, forKey: .model)
        try c.encodeNullable(reasoning, forKey: .reasoning)
    }
}

public enum ModelIdentifier {
    /// Model ids and aliases as runtimes report them ("sonnet", "gpt-6.1-sol",
    /// "claude-opus-5[1m]"). Never starts with "-", so it can't be read as a flag.
    public static func isValidModel(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 120, s.first != "-" else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._:-[]/@".unicodeScalars.contains($0) }
    }

    public static func isValidLevel(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 32 && s.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || $0 == "_" || $0 == "-" }
            && s.first != "-"
    }
}

/// Parsers for the runtimes' own model listings. Entries with unusable ids are skipped.
public enum ModelCatalogParser {
    /// The `models` array of Claude Code's `initialize` control response.
    public static func claudeInitialize(stdout: String, requestID: String) -> [ModelOption]? {
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "control_response",
                  let response = event["response"] as? [String: Any],
                  response["request_id"] as? String == requestID else { continue }
            guard response["subtype"] as? String == "success",
                  let body = response["response"] as? [String: Any],
                  let models = body["models"] as? [[String: Any]] else { return nil }
            return models.compactMap { m in
                guard let id = m["value"] as? String, ModelIdentifier.isValidModel(id) else { return nil }
                let levels = (m["supportedEffortLevels"] as? [String] ?? []).filter(ModelIdentifier.isValidLevel)
                return ModelOption(id: id, displayName: m["displayName"] as? String ?? id,
                                   detail: m["description"] as? String, resolvedModel: m["resolvedModel"] as? String,
                                   reasoningLevels: levels, defaultReasoning: nil)
            }
        }
        return nil
    }

    static let delegatingLevels: Set<String> = ["ultra"]

    /// `codex debug models`: only models the catalog marks for listing.
    public static func codexCatalog(_ data: Data) -> [ModelOption]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return nil }
        let listed = models.filter { ($0["visibility"] as? String ?? "list") == "list" }
            .sorted { ($0["priority"] as? Int ?? .max) < ($1["priority"] as? Int ?? .max) }
        return listed.compactMap { m in
            guard let id = m["slug"] as? String, ModelIdentifier.isValidModel(id) else { return nil }
            // "ultra" means automatic task delegation (sub-agents), which Anti-slop's
            // isolation disables, so it is not offered.
            let levels = (m["supported_reasoning_levels"] as? [[String: Any]] ?? [])
                .compactMap { $0["effort"] as? String }
                .filter { ModelIdentifier.isValidLevel($0) && !delegatingLevels.contains($0) }
            let def = (m["default_reasoning_level"] as? String).flatMap { ModelIdentifier.isValidLevel($0) ? $0 : nil }
            return ModelOption(id: id, displayName: m["display_name"] as? String ?? id,
                               detail: m["description"] as? String, resolvedModel: nil,
                               reasoningLevels: levels, defaultReasoning: def)
        }
    }
}

/// Product presets, resolved only against models and effort levels the account offers.
public enum Intelligence: String, Codable, CaseIterable, Sendable {
    case roomTemp = "room_temp", average, smart, genius
    public var displayName: String {
        switch self {
        case .roomTemp: return "Room Temp"
        case .average: return "Average"
        case .smart: return "Smart"
        case .genius: return "Genius"
        }
    }

    public func resolve(in catalog: [ModelOption], provider: ProviderID) -> ModelPreference? {
        guard !catalog.isEmpty else { return nil }
        // Prefer the first (current) entry in each known family, never invent a model ID.
        let families: [String]
        switch (provider, self) {
        case (.claudeCode, .genius): families = ["opus", "sonnet", "haiku"]
        case (.claudeCode, .smart): families = ["sonnet", "opus", "haiku"]
        case (.claudeCode, .average): families = ["sonnet", "haiku", "opus"]
        case (.claudeCode, .roomTemp): families = ["haiku", "sonnet", "opus"]
        case (.codex, .genius): families = ["astra", "sol", "codex", "terra", "luna", "mini"]
        case (.codex, .smart): families = ["sol", "codex", "astra", "terra", "luna", "mini"]
        case (.codex, .average), (.codex, .roomTemp): families = ["luna", "mini", "terra", "sol", "codex", "astra"]
        }
        let explicit = catalog.filter { !$0.isRuntimeDefault }
        let chosen = families.lazy.compactMap { family in
            explicit.first { $0.id.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(Substring(family)) }
        }.first ?? catalog.first(where: \.isRuntimeDefault) ?? catalog[0]
        let preferredLevels: [String]
        switch self {
        case .roomTemp: preferredLevels = ["minimal", "low", "none", "medium", "high"]
        case .average: preferredLevels = ["medium", "low", "high", "minimal"]
        case .smart: preferredLevels = ["high", "medium", "low"]
        case .genius: preferredLevels = ["max", "xhigh", "high", "medium", "low"]
        }
        let allowed = chosen.reasoningLevels.filter { $0 != "ultra" && ModelIdentifier.isValidLevel($0) }
        let level = preferredLevels.first(where: allowed.contains)
            ?? chosen.defaultReasoning.flatMap { allowed.contains($0) ? $0 : nil }
        return ModelPreference(model: chosen.isRuntimeDefault ? nil : chosen.id, reasoning: level)
    }
}
