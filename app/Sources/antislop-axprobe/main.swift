#if os(macOS)
import AntiSlopMac
import Foundation

Task { @MainActor in
    let code = await AXProbe.run(CommandLine.arguments)
    exit(code)
}
dispatchMain()
#else
print("antislop-axprobe exercises macOS Accessibility and only runs on macOS.")
#endif
