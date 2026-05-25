import AppKit
import Darwin
import QuickLookUI
import XCTest

final class QuickLookPreviewExtensionEntryTests: XCTestCase {
    func testQuickLookPreviewExtensionPrincipalClassLoads() throws {
        let previewController = try loadPreviewController(from: Self.quickLookPreviewAppexName)

        XCTAssertTrue(previewController is NSViewController)
    }

    func testQuickLookPreviewExtensionIncludesAppLocalizations() throws {
        let appexBundle = try loadQuickLookBundle(named: Self.quickLookPreviewAppexName)
        let englishLocalizationPath = try XCTUnwrap(appexBundle.path(forResource: "en",
                                                                     ofType: "lproj"))
        let englishLocalizationBundle = try XCTUnwrap(Bundle(path: englishLocalizationPath))

        let key = "app.archive.error.operationCancelled"
        XCTAssertEqual(englishLocalizationBundle.localizedString(forKey: key,
                                                                 value: nil,
                                                                 table: "App"),
                       "Operation was cancelled")
    }

    private func loadPreviewController(from appexName: String) throws -> QLPreviewingController {
        let appexBundle = try loadQuickLookBundle(named: appexName)
        let extensionInfo = try XCTUnwrap(appexBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        let principalClassName = try XCTUnwrap(extensionInfo["NSExtensionPrincipalClass"] as? String)
        let principalClass = try XCTUnwrap(NSClassFromString(principalClassName) as? NSObject.Type)
        let controller = principalClass.init()

        return try XCTUnwrap(controller as? QLPreviewingController)
    }

    private func loadQuickLookBundle(named appexName: String) throws -> Bundle {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let appexURL = plugInsURL.appendingPathComponent("\(appexName).appex", isDirectory: true)
        let appexBundle = try XCTUnwrap(Bundle(url: appexURL))

        if appexBundle.load() || loadDebugDylib(for: appexBundle, at: appexURL) {
            return appexBundle
        }

        let loadError = dlerror().map { String(cString: $0) } ?? "Unknown bundle load error."
        XCTFail("Failed to load \(appexName).appex: \(loadError)")
        return appexBundle
    }

    private func loadDebugDylib(for appexBundle: Bundle, at appexURL: URL) -> Bool {
        guard let executableName = appexBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else {
            return false
        }

        let debugDylibURL = appexURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("\(executableName).debug.dylib")
        guard FileManager.default.fileExists(atPath: debugDylibURL.path) else {
            return false
        }

        return dlopen(debugDylibURL.path, RTLD_NOW | RTLD_LOCAL) != nil
    }

    private static var quickLookPreviewAppexName: String {
        #if SHICHIZIP_ZS_VARIANT
            "ShichiZipZSArchivePreviewExtension"
        #else
            "ShichiZipArchivePreviewExtension"
        #endif
    }
}
