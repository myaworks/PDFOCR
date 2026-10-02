import Foundation
import PDFOCRKit

let tool = "pdf-ocr"
let version = "1.0.0"

struct Usage: Error, CustomStringConvertible {
    var description: String { Self.text }
    static let text = """
    \(tool) \(version) — add a searchable text layer to scanned PDFs using macOS Vision.

    USAGE
      \(tool) [options] <input.pdf> [more.pdfs…]

    OPTIONS
      -o, --output <path>     Output file, or a directory when several inputs are
                              given. Default: <input>-ocr.pdf next to the input.
      -l, --lang <codes>      Recognition languages, comma separated. Default: en-US.
                              e.g. --lang tr-TR,en-US
          --level <mode>      fast | accurate. Default: accurate.
          --dpi <n>           Rasterization resolution. Default: 300.
          --pages <spec>      Page selection, e.g. 1-10,15,20-. Default: all.
          --font <name>       helvetica | times | courier | unicode. Default: helvetica.
                             The first three are PDF base-14 fonts and add no font
                             data; "unicode" embeds a subset so characters outside
                             Latin-1 survive.
          --font-size <n>     Fixed point size instead of matching the scanned box.
          --no-squeeze        Do not compress lines to the width of their ink.
          --redo-text         Also process pages that already have a text layer.
          --replace-text     Replace an existing text layer: the page is laid down
                             as a bitmap so the old text is gone. Implies
                             --redo-text. Use this on re-OCR, otherwise both the old
                             and the new text stay in the file and search returns
                             both. The page loses vector content.
          --min-confidence <f>  Drop lines below this score, 0…1. Default: 0.
          --text              Also write a .txt transcription next to the output.
      -f, --force             Overwrite the output if it exists.
      -q, --quiet             Only report warnings and errors.
      -h, --help              Show this help.
          --version           Show the version.

    NOTES
      Page size and appearance are preserved; only an invisible text layer is
      added. Bookmarks, form fields and link annotations are not carried over.
    """
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(tool): \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.isEmpty { fail(Usage.text) }

var output: String?
var languages: [String]?
var level: RecognitionLevel = .accurate
var dpi: Double = 300
var pages: PageSelection = .all
var baseFont: BaseFont = .helvetica
var fontSizeMode: FontSizeMode = .matchBox
var squeeze = true
var skipText = true
var replaceText = false
var minConfidence: Float = 0
var writeText = false
var force = false
var quiet = false
var inputs: [String] = []

@MainActor
func value(for flag: String) -> String {
    guard !arguments.isEmpty else { fail("\(flag) needs a value") }
    return arguments.removeFirst()
}

while !arguments.isEmpty {
    let arg = arguments.removeFirst()
    switch arg {
    case "-h", "--help":
        print(Usage.text)
        exit(0)
    case "--version":
        print("\(tool) \(version)")
        exit(0)
    case "-o", "--output": output = value(for: arg)
    case "-l", "--lang": languages = value(for: arg).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    case "--level":
        let raw = value(for: arg)
        guard let parsed = RecognitionLevel(rawValue: raw) else { fail("--level must be fast or accurate, got '\(raw)'") }
        level = parsed
    case "--dpi":
        let raw = value(for: arg)
        guard let parsed = Double(raw), parsed >= 72, parsed <= 1200 else { fail("--dpi must be 72…1200, got '\(raw)'") }
        dpi = parsed
    case "--pages":
        let raw = value(for: arg)
        do { pages = try PageSelection.parse(raw) }
        catch { fail("--pages: \(error)") }
    case "--font":
        let raw = value(for: arg)
        guard let parsed = BaseFont(rawValue: raw) else { fail("--font must be helvetica, times, courier or unicode, got '\(raw)'") }
        baseFont = parsed
    case "--font-size":
        let raw = value(for: arg)
        guard let parsed = Double(raw), parsed > 0 else { fail("--font-size must be positive, got '\(raw)'") }
        fontSizeMode = .fixed(parsed)
    case "--no-squeeze": squeeze = false
    case "--redo-text": skipText = false
    case "--replace-text": replaceText = true
    case "--min-confidence":
        let raw = value(for: arg)
        guard let parsed = Float(raw), (0...1).contains(parsed) else { fail("--min-confidence must be 0…1, got '\(raw)'") }
        minConfidence = parsed
    case "--text": writeText = true
    case "-f", "--force": force = true
    case "-q", "--quiet": quiet = true
    default:
        if arg.hasPrefix("-") { fail("unknown option '\(arg)' — try --help") }
        inputs.append(arg)
    }
}

guard !inputs.isEmpty else { fail("no input PDF given — try --help") }

if inputs.count > 1, let output, (try? URL(fileURLWithPath: output).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
    fail("--output must be a directory when several PDFs are given")
}

var options = OCROptions()
options.languages = languages ?? options.languages
options.recognitionLevel = level
options.dpi = dpi
options.pageSelection = pages
options.baseFont = baseFont
options.fontSizeMode = fontSizeMode
options.squeezeLines = squeeze
options.skipPagesWithText = skipText
options.replaceExistingText = replaceText
options.minimumConfidence = minConfidence
options.writePlainText = writeText

var failures = 0

for path in inputs {
    let source = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: source.path) else {
        fail("no such file '\(path)'")
    }

    let target: URL
    if let output {
        let asURL = URL(fileURLWithPath: output)
        let isDirectory = (try? asURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            target = asURL.appendingPathComponent(
                source.deletingPathExtension().lastPathComponent + "-ocr.pdf"
            )
        } else if inputs.count == 1 {
            target = asURL
        } else {
            fail("--output must be a directory when several PDFs are given")
        }
    } else {
        target = source.deletingPathExtension()
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-ocr")
            .appendingPathExtension("pdf")
    }

    if FileManager.default.fileExists(atPath: target.path), !force {
        fail("'\(target.lastPathComponent)' already exists — pass --force to overwrite")
    }

    do {
        let isQuiet = quiet
        let report = try OCRRun.run(input: source, output: target, options: options) { progress in
            guard !isQuiet else { return }
            let bar = Int(progress.fraction * 24)
            let filled = String(repeating: "#", count: bar)
            let rest = String(repeating: ".", count: 24 - bar)
            FileHandle.standardOutput.write(Data("\r[\(filled)\(rest)] \(progress.page)/\(progress.total)".utf8))
        }
        if !isQuiet { FileHandle.standardOutput.write(Data("\n".utf8)) }

        let confidence = report.averageConfidence > 0
            ? String(format: ", mean confidence %.2f", report.averageConfidence)
            : ""
        var extra = ""
        if !report.replacedPages.isEmpty { extra += ", \(report.replacedPages.count) text layer(s) replaced" }
        if !report.skippedPages.isEmpty { extra += ", \(report.skippedPages.count) skipped" }
        print("\(target.lastPathComponent): \(report.processedPages.count) page(s) OCR'd, "
            + "\(report.linesRecognized) line(s) in \(String(format: "%.1f", report.duration))s\(confidence)\(extra)")
        for warning in report.warnings { print("  warning: \(warning)") }
    } catch {
        FileHandle.standardError.write(Data("\(tool): \(source.lastPathComponent): \(error)\n".utf8))
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
