import Foundation

/// Starting bounds from ARCHITECTURE.md ("Proposed bounded defaults").
/// Character counts are Unicode code points, matching the JSON Schemas.
public enum Limits {
    public static let selectedText = 20_000
    public static let contextPerSide = 1_500
    public static let guideText = 8_000
    public static let guideLabel = 120
    public static let responseText = 40_000
    public static let intent = 160
    public static let note = 240
    public static let appName = 200
    public static let documentTitle = 500
    public static let contentTypeHint = 120

    /// Provider request deadline. Tune with measured runs (see app/IMPLEMENTATION_STATUS.md).
    public static let rewriteTimeout: TimeInterval = 90
    public static let readinessTimeout: TimeInterval = 60
    /// Hard caps on raw provider process output, well above any valid response.
    public static let providerStdoutBytes = 4 * 1024 * 1024
    public static let providerStderrBytes = 256 * 1024
    /// Full control values beyond this are not retained for drift checks.
    public static let retainedFullTextUTF16 = 4_000_000
}
