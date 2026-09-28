// The AppKit/Accessibility layer compiles only on macOS. On other platforms this
// module is empty so AntiSlopCore can be built and tested (e.g. in Linux CI).
#if !os(macOS)
public enum AntiSlopMacUnavailable {}
#endif
