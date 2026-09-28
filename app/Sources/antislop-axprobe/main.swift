#if os(macOS)
import AntiSlopMac
AXProbe.main()
#else
print("antislop-axprobe exercises macOS Accessibility and only runs on macOS.")
#endif
