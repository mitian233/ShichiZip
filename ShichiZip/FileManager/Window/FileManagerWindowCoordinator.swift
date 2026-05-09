import Cocoa

@MainActor
protocol FileManagerArchiveCoordinationProviding: AnyObject {
    func archiveCoordinationSnapshots() -> [FileManagerNestedArchiveOpenSnapshot]
}

@MainActor
protocol FileManagerWindowCoordinating: FileManagerArchiveCoordinationProviding {
    func openArchiveInNewFileManager(_ url: URL)
}

@MainActor
protocol FileManagerDocumentOpenRouting: AnyObject {
    func beginDeferredArchiveOpen()
    func endDeferredArchiveOpen()
    func openArchiveInNewFileManager(_ url: URL)
}

@MainActor
final class FileManagerWindowRegistry: FileManagerWindowCoordinating {
    private var controllers: [FileManagerWindowController] = []

    @discardableResult
    func prepareForApplicationTermination(showError: Bool = true) -> Bool {
        for controller in controllers {
            guard controller.prepareForClose(showError: showError) else {
                return false
            }
        }
        return true
    }

    func showFileManager(_ sender: Any?) {
        showFileManagerWindow(reusableFileManagerWindowController() ?? makeFileManagerWindowController(),
                              sender: sender)
    }

    func openArchiveInFileManager(_ url: URL) {
        let reusableController = reusableFileManagerWindowController()
        let controller = reusableController ?? makeFileManagerWindowController()
        if controller.navigateToArchive(url, revealWindow: false) {
            showFileManagerWindow(controller,
                                  sender: nil)
        } else if reusableController == nil {
            removeFileManagerWindowController(controller)
        }
    }

    func openArchiveInNewFileManager(_ url: URL) {
        let controller = makeFileManagerWindowController()
        if controller.navigateToArchive(url, revealWindow: false) {
            showFileManagerWindow(controller,
                                  sender: nil)
        } else {
            removeFileManagerWindowController(controller)
        }
    }

    @discardableResult
    func openFileSystemItemInNewFileManager(_ url: URL) -> Bool {
        let controller = makeFileManagerWindowController()
        if controller.openFileSystemItem(url, revealWindow: false) {
            showFileManagerWindow(controller,
                                  sender: nil)
            return true
        }

        removeFileManagerWindowController(controller)
        return false
    }

    func revealFileSystemItemsInNewWindow(_ urls: [URL]) {
        let controller = makeFileManagerWindowController()

        if controller.revealFileSystemItems(urls, revealWindow: false) {
            showFileManagerWindow(controller,
                                  sender: nil)
        } else {
            removeFileManagerWindowController(controller)
        }
    }

    func archiveCoordinationSnapshots() -> [FileManagerNestedArchiveOpenSnapshot] {
        controllers.flatMap { $0.archiveCoordinationSnapshots() }
    }

    private func reusableFileManagerWindowController() -> FileManagerWindowController? {
        if let keyController = NSApp.keyWindow?.windowController as? FileManagerWindowController,
           controllers.contains(where: { $0 === keyController })
        {
            return keyController
        }

        if let mainController = NSApp.mainWindow?.windowController as? FileManagerWindowController,
           controllers.contains(where: { $0 === mainController })
        {
            return mainController
        }

        return controllers.last { $0.window?.isVisible == true } ?? controllers.last
    }

    private func makeFileManagerWindowController() -> FileManagerWindowController {
        let controller = FileManagerWindowController(windowCoordinator: self)
        controller.onWindowWillClose = { [weak self] closingController in
            self?.removeFileManagerWindowController(closingController)
        }
        controllers.append(controller)
        return controller
    }

    private func showFileManagerWindow(_ controller: FileManagerWindowController,
                                       sender: Any?)
    {
        cascadeFileManagerWindowIfNeeded(controller)
        controller.showWindow(sender)
    }

    private func cascadeFileManagerWindowIfNeeded(_ controller: FileManagerWindowController) {
        guard let window = controller.window,
              !window.isVisible,
              !window.isMiniaturized
        else { return }

        window.cascadeTopLeft(from: firstFileManagerWindowTopLeftPoint(for: window,
                                                                       excluding: controller))
    }

    private func firstFileManagerWindowTopLeftPoint(for window: NSWindow,
                                                    excluding controller: FileManagerWindowController) -> NSPoint
    {
        guard let sourceWindow = controllers
            .filter({ $0 !== controller })
            .compactMap(\.window)
            .last(where: { $0.isVisible })
        else {
            return NSPoint(x: window.frame.minX, y: window.frame.maxY)
        }

        let sourceTopLeftPoint = NSPoint(x: sourceWindow.frame.minX,
                                         y: sourceWindow.frame.maxY)
        return window.cascadeTopLeft(from: sourceTopLeftPoint)
    }

    private func removeFileManagerWindowController(_ controller: FileManagerWindowController) {
        controllers.removeAll { $0 === controller }
    }
}
