import PDFOCRKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @Bindable var model: AppModel
    @State private var isChoosingFolder = false
    @State private var presetName = ""
    @State private var isNamingPreset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                presetSection
                Divider()
                modeSection
                Divider()
                basicSection
                Divider()
                advancedSection
            }
            .padding(16)
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                model.destination = .chosenFolder
                model.outputFolder = first
            }
        }
        .alert("Profil adı", isPresented: $isNamingPreset) {
            TextField("Örn. DenetimBelgeleri", text: $presetName)
            Button("Kaydet") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.savePreset(named: name) }
                presetName = ""
            }
            Button("Vazgeç") { presetName = "" }
        }
    }

    // MARK: - presets

    private var presetSection: some View {
        Section("Profiller") {
            Picker("Profil", selection: Binding(
                get: { model.presetStore.presets.first?.name ?? "" },
                set: { model.currentPreset(named: $0) }
            )) {
                ForEach(model.presetStore.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }

            HStack {
                Button {
                    isNamingPreset = true
                } label: {
                    Label("Bu ayarları kaydet", systemImage: "plus")
                }
                Spacer()
                Button(role: .destructive) {
                    if let first = model.presetStore.presets.first {
                        model.presetStore.remove(at: IndexSet(integer: 0))
                        model.currentPreset(named: first.name)
                    }
                } label: {
                    Label("Sil", systemImage: "trash")
                }
                .disabled(model.presetStore.presets.count <= 1)
            }
            .controlSize(.small)
        }
    }

    // MARK: - mode

    private var modeSection: some View {
        Section("Ne yapılsın") {
            Picker("", selection: $model.mode) {
                ForEach(ProcessingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(model.mode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - always visible

    private var basicSection: some View {
        Section("Temel") {
            Picker("Çıktı", selection: $model.destination) {
                ForEach(OutputDestination.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            if model.destination == .chosenFolder {
                HStack {
                    Text(model.outputFolder?.lastPathComponent ?? "Klasör seçilmedi")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Seç…") { isChoosingFolder = true }
                        .controlSize(.small)
                }
            }

            // A Picker cannot show a multi-selection readably, so use a menu
            // with checkmarks and keep the chosen codes visible in the label.
            Menu {
                ForEach(PDFInspector.commonLanguages, id: \.self) { code in
                    Button {
                        toggle(code)
                    } label: {
                        if model.languages.contains(code) {
                            Label(code, systemImage: "checkmark")
                        } else {
                            Text(code)
                        }
                    }
                }
            } label: {
                Text("Diller: " + (model.languages.isEmpty
                    ? "seçilmedi"
                    : model.languages.joined(separator: ", ")))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tarama çözünürlüğü")
                    Spacer()
                    Text("\(Int(model.dpi)) DPI")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.dpi, in: 150...600, step: 50)
                Text("Taramalar genelde 300 DPI'dir. Tablo yoğun sayfalarda 400–600 daha iyi okunur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - advanced

    private var advancedSection: some View {
        Section {
            Toggle("Gelişmiş ayarlar", isOn: $model.advanced)
                .font(.headline)

            if model.advanced {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Tanıma düzeyi", selection: $model.recognitionLevel) {
                            Text("Hızlı").tag(RecognitionLevel.fast)
                            Text("Hassas").tag(RecognitionLevel.accurate)
                        }
                        .pickerStyle(.segmented)

                        Picker("Metin fontu", selection: $model.baseFont) {
                            Text("Helvetica").tag(BaseFont.helvetica)
                            Text("Times").tag(BaseFont.times)
                            Text("Courier").tag(BaseFont.courier)
                            Text("Unicode (gömülü)").tag(BaseFont.unicode)
                        }

                        Picker("Nokta boyutu", selection: $model.fontSizeMode) {
                            Text("Taranan kutuya göre").tag(FontSizeMode.matchBox)
                            Text("Sabit").tag(FontSizeMode.fixed(model.fixedFontSize))
                        }
                        if case .fixed = model.fontSizeMode {
                            Stepper(
                                "\(model.fixedFontSize, specifier: "%.1f") pt",
                                value: $model.fixedFontSize,
                                in: 4...24,
                                step: 0.5
                            )
                            Text("Sabit boyut, farklı büyüklükteki satırları eşit gösterir.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Satırları taranan genişliğe sıkıştır", isOn: $model.squeezeLines)
                        Toggle("Ayrıca .txt dökümü üret", isOn: $model.writePlainText)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Sayfa aralığı")
                                Spacer()
                                if !model.pageRangeText.isEmpty {
                                    Button("Temizle") { model.pageRangeText = "" }
                                        .controlSize(.small)
                                }
                            }
                            TextField("1-10, 15, 20-", text: $model.pageRangeText)
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                            Text(pageRangeHelp)
                                .font(.caption)
                                .foregroundStyle(pageRangeHelpColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Minimum güven")
                                Spacer()
                                Text(model.minimumConfidence, format: .number.precision(.fractionLength(2)))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.minimumConfidence, in: 0...0.9, step: 0.05)
                            Text("Düşük güvenli satırları atar. Temiz taramada 0 bırakmak en iyisi.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("Parametreler")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggle(_ code: String) {
        if let index = model.languages.firstIndex(of: code) {
            model.languages.remove(at: index)
        } else {
            model.languages.append(code)
        }
    }

    private var pageRangeHelp: String {
        let trimmed = model.pageRangeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Boş bırakılırsa tüm sayfalar." }
        guard let selection = try? PageSelection.parse(trimmed) else {
            return "Anlaşılmadı. Örnek: 1-10, 15, 20-"
        }
        switch selection {
        case .all: return "Tüm sayfalar"
        case .ranges(let ranges):
            return ranges
                .map { $0.upperBound == PageSelection.openEnded ? "\($0.lowerBound)-son" : "\($0.lowerBound)-\($0.upperBound)" }
                .joined(separator: ", ")
        }
    }

    private var pageRangeHelpColor: Color {
        model.pageRangeText.trimmingCharacters(in: .whitespaces).isEmpty
            ? .secondary
            : ((try? PageSelection.parse(model.pageRangeText)) != nil ? .secondary : .red)
    }
}