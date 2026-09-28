import AntiSlopCore
import Foundation

// Developer tool: live provider readiness and the editorial fixture corpus,
// through exactly the adapter code the app uses. Fixture texts are synthetic,
// so their outputs may be stored as evidence; never point this at private text.

struct Options {
    var command = "help"
    var provider: ProviderID? = nil
    var fixtureProvider = false
    var profiles: [StyleProfileID] = StyleProfileID.allCases
    var cases: Set<String>? = nil
    var fixtures = "../fixtures/editorial-cases.json"
    var out: String? = nil
    var passEnv: [String] = []
    var claudePath: String? = nil
    var codexPath: String? = nil
    var model: String? = nil
    var timeout: TimeInterval = Limits.rewriteTimeout
    var jobs = 2
    var caseID: String? = nil
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    if let first = args.first, !first.hasPrefix("-") { o.command = first; args.removeFirst() }
    var i = 0
    func next() -> String {
        i += 1
        guard i < args.count else { fail("missing value for \(args[i - 1])") }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "--provider":
            let v = next()
            if v == "fixture" { o.fixtureProvider = true; o.provider = .claudeCode }
            else if let p = ProviderID(rawValue: v) { o.provider = p }
            else { fail("unknown provider \(v)") }
        case "--profiles": o.profiles = next().split(separator: ",").compactMap { StyleProfileID(rawValue: String($0)) }
        case "--cases": o.cases = Set(next().split(separator: ",").map(String.init))
        case "--case": o.caseID = next()
        case "--fixtures": o.fixtures = next()
        case "--out": o.out = next()
        case "--pass-env": o.passEnv.append(next())
        case "--claude-path": o.claudePath = next()
        case "--codex-path": o.codexPath = next()
        case "--model": o.model = next()
        case "--timeout": o.timeout = TimeInterval(next()) ?? o.timeout
        case "--jobs": o.jobs = max(1, Int(next()) ?? 2)
        default: fail("unknown option \(args[i])")
        }
        i += 1
    }
    return o
}

func fail(_ s: String) -> Never {
    FileHandle.standardError.write(Data("antislop-eval: \(s)\n".utf8))
    exit(2)
}

func makeProvider(_ o: Options) -> RewriteProvider {
    if o.fixtureProvider { return FixtureProvider(delay: 0) }
    switch o.provider {
    case .claudeCode?:
        return ClaudeCodeProvider(locator: ExecutableLocator(overridePath: o.claudePath),
                                  explicitPassthrough: o.passEnv, modelOverride: o.model)
    case .codex?:
        return CodexProvider(locator: ExecutableLocator(overridePath: o.codexPath), modelOverride: o.model)
    case nil:
        fail("--provider is required (claude-code, codex or fixture)")
    }
}

struct FixtureCase {
    let id: String
    let request: RewriteRequest
    let acceptable: String
    let mustPreserve: [String]
    let reviewRule: String
}

func loadCases(_ path: String) -> [FixtureCase] {
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = root["cases"] as? [[String: Any]] else { fail("cannot read fixtures at \(path)") }
    return cases.map { c in
        let reqData = try! JSONSerialization.data(withJSONObject: c["request"]!)
        let req = try! JSONDecoder().decode(RewriteRequest.self, from: reqData)
        return FixtureCase(id: c["id"] as! String, request: req,
                           acceptable: c["acceptable_example"] as! String,
                           mustPreserve: c["must_preserve"] as! [String],
                           reviewRule: c["review_rule"] as! String)
    }
}

struct CaseResult: Codable {
    let caseID: String
    let profile: String
    let status: String
    let durationMs: Int
    let intent: String?
    let rewrittenText: String?
    let note: String?
    let unchanged: Bool?
    let matchesAcceptableExample: Bool?
    let missingLiterals: [String]
    let failureClass: String?
    let model: String?
    let runtimeVersion: String?
    let reviewRule: String

    enum CodingKeys: String, CodingKey {
        case caseID = "case_id", profile, status, durationMs = "duration_ms", intent
        case rewrittenText = "rewritten_text", note, unchanged
        case matchesAcceptableExample = "matches_acceptable_example"
        case missingLiterals = "missing_literals", failureClass = "failure_class", model
        case runtimeVersion = "runtime_version", reviewRule = "review_rule"
    }
}

struct Report: Codable {
    let generatedAt: String
    let provider: String
    let readiness: String
    let promptVersion: String
    let host: String
    let results: [CaseResult]
    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at", provider, readiness, promptVersion = "prompt_version", host, results
    }
}

func readinessText(_ r: ReadinessState) -> String {
    [r.label, r.detail].compactMap { $0 }.joined(separator: ": ")
}

func runCase(_ c: FixtureCase, profile: StyleProfileID, provider: RewriteProvider, timeout: TimeInterval) async -> CaseResult {
    var req = c.request
    req.styleProfileID = profile
    req.profileRevision = profile.revision
    let started = Date()
    do {
        let composed = try PromptComposer.compose(request: req)
        let r = try await provider.rewrite(composed, timeout: timeout)
        let out = r.response.rewrittenText
        return CaseResult(caseID: c.id, profile: profile.rawValue, status: "ok",
                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                          intent: r.response.intent, rewrittenText: out, note: r.response.note,
                          unchanged: out == c.request.selectedText,
                          matchesAcceptableExample: out == c.acceptable,
                          missingLiterals: c.mustPreserve.filter { !out.contains($0) },
                          failureClass: nil, model: r.receipt.model, runtimeVersion: r.receipt.runtimeVersion,
                          reviewRule: c.reviewRule)
    } catch let f as ProviderFailure {
        return CaseResult(caseID: c.id, profile: profile.rawValue, status: "request_failed",
                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                          intent: nil, rewrittenText: nil, note: nil, unchanged: nil, matchesAcceptableExample: nil,
                          missingLiterals: [], failureClass: f.diagnosticClass, model: nil, runtimeVersion: nil,
                          reviewRule: c.reviewRule)
    } catch {
        return CaseResult(caseID: c.id, profile: profile.rawValue, status: "composition_failed", durationMs: 0,
                          intent: nil, rewrittenText: nil, note: nil, unchanged: nil, matchesAcceptableExample: nil,
                          missingLiterals: [], failureClass: "\(error)", model: nil, runtimeVersion: nil,
                          reviewRule: c.reviewRule)
    }
}

let options = parse()

switch options.command {
case "readiness":
    let p = makeProvider(options)
    let r = await p.checkReadiness()
    print("\(options.fixtureProvider ? "fixture" : p.id.rawValue): \(readinessText(r))")
    exit(r.isReady || r == .fixtureOnly ? 0 : 1)

case "compose":
    let cases = loadCases(options.fixtures)
    guard let id = options.caseID, let c = cases.first(where: { $0.id == id }) else { fail("--case <id> required") }
    var req = c.request
    let profile = options.profiles.first ?? .noAISlop
    req.styleProfileID = profile
    req.profileRevision = profile.revision
    let composed = try PromptComposer.compose(request: req)
    print("=== instructions (system/developer role) ===\n\(composed.instructions)\n")
    print("=== data message (stdin) ===\n\(composed.dataMessage)")

case "corpus":
    let provider = makeProvider(options)
    let readiness = await provider.checkReadiness()
    let label = options.fixtureProvider ? "fixture" : provider.id.rawValue
    print("\(label) readiness: \(readinessText(readiness))")
    guard readiness.isReady || readiness == .fixtureOnly else {
        fail("provider is not ready; not running the corpus (a failed readiness check is not an editorial result)")
    }
    var cases = loadCases(options.fixtures)
    if let only = options.cases { cases = cases.filter { only.contains($0.id) } }
    let jobs = cases.flatMap { c in options.profiles.map { (c, $0) } }
    var results: [CaseResult] = []
    var index = 0
    while index < jobs.count {
        let batch = jobs[index..<min(index + options.jobs, jobs.count)]
        let batchResults = await withTaskGroup(of: CaseResult.self) { group in
            for (c, profile) in batch {
                group.addTask { await runCase(c, profile: profile, provider: provider, timeout: options.timeout) }
            }
            var out: [CaseResult] = []
            for await r in group { out.append(r) }
            return out
        }
        for r in batchResults.sorted(by: { ($0.caseID, $0.profile) < ($1.caseID, $1.profile) }) {
            let flag = r.status != "ok" ? "FAILED \(r.failureClass ?? "")"
                : r.missingLiterals.isEmpty ? "ok" : "REVIEW missing \(r.missingLiterals)"
            let ms = String(r.durationMs)
            print(r.caseID.padding(toLength: 24, withPad: " ", startingAt: 0)
                  + r.profile.padding(toLength: 12, withPad: " ", startingAt: 0)
                  + String(repeating: " ", count: max(0, 7 - ms.count)) + ms + "ms  " + flag)
        }
        results += batchResults
        index += options.jobs
    }
    let order = Dictionary(uniqueKeysWithValues: cases.enumerated().map { ($1.id, $0) })
    results.sort { (order[$0.caseID] ?? 0, $0.profile) < (order[$1.caseID] ?? 0, $1.profile) }
    #if os(macOS)
    let host = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    #else
    let host = "Linux \(ProcessInfo.processInfo.operatingSystemVersionString)"
    #endif
    let report = Report(generatedAt: ISO8601DateFormatter().string(from: Date()), provider: label,
                        readiness: readinessText(readiness), promptVersion: ContractVersion.prompt,
                        host: host, results: results)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try enc.encode(report)
    if let out = options.out {
        try data.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
    let ok = results.filter { $0.status == "ok" }.count
    print("\(ok)/\(results.count) requests returned a validated proposal")

default:
    print("""
    usage:
      antislop-eval readiness --provider claude-code|codex|fixture [--pass-env NAME]
      antislop-eval corpus --provider claude-code|codex|fixture [--profiles no-ai-slop,humanizer,none]
                           [--cases id,...] [--fixtures path] [--out report.json] [--jobs N] [--model M]
      antislop-eval compose --case <id> [--profiles <profile>]
    --pass-env forwards one named variable (never API keys) for headless test environments.
    """)
}
