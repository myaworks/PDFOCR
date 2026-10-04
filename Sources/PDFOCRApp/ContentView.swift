import PDFOCRKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false
    // a .constant binding here is not writable; SwiftUI writes to it during layout
    // and AppKit traps, so keep real state for the inspector.
    @State private var isInspectorVisible = true

    var body: some View {
        NavigationSplitView {
            FileSidebar(model: model, isDropTargeted: $isDropTargeted)
        } detail: {
            QueueView(model: model)
                .navigationTitle("PDFOCR")
        }
        .inspector(isPresented: $isInspectorVisible) {
            InspectorView(model: model)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.clearAll()
                } label: {
                    Label("Temizle", systemImage: "trash")
                }
                .disabled(model.isRunning || model.items.isEmpty)

                Button {
                    model.isRunning ? model.cancel() : model.start()
                } label: {
                    Label(
                        model.isRunning ? "Durdur" : "Başlat",
                        systemImage: model.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.glass)
                .disabled(!model.isRunning && model.items.allSatisfy { $0.phase.isFinished || $0.isUnreadable })
            }
        }
        .fileImporter(
            isPresented: $model.isChoosingFiles,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.add(urls: urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls.filter { $0.pathExtension.lowercased() == "pdf" })
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .onOpenURL { model.add(urls: [$0]) }
        .onAppear {
            DocumentOpener.register { model.add(urls: $0) }

            // Also accept files given on the command line, which is what
            // happens when the bundle has no document types: `swift run
            // PDFOCRApp ~/scans/report.pdf`
            let passed = CommandLine.arguments
                .dropFirst()
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !passed.isEmpty { model.add(urls: passed) }
        }
        .animation(.snappy, value: model.items.count)
    }
}

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 44))
                Text("PDF'leri bırak")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
        .allowsHitTesting(false)
    }
}