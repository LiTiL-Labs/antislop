#if os(macOS)
import AntiSlopMac
AntiSlopApplication.run()
#else
print("Anti-slop is a macOS app. Build and run it on macOS 13 or later (see app/README.md).")
#endif
