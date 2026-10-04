import AppKit
import SwiftUI

/// Receives the "open a document" event, so PDFOCR shows up under Finder's
/// Open With and double-clicking a PDF adds it to the queue.
///
/// Declaring `CFBundleDocumentTypes` is what makes macOS send this event
/// instead of putting the file in `CommandLine.arguments`, so the two paths are
/// not interchangeable — both are handled.
///
/// Events can arrive before the window exists, so anything that turns up early
/// is held until a handler registers.
@MainActor
final class DocumentOpener: NSObject, NSApplicationDelegate {
    private static var pending: [URL] = []
    private static var handler: ((@MainActor ([URL]) -> Void))?

    static func register(_ handler: @escaping @MainActor ([URL]) -> Void) {
        self.handler = handler
        guard !pending.isEmpty else { return }
        let urls = pending
        pending = []
        handler(urls)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = Self.handler {
            handler(urls)
        } else {
            Self.pending.append(contentsOf: urls)
        }
    }
}

@main
struct PDFOCRApp: App {
    @NSApplicationDelegateAdaptor(DocumentOpener.self) private var opener
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDF Ekle…") { model.isChoosingFiles = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .appInfo) {}
            CommandMenu("OCR") {
                Button(model.isRunning ? "Durdur" : "Başlat") {
                    model.isRunning ? model.cancel() : model.start()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isRunning && model.items.allSatisfy { $0.phase.isFinished || $0.isUnreadable })

                Divider()

                Button("Tamamlananları Temizle") { model.removeFinished() }
                    .disabled(model.isRunning || model.finishedCount == 0)

                Button("Listeyi Boşalt") { model.clearAll() }
                    .disabled(model.isRunning || model.items.isEmpty)
            }
        }
    }
}