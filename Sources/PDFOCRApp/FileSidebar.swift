import PDFOCRKit
import SwiftUI

struct FileSidebar: View {
    @Bindable var model: AppModel
    @Binding var isDropTargeted: Bool

    var body: some View {
        List {
            Section {
                ForEach(model.items) { item in
                    FileRow(item: item, mode: model.destination(for: item))
                        .contextMenu {
                            Button("Listeden Çıkar") { model.remove(item) }
                                .disabled(model.isRunning)
                            Button("Finder'da Göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Dosyalar")
                    Spacer()
                    Text("\(model.items.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    model.isChoosingFiles = true
                } label: {
                    Label("PDF Ekle", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("PDF ekle")

                Button {
                    model.removeFinished()
                } label: {
                    Label("Tamamlananları temizle", systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.isRunning || model.finishedCount == 0)
                .help("Tamamlananları temizle")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct FileRow: View {
    let item: AppModel.Item
    let mode: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .font(.body)
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let info = item.info {
                HStack(spacing: 5) {
                    CoverageBadge(status: info.status)
                    Text("\(info.pageCount) sayfa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.phase == .done {
                        Text("· \(item.lines) satır")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(item.failure ?? "Okunamadı")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch item.phase {
        case .done: "doc.text.fill"
        case .running: "hourglass"
        case .cancelled: "pause.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .waiting: "doc"
        }
    }
}

struct CoverageBadge: View {
    let status: DocumentInfo.Coverage

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .unreadable: "okunamadı"
        case .none: "metin yok"
        case .complete: "tamamı metinli"
        case .partial(let count): "\(count) sayfa metinli"
        }
    }

    private var tint: Color {
        switch status {
        case .unreadable: .red
        case .none: .orange
        case .complete: .green
        case .partial: .yellow
        }
    }
}