import XCTest
@testable import AntiSlopCore

final class IntelligenceTests: XCTestCase {
    func testCodexUsesOfferedCurrentFamiliesAndSupportedEffort() {
        let catalog = [
            ModelOption(id: "gpt-6.1-sol", displayName: "Workhorse", reasoningLevels: ["low", "medium", "high", "max"]),
            ModelOption(id: "gpt-6-astra", displayName: "Frontier", reasoningLevels: ["low", "high", "max", "ultra"]),
            ModelOption(id: "gpt-6-luna", displayName: "Fast", reasoningLevels: ["low", "medium"]),
            ModelOption(id: "gpt-5.6-sol", displayName: "Older")
        ]
        XCTAssertEqual(Intelligence.genius.resolve(in: catalog, provider: .codex), ModelPreference(model: "gpt-6-astra", reasoning: "max"))
        XCTAssertEqual(Intelligence.smart.resolve(in: catalog, provider: .codex), ModelPreference(model: "gpt-6.1-sol", reasoning: "high"))
        XCTAssertEqual(Intelligence.average.resolve(in: catalog, provider: .codex), ModelPreference(model: "gpt-6-luna", reasoning: "medium"))
        XCTAssertEqual(Intelligence.roomTemp.resolve(in: catalog, provider: .codex), ModelPreference(model: "gpt-6-luna", reasoning: "low"))
    }

    func testClaudeFourPresetsWithThreeFamiliesAndNoHaikuEffort() {
        let catalog = [ModelOption(id: "default", displayName: "Default"),
                       ModelOption(id: "opus[1m]", displayName: "Opus", reasoningLevels: ["low", "medium", "high", "max"]),
                       ModelOption(id: "sonnet", displayName: "Sonnet", reasoningLevels: ["low", "medium", "high"]),
                       ModelOption(id: "haiku", displayName: "Haiku")]
        XCTAssertEqual(Intelligence.genius.resolve(in: catalog, provider: .claudeCode), ModelPreference(model: "opus[1m]", reasoning: "max"))
        XCTAssertEqual(Intelligence.smart.resolve(in: catalog, provider: .claudeCode), ModelPreference(model: "sonnet", reasoning: "high"))
        XCTAssertEqual(Intelligence.average.resolve(in: catalog, provider: .claudeCode), ModelPreference(model: "sonnet", reasoning: "medium"))
        XCTAssertEqual(Intelligence.roomTemp.resolve(in: catalog, provider: .claudeCode), ModelPreference(model: "haiku"))
    }

    func testSparseAndUnknownCatalogsNeverInventOptionsOrDelegate() throws {
        for catalog in [[], [ModelOption(id: "new-model", displayName: "New", reasoningLevels: ["ultra"])],
                        [ModelOption(id: "default", displayName: "Default", reasoningLevels: ["low"])]] {
            for provider in ProviderID.allCases {
                for tier in Intelligence.allCases {
                    let pref = tier.resolve(in: catalog, provider: provider)
                    if catalog.isEmpty { XCTAssertNil(pref); continue }
                    let p = try XCTUnwrap(pref)
                    if let id = p.model { XCTAssertTrue(catalog.contains { $0.id == id }) }
                    XCTAssertNotEqual(p.reasoning, "ultra")
                    XCTAssertTrue(p.isValid)
                }
            }
        }
    }

    func testStartupAndPerProviderPresetsPersistAndKeepShortcuts() throws {
        var settings = AppSettings(providerID: .codex,
                                   shortcut: ShortcutBinding(keyCode: 61, displayLabel: "Right ⌥", modifiers: []),
                                   detectShortcut: ShortcutBinding(keyCode: 115, displayLabel: "Home", modifiers: []))
        settings.intelligence = [.codex: .genius, .claudeCode: .roomTemp]
        settings.launchAtLogin = false
        settings.writingPreferences.sentenceComplexity = .lawyer
        let encoded = try ContractJSON.encoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded), settings)
        XCTAssertEqual(try SchemaCheck.validate(settings, against: "schemas/settings.schema.json"), [])
    }
}
