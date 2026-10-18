import Foundation
import XCTest
@testable import FrameKitCore

final class LocalizationTests: XCTestCase {
    private var host: Bundle { Bundle(for: Self.self) }

    private func languageBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(host.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    private func strings(_ table: String, language: String) throws -> [String: String] {
        let bundle = try languageBundle(language)
        let url = try XCTUnwrap(bundle.url(forResource: table, withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testCatalogsShipBothLanguagesWithMatchingInterpolationArguments() throws {
        let english = try strings("Localizable", language: "en")
        let chinese = try strings("Localizable", language: "zh-Hans")
        XCTAssertGreaterThan(english.count, 100)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let tokens = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:lld|llu|d|u|@)"#)
        func arguments(_ text: String) -> [String] {
            tokens.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }.sorted()
        }
        for key in english.keys {
            let en = try XCTUnwrap(english[key])
            let zh = try XCTUnwrap(chinese[key])
            XCTAssertFalse(en.isEmpty, key)
            XCTAssertFalse(zh.isEmpty, key)
            XCTAssertEqual(arguments(en), arguments(zh), key)
            XCTAssertNil(en.range(of: #"\p{Han}"#, options: .regularExpression), key)
        }
    }

    func testBundleMatchesSystemLanguagePreferencesAndEnglishFallback() {
        let available = host.localizations
        XCTAssertTrue(available.contains("en"))
        XCTAssertTrue(available.contains("zh-Hans"))
        XCTAssertEqual(host.developmentLocalization, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["en-GB"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["zh-Hans-CN"]).first, "zh-Hans")
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["fr", "en"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["fr", "zh-Hans"]).first, "zh-Hans")
        // Bundle falls back to the development language when no preferred language is supported.
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: ["ja"]).first, "en")
    }

    func testPermissionPurposeStringAndErrorAreTranslated() throws {
        let key = "NSScreenCaptureUsageDescription"
        let enPurpose = try XCTUnwrap(strings("InfoPlist", language: "en")[key])
        let zhPurpose = try XCTUnwrap(strings("InfoPlist", language: "zh-Hans")[key])
        XCTAssertTrue(enPurpose.contains("FrameKit"))
        XCTAssertTrue(zhPurpose.contains("FrameKit"))
        XCTAssertTrue(zhPurpose.contains("截取"))
        let english = try languageBundle("en")
        let chinese = try languageBundle("zh-Hans")
        XCTAssertEqual(String(localized: "Capture", bundle: english), "Capture")
        XCTAssertEqual(String(localized: "Capture", bundle: chinese), "截图")
        XCTAssertEqual(String(localized: "Enter valid screen coordinates.", bundle: chinese), "请输入有效的屏幕坐标。")
    }

    func testRuntimeInterpolationPreservesUserContentAndUnits() throws {
        let title = "NyxAstra — 测试 100% %@"
        let name = "Capture-截图.png"
        let zh = try languageBundle("zh-Hans")
        let en = try languageBundle("en")
        XCTAssertEqual(String(localized: "Selected “\(title)”. Resize it or capture directly.", bundle: zh),
                       "已选择「\(title)」，可调整尺寸或直接截图。")
        XCTAssertEqual(String(localized: "Saved \(name). Pixel dimensions and PNG format verified.", bundle: en),
                       "Saved \(name). Pixel dimensions and PNG format verified.")
        let dimensions = "2560 × 1600 px"
        XCTAssertEqual(String(localized: "Export \(dimensions)", bundle: zh), "导出 2560 × 1600 px")
        let code: Int32 = -25204
        let failure = String(localized: "Resize failed (AX \(String(code))). The window may have partially changed. Refresh to check its actual size before retrying.", bundle: zh)
        XCTAssertTrue(failure.hasPrefix("调整尺寸未完成（AX -25204）"))
    }

    func testCoreMessagesUseTheSameLanguageAsTheHostApp() throws {
        XCTAssertEqual(AppLocalization.bundle.bundleURL, host.bundleURL)
        let isChinese = host.preferredLocalizations.first == "zh-Hans"
        XCTAssertEqual(ResizeMode.fit.title, isChinese ? "等比留白" : "Fit")
        XCTAssertEqual(ResizeMode.fill.title, isChinese ? "居中裁剪" : "Fill")
        XCTAssertEqual(ResizeMode.stretch.title, isChinese ? "拉伸" : "Stretch")
        let unnamed = WindowDescriptor(id: 42, processID: 1, title: "", frame: .zero)
        XCTAssertEqual(unnamed.displayTitle, isChinese ? "未命名窗口 #42" : "Untitled Window #42")
        let largeID = WindowDescriptor(id: 12345, processID: 1, title: "", frame: .zero)
        XCTAssertEqual(largeID.displayTitle, isChinese ? "未命名窗口 #12345" : "Untitled Window #12345")
        let userTitle = WindowDescriptor(id: 43, processID: 1, title: "Capture", frame: .zero)
        XCTAssertEqual(userTitle.displayTitle, "Capture")
        XCTAssertThrowsError(try PixelSize(width: 0, height: 100)) { error in
            XCTAssertEqual(error.localizedDescription, isChinese
                           ? "图片宽高须为 1–16384 的整数像素。"
                           : "Image width and height must be whole pixels from 1 to 16384.")
        }
    }
}
