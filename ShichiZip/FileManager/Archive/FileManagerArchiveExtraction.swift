import AppKit
import Darwin
import Foundation

struct FileManagerExtractionMaterialization: @unchecked Sendable {
    private static let visibleSidecarRecoveryAttempts = 16

    let finalURL: URL
    let sidecarURL: URL
    let publishRootURL: URL
    private let publishRootIsDirectory: Bool
    private let fileManager: FileManager

    static func prepareNewDestination(finalURL: URL,
                                      publishRootIsDirectory: Bool,
                                      fileManager: FileManager = .default) throws -> FileManagerExtractionMaterialization?
    {
        let standardizedFinalURL = finalURL.standardizedFileURL
        let parentURL = standardizedFinalURL.deletingLastPathComponent().standardizedFileURL
        try fileManager.createDirectory(at: parentURL,
                                        withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: standardizedFinalURL.path) else {
            return nil
        }

        let sidecarURL = try FileManagerTemporaryDirectorySupport.makeUniqueDirectory(
            in: parentURL,
            prefix: FileManagerTemporaryDirectorySupport.extractionSidecarPrefix,
            fileManager: fileManager,
            failureDescription: "A sidecar extraction directory could not be created.",
        )
        return FileManagerExtractionMaterialization(
            finalURL: standardizedFinalURL,
            sidecarURL: sidecarURL,
            publishRootURL: sidecarURL.appendingPathComponent(standardizedFinalURL.lastPathComponent,
                                                              isDirectory: publishRootIsDirectory),
            publishRootIsDirectory: publishRootIsDirectory,
            fileManager: fileManager,
        )
    }

    func createPublishRootDirectoryIfNeeded() throws {
        guard publishRootIsDirectory else { return }
        try fileManager.createDirectory(at: publishRootURL,
                                        withIntermediateDirectories: false)
    }

    @discardableResult
    func moveSidecarItemToPublishRoot(named itemName: String) throws -> Bool {
        let sourceURL = sidecarURL.appendingPathComponent(itemName, isDirectory: false)
            .standardizedFileURL
        guard sourceURL != publishRootURL else {
            return fileManager.fileExists(atPath: publishRootURL.path)
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return false
        }

        if fileManager.fileExists(atPath: publishRootURL.path) {
            try fileManager.removeItem(at: publishRootURL)
        }
        try Self.renameReplacingItem(at: sourceURL,
                                     with: publishRootURL)
        return true
    }

    func finish(operationError: Error?) throws {
        guard fileManager.fileExists(atPath: publishRootURL.path) else {
            if sidecarContainsItems() {
                let recoveryURL = revealSidecarIfPossible()
                throw recoveryError(operationError: operationError,
                                    recoveryURL: recoveryURL)
            }

            try? fileManager.removeItem(at: sidecarURL)
            if let operationError {
                throw operationError
            }
            throw noPublishedOutputError()
        }

        do {
            try publish()
            try? fileManager.removeItem(at: sidecarURL)
            noteFileSystemChanged([finalURL, finalURL.deletingLastPathComponent()])
        } catch {
            let recoveryURL = revealSidecarIfPossible()
            throw publishError(error,
                               operationError: operationError,
                               recoveryURL: recoveryURL)
        }

        if let operationError {
            throw operationError
        }
    }

    private func publish() throws {
        if isDirectory(at: publishRootURL) {
            try publishDirectory()
        } else {
            try Self.renameReplacingItem(at: publishRootURL,
                                         with: finalURL)
        }
    }

    private func publishDirectory() throws {
        if fileManager.fileExists(atPath: finalURL.path) {
            if renameSwap(publishRootURL, finalURL) {
                try fileManager.removeItem(at: publishRootURL)
                return
            }
            try fileManager.removeItem(at: finalURL)
        }

        try Self.renameReplacingItem(at: publishRootURL,
                                     with: finalURL)
    }

    private func renameSwap(_ firstURL: URL, _ secondURL: URL) -> Bool {
        let result = firstURL.path.withCString { firstPath in
            secondURL.path.withCString { secondPath in
                renamex_np(firstPath, secondPath, UInt32(RENAME_SWAP))
            }
        }
        return result == 0
    }

    private static func renameReplacingItem(at sourceURL: URL,
                                            with destinationURL: URL) throws
    {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            let errorCode = errno
            throw NSError(domain: NSPOSIXErrorDomain,
                          code: Int(errorCode),
                          userInfo: [
                              NSFilePathErrorKey: destinationURL.path,
                              NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain,
                                                            code: Int(errorCode)),
                          ])
        }
    }

    private func revealSidecarIfPossible() -> URL {
        let parentURL = sidecarURL.deletingLastPathComponent()
        let visibleBaseName = sidecarURL.lastPathComponent.hasPrefix(".")
            ? String(sidecarURL.lastPathComponent.dropFirst())
            : sidecarURL.lastPathComponent

        for attempt in 0 ..< Self.visibleSidecarRecoveryAttempts {
            let visibleName = attempt == 0 ? visibleBaseName : "\(visibleBaseName)-\(attempt + 1)"
            let visibleURL = parentURL.appendingPathComponent(visibleName,
                                                              isDirectory: true)
            guard !fileManager.fileExists(atPath: visibleURL.path) else {
                continue
            }

            do {
                try fileManager.moveItem(at: sidecarURL,
                                         to: visibleURL)
                noteFileSystemChanged([visibleURL, parentURL])
                return visibleURL.standardizedFileURL
            } catch {
                continue
            }
        }

        return sidecarURL
    }

    private func sidecarContainsItems() -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: sidecarURL.path) else {
            return false
        }
        return !contents.isEmpty
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path,
                                      isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func noPublishedOutputError() -> NSError {
        NSError(domain: NSCocoaErrorDomain,
                code: NSFileNoSuchFileError,
                userInfo: [
                    NSFilePathErrorKey: publishRootURL.path,
                    NSLocalizedDescriptionKey: "The extraction did not produce an item to publish.",
                ])
    }

    private func recoveryError(operationError: Error?,
                               recoveryURL: URL) -> NSError
    {
        var userInfo: [String: Any] = [
            NSFilePathErrorKey: recoveryURL.path,
            NSLocalizedDescriptionKey: "The extracted item could not be published.",
            NSLocalizedFailureReasonErrorKey: "Partial output was kept at \(recoveryURL.path).",
        ]
        if let operationError {
            userInfo[NSUnderlyingErrorKey] = operationError
        }
        return NSError(domain: NSCocoaErrorDomain,
                       code: NSFileWriteUnknownError,
                       userInfo: userInfo)
    }

    private func publishError(_ publishError: Error,
                              operationError: Error?,
                              recoveryURL: URL) -> NSError
    {
        var userInfo: [String: Any] = [
            NSFilePathErrorKey: finalURL.path,
            NSLocalizedDescriptionKey: "The extracted item could not be published.",
            NSLocalizedFailureReasonErrorKey: "Partial output was kept at \(recoveryURL.path).",
            NSUnderlyingErrorKey: publishError,
        ]
        if let operationError {
            userInfo["ShichiZipExtractionError"] = operationError
        }
        return NSError(domain: NSCocoaErrorDomain,
                       code: NSFileWriteUnknownError,
                       userInfo: userInfo)
    }

    private func noteFileSystemChanged(_ urls: [URL]) {
        let paths = urls.map(\.path)
        DispatchQueue.main.async {
            for path in paths {
                NSWorkspace.shared.noteFileSystemChanged(path)
            }
        }
    }
}

struct FileManagerArchiveExtractionContext {
    let archive: SZArchive
    let allEntries: [ArchiveItem]
    let currentSubdir: String
    let quarantineSourceArchivePath: String?
}

/// Prepared extraction work is handed to ArchiveOperationRunner; archive/session access is coordinated by the caller.
struct FileManagerPreparedExtraction: @unchecked Sendable {
    let archive: SZArchive
    let entryIndices: [NSNumber]
    let destinationURL: URL
    let settings: SZExtractionSettings
    let materializeNewDestination: Bool

    nonisolated func perform(session: SZOperationSession?) throws {
        if materializeNewDestination,
           settings.pathMode != .absolutePaths,
           let materialization = try FileManagerExtractionMaterialization.prepareNewDestination(
               finalURL: destinationURL,
               publishRootIsDirectory: true,
           )
        {
            try materialization.createPublishRootDirectoryIfNeeded()
            var extractionError: Error?
            do {
                try archive.extractEntries(entryIndices,
                                           toPath: materialization.publishRootURL.path,
                                           settings: settings,
                                           session: session)
            } catch {
                extractionError = error
            }
            try materialization.finish(operationError: extractionError)
            return
        }

        try archive.extractEntries(entryIndices,
                                   toPath: destinationURL.path,
                                   settings: settings,
                                   session: session)
    }
}

enum FileManagerArchiveExtraction {
    static func prepare(items: [ArchiveItem],
                        context: FileManagerArchiveExtractionContext,
                        destinationURL: URL,
                        overwriteMode: SZOverwriteMode,
                        pathMode: SZPathMode,
                        password: String?,
                        preserveNtSecurityInfo: Bool,
                        eliminateDuplicates: Bool,
                        inheritDownloadedFileQuarantine: Bool,
                        materializeNewDestination: Bool = true) -> FileManagerPreparedExtraction?
    {
        let indices = entryIndices(for: items,
                                   allEntries: context.allEntries)
        guard !indices.isEmpty else { return nil }

        let settings = extractionSettings(context: context,
                                          overwriteMode: overwriteMode,
                                          pathMode: pathMode,
                                          password: password,
                                          inheritDownloadedFileQuarantine: inheritDownloadedFileQuarantine)
        settings.pathPrefixToStrip = pathPrefixToStrip(for: items,
                                                       context: context,
                                                       destinationURL: destinationURL,
                                                       pathMode: pathMode,
                                                       eliminateDuplicates: eliminateDuplicates)
        settings.preserveNtSecurityInfo = preserveNtSecurityInfo

        return FileManagerPreparedExtraction(archive: context.archive,
                                             entryIndices: indices,
                                             destinationURL: destinationURL.standardizedFileURL,
                                             settings: settings,
                                             materializeNewDestination: materializeNewDestination)
    }

    static func performFullArchiveExtraction(_ archive: SZArchive,
                                             to destinationURL: URL,
                                             settings: SZExtractionSettings,
                                             session: SZOperationSession?) throws
    {
        if settings.pathMode != .absolutePaths,
           let materialization = try FileManagerExtractionMaterialization.prepareNewDestination(
               finalURL: destinationURL,
               publishRootIsDirectory: true,
           )
        {
            try materialization.createPublishRootDirectoryIfNeeded()
            var extractionError: Error?
            do {
                try archive.extract(toPath: materialization.publishRootURL.path,
                                    settings: settings,
                                    session: session)
            } catch {
                extractionError = error
            }
            try materialization.finish(operationError: extractionError)
            return
        }

        try archive.extract(toPath: destinationURL.path,
                            settings: settings,
                            session: session)
    }

    static func pathPrefixToStrip(for items: [ArchiveItem],
                                  context: FileManagerArchiveExtractionContext,
                                  destinationURL: URL,
                                  pathMode: SZPathMode,
                                  eliminateDuplicates: Bool) -> String?
    {
        let basePrefix: String? = if pathMode == .currentPaths,
                                     !context.currentSubdir.isEmpty
        {
            context.currentSubdir
        } else {
            nil
        }

        guard eliminateDuplicates,
              pathMode != .absolutePaths,
              pathMode != .noPaths,
              let duplicatePrefix = ArchiveItem.duplicateRootPrefixToStrip(for: items,
                                                                           destinationLeafName: destinationURL.lastPathComponent,
                                                                           removingPrefix: basePrefix)
        else {
            return basePrefix
        }

        return duplicatePrefix
    }

    static func entryIndices(for selectedItems: [ArchiveItem],
                             allEntries: [ArchiveItem]) -> [NSNumber]
    {
        var indices = Set<Int>()

        for item in selectedItems {
            if item.index >= 0 {
                indices.insert(item.index)
            }

            if item.isDirectory || item.index < 0 {
                let directoryPath = normalizeArchivePath(item.path)
                let prefix = directoryPath.isEmpty ? "" : directoryPath + "/"

                for entry in allEntries where entry.index >= 0 {
                    let entryPath = normalizeArchivePath(entry.path)
                    if entryPath == directoryPath || (!prefix.isEmpty && entryPath.hasPrefix(prefix)) {
                        indices.insert(entry.index)
                    }
                }
            }
        }

        return indices.sorted().map { NSNumber(value: $0) }
    }

    private static func extractionSettings(context: FileManagerArchiveExtractionContext,
                                           overwriteMode: SZOverwriteMode,
                                           pathMode: SZPathMode,
                                           password: String?,
                                           inheritDownloadedFileQuarantine: Bool) -> SZExtractionSettings
    {
        let settings = SZExtractionSettings()
        settings.overwriteMode = overwriteMode
        settings.pathMode = pathMode
        if let password, !password.isEmpty {
            settings.password = password
        }
        if inheritDownloadedFileQuarantine {
            settings.sourceArchivePathForQuarantine = context.quarantineSourceArchivePath
        }
        if pathMode == .currentPaths,
           !context.currentSubdir.isEmpty
        {
            settings.pathPrefixToStrip = context.currentSubdir
        }
        return settings
    }

    private static func normalizeArchivePath(_ path: String) -> String {
        var normalized = path
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
