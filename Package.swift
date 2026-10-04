// swift-tools-version: 6.2
import Foundation
import PackageDescription

let package = Package(
    name: "PDFOCR",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PDFOCRKit", targets: ["PDFOCRKit"]),
        .executable(name: "pdf-ocr", targets: ["pdf-ocr"]),
        .executable(name: "PDFOCR", targets: ["PDFOCRApp"]),
    ],
    targets: [
        .target(name: "PDFOCRKit"),
        .executableTarget(name: "pdf-ocr", dependencies: ["PDFOCRKit"]),
        .executableTarget(name: "PDFOCRApp", dependencies: ["PDFOCRKit"]),
        .testTarget(name: "PDFOCRKitTests", dependencies: ["PDFOCRKit"]),
    ]
)