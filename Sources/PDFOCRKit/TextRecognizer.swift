import CoreGraphics
import Foundation
import Vision

public enum TextRecognizer {
    public static func recognize(
        image: CGImage,
        options: OCROptions
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.recognitionLevel.visionLevel
        request.usesLanguageCorrection = true
        request.recognitionLanguages = options.languages

        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, candidate.confidence >= options.minimumConfidence else { return nil }
            return RecognizedLine(
                text: text,
                box: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }

    /// Languages Vision can actually read on this machine, for the GUI picker.
    public static func supportedLanguages() -> [String] {
        (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequest.currentRevision
        )) ?? ["en-US"]
    }
}
