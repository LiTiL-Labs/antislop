import Foundation
@testable import AntiSlopCore

/// Repository paths, so tests check against the canonical package files.
enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AntiSlopCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // app
        .deletingLastPathComponent() // repository root

    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func json(_ path: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(path)))
    }
}

/// Minimal validator for the Draft 2020-12 keywords used by schemas/*.json:
/// type, const, enum, properties, required, additionalProperties, anyOf,
/// minLength, maxLength, items, maxItems, uniqueItems, minimum, maximum.
enum SchemaCheck {
    static func errors(_ value: Any, _ schema: [String: Any], path: String = "$") -> [String] {
        var out: [String] = []
        if let anyOf = schema["anyOf"] as? [[String: Any]] {
            if !anyOf.contains(where: { errors(value, $0, path: path).isEmpty }) { out.append("\(path): no anyOf branch matched") }
        }
        if let c = schema["const"] {
            if !equal(value, c) { out.append("\(path): const mismatch") }
        }
        if let e = schema["enum"] as? [Any] {
            if !e.contains(where: { equal(value, $0) }) { out.append("\(path): not in enum") }
        }
        if let t = schema["type"] as? String {
            if !typeMatches(value, t) { out.append("\(path): expected \(t)"); return out }
        }
        if let s = value as? String, !(value is NSNumber) {
            let n = s.unicodeScalars.count
            if let min = schema["minLength"] as? Int, n < min { out.append("\(path): shorter than \(min)") }
            if let max = schema["maxLength"] as? Int, n > max { out.append("\(path): longer than \(max)") }
        }
        if let num = value as? NSNumber, !isBool(value) {
            if let min = schema["minimum"] as? Double, num.doubleValue < min { out.append("\(path): below minimum") }
            if let max = schema["maximum"] as? Double, num.doubleValue > max { out.append("\(path): above maximum") }
        }
        if let obj = value as? [String: Any] {
            let props = schema["properties"] as? [String: Any] ?? [:]
            for r in schema["required"] as? [String] ?? [] where obj[r] == nil { out.append("\(path).\(r): required") }
            if (schema["additionalProperties"] as? Bool) == false {
                for k in obj.keys where props[k] == nil { out.append("\(path).\(k): additional property") }
            }
            for (k, v) in obj {
                if let sub = props[k] as? [String: Any] { out += errors(v, sub, path: "\(path).\(k)") }
            }
        }
        if let arr = value as? [Any] {
            if let max = schema["maxItems"] as? Int, arr.count > max { out.append("\(path): too many items") }
            if (schema["uniqueItems"] as? Bool) == true {
                for i in arr.indices { for j in arr.indices where j > i && equal(arr[i], arr[j]) { out.append("\(path): duplicate items") } }
            }
            if let items = schema["items"] as? [String: Any] {
                for (i, v) in arr.enumerated() { out += errors(v, items, path: "\(path)[\(i)]") }
            }
        }
        return out
    }

    static func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        #if canImport(Darwin)
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #else
        return v is Bool && String(cString: n.objCType) == "c"
        #endif
    }

    static func typeMatches(_ v: Any, _ t: String) -> Bool {
        switch t {
        case "object": return v is [String: Any]
        case "array": return v is [Any]
        case "string": return v is String
        case "null": return v is NSNull
        case "boolean": return isBool(v)
        case "integer":
            guard let n = v as? NSNumber, !isBool(v) else { return false }
            return n.doubleValue == n.doubleValue.rounded()
        case "number": return v is NSNumber && !isBool(v)
        default: return false
        }
    }

    static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if a is NSNull && b is NSNull { return true }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        return false
    }

    static func validate<T: Encodable>(_ value: T, against schemaPath: String) throws -> [String] {
        let data = try ContractJSON.encoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        let schema = try Repo.json(schemaPath) as! [String: Any]
        return errors(obj, schema)
    }
}

func capture(_ text: String, context: NearbyContext = .unavailable, hint: SourceHint = .none) -> CapturedText {
    CapturedText(selectedText: text, selectionKind: ContextBuilder.classify(text), context: context, sourceHint: hint)
}
