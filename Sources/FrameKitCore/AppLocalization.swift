import Foundation

private final class LocalizationBundleToken: NSObject {}

public enum AppLocalization {
    // FrameKitCore is statically linked. The strings live in the executable's
    // bundle (the app in production, the test bundle during unit tests).
    // Let Bundle choose the language using macOS preferences and English fallback.
    public static let bundle = Bundle(for: LocalizationBundleToken.self)
}
