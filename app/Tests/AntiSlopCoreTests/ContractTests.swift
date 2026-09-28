import XCTest
@testable import AntiSlopCore

final class ContractTests: XCTestCase {
    func testAllFixtureRequestsRoundTripAndMatchSchema() throws {
        let root = try Repo.json("fixtures/editorial-cases.json") as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 18)
        for c in cases {
            let raw = c["request"] as! [String: Any]
            let data = try JSONSerialization.data(withJSONObject: raw)
            let req = try JSONDecoder().decode(RewriteRequest.self, from: data)
            XCTAssertEqual(try SchemaCheck.validate(req, against: "schemas/rewrite-request.schema.json"), [], "\(c["id"]!)")
            // Re-encoding must keep explicit nulls and every required key.
            let again = try JSONSerialization.jsonObject(with: ContractJSON.encoder().encode(req)) as! [String: Any]
            XCTAssertEqual(Set(again.keys), Set(raw.keys))
            XCTAssertTrue(((again["nearby_context"] as! [String: Any])["before"] as! [String: Any]).keys.contains("text"))
            XCTAssertEqual(try JSONDecoder().decode(RewriteRequest.self, from: ContractJSON.encoder().encode(req)), req)
        }
    }

    func testSchemaExamplesDecodeAndReencodeValid() throws {
        let data = try Data(contentsOf: Repo.root.appendingPathComponent("schemas/rewrite-request.example.json"))
        let req = try JSONDecoder().decode(RewriteRequest.self, from: data)
        XCTAssertEqual(try SchemaCheck.validate(req, against: "schemas/rewrite-request.schema.json"), [])

        let sdata = try Data(contentsOf: Repo.root.appendingPathComponent("schemas/settings.example.json"))
        let settings = try JSONDecoder().decode(AppSettings.self, from: sdata)
        XCTAssertEqual(try SchemaCheck.validate(settings, against: "schemas/settings.schema.json"), [])
        XCTAssertNil(settings.shortcut)
    }

    func testSchemaCheckerRejectsKnownBadShapes() throws {
        // Guards the test helper itself, so passing schema tests mean something.
        let schema = try Repo.json("schemas/rewrite-response.schema.json") as! [String: Any]
        XCTAssertEqual(SchemaCheck.errors(["intent": "x", "rewritten_text": "y", "note": NSNull()], schema), [])
        XCTAssertFalse(SchemaCheck.errors(["intent": "x", "rewritten_text": "y"], schema).isEmpty)
        XCTAssertFalse(SchemaCheck.errors(["intent": "x", "rewritten_text": "", "note": NSNull()], schema).isEmpty)
        XCTAssertFalse(SchemaCheck.errors(["intent": "x", "rewritten_text": "y", "note": NSNull(), "score": 1], schema).isEmpty)
        XCTAssertFalse(SchemaCheck.errors(["intent": 3, "rewritten_text": "y", "note": NSNull()], schema).isEmpty)
    }

    func testContextSideInvariants() {
        XCTAssertTrue(ContextSide.unavailable.isConsistent)
        XCTAssertTrue(ContextSide.documentBoundary.isConsistent)
        XCTAssertTrue(ContextSide.excerpt("abc").isConsistent)
        // An empty "excerpt" is not evidence of a document edge.
        XCTAssertEqual(ContextSide.excerpt(""), .unavailable)
        XCTAssertFalse(ContextSide(uncheckedText: nil, boundary: .documentBoundary).isConsistent)
        XCTAssertFalse(ContextSide(uncheckedText: "x", boundary: .unavailable).isConsistent)
    }

    func testProfileRevisionPairing() {
        XCTAssertEqual(StyleProfileID.none.revision, "none")
        XCTAssertEqual(StyleProfileID.noAISlop.revision, "0.2")
        XCTAssertEqual(StyleProfileID.humanizer.revision, "0.2")
    }
}

final class ResponseValidatorTests: XCTestCase {
    let source = "It is worth noting that the pilot may reduce review time for some teams."

    func ok(_ json: String, source: String? = nil) -> RewriteResponse? {
        try? ResponseValidator.validate(jsonText: json, originalSelection: source ?? self.source).get()
    }

    func err(_ json: String, source: String? = nil) -> ResponseValidationError? {
        if case .failure(let e) = ResponseValidator.validate(jsonText: json, originalSelection: source ?? self.source) { return e }
        return nil
    }

    func testSchemaExampleIsAccepted() throws {
        let text = try Repo.text("schemas/rewrite-response.example.json")
        let r = try XCTUnwrap(ok(text))
        XCTAssertEqual(r.rewrittenText, "The pilot may reduce review time for some teams.")
        XCTAssertNil(r.note)
    }

    func testRequiredNullableNoteKey() {
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b"}"#), .missingProperty("note"))
        XCTAssertNotNil(ok(#"{"intent":"a","rewritten_text":"b","note":null}"#))
        XCTAssertEqual(ok(#"{"intent":"a","rewritten_text":"b","note":"n"}"#)?.note, "n")
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b","note":""}"#), .empty("note"))
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b","note":5}"#), .wrongType("note"))
    }

    func testRejectsExtraPropertiesAndWrappers() {
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b","note":null,"ai_score":0.9}"#), .unexpectedProperty("ai_score"))
        XCTAssertEqual(err("Here is the rewrite: {\"intent\":\"a\",\"rewritten_text\":\"b\",\"note\":null}"), .notSingleObject)
        XCTAssertEqual(err("```json\n{\"intent\":\"a\",\"rewritten_text\":\"b\",\"note\":null}\n```"), .notSingleObject)
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b","note":null} {"intent":"c"}"#), .notJSON)
        XCTAssertEqual(err(#"[{"intent":"a","rewritten_text":"b","note":null}]"#), .notSingleObject)
        XCTAssertEqual(err(""), .notJSON)
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"b","note":null"#), .notJSON)
    }

    func testEmptyAndBlankReplacements() {
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"","note":null}"#), .empty("rewritten_text"))
        XCTAssertEqual(err(#"{"intent":"a","rewritten_text":"  \n ","note":null}"#), .blankReplacementForSubstantiveSource)
        XCTAssertEqual(err(#"{"intent":"","rewritten_text":"b","note":null}"#), .empty("intent"))
    }

    func testUnchangedTextIsValidAndWhitespacePreserved() {
        let src = " may reduce "
        let r = ok(#"{"intent":"Context unclear","rewritten_text":" may reduce ","note":null}"#, source: src)
        XCTAssertEqual(r?.rewrittenText, src)
    }

    func testLimitsCountCodePoints() {
        let intent161 = String(repeating: "é", count: 161)
        XCTAssertEqual(err("{\"intent\":\"\(intent161)\",\"rewritten_text\":\"b\",\"note\":null}"), .tooLong("intent"))
        let intent160 = String(repeating: "é", count: 160)
        XCTAssertNotNil(ok("{\"intent\":\"\(intent160)\",\"rewritten_text\":\"b\",\"note\":null}"))
        let long = String(repeating: "a", count: Limits.responseText + 1)
        XCTAssertEqual(err("{\"intent\":\"i\",\"rewritten_text\":\"\(long)\",\"note\":null}"), .tooLong("rewritten_text"))
        let note241 = String(repeating: "n", count: 241)
        XCTAssertEqual(err("{\"intent\":\"i\",\"rewritten_text\":\"b\",\"note\":\"\(note241)\"}"), .tooLong("note"))
    }

    func testUnicodeSurvivesValidation() {
        let r = ok(#"{"intent":"Plan","rewritten_text":"Le pilote pourrait réduire les erreurs — 🚀","note":null}"#,
                   source: "Il est important de noter que le pilote pourrait réduire les erreurs.")
        XCTAssertEqual(r?.rewrittenText, "Le pilote pourrait réduire les erreurs — 🚀")
    }

    func testWireSchemaIsValidJSONWithSameRequiredKeys() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(ResponseValidator.providerWireSchema.utf8)) as! [String: Any]
        XCTAssertEqual(Set(obj["required"] as! [String]), ["intent", "rewritten_text", "note"])
        XCTAssertEqual(obj["additionalProperties"] as? Bool, false)
    }
}
