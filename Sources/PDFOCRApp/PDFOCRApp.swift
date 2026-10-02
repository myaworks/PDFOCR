import SwiftUI

@main
struct PDFOCRApp: App {
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