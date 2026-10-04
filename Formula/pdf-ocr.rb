# typed: false
# frozen_string_literal: true

# A prebuilt binary rather than a source build: the release already carries a
# universal `pdf-ocr`, so `brew install` needs no toolchain, and there is
# nothing for `--build-from-source` to do.
class PdfOcr < Formula
  desc "Add a searchable text layer to scanned PDFs with macOS Vision"
  homepage "https://github.com/myaworks/PDFOCR"
  url "https://github.com/myaworks/PDFOCR/releases/download/v1.2.0/pdf-ocr-macos-universal.tar.gz"
  version "1.2.0"
  sha256 "af376340747ac6fad0123ccc3294c81e67d05385c8ce0d9213586d047219f847"
  license "MIT"

  depends_on :macos

  def install
    bin.install "pdf-ocr"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pdf-ocr --version")

    # One blank page, written with real xref offsets. A hand-written PDF with
    # guessed offsets makes CoreGraphics log a parse error, which would make the
    # test pass for the wrong reason.
    body = +"%PDF-1.4\n"
    offsets = []
    ["<< /Type /Catalog /Pages 2 0 R >>",
     "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
     "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"].each_with_index do |dict, index|
      offsets << body.bytesize
      body << "#{index + 1} 0 obj\n#{dict}\nendobj\n"
    end
    xref = body.bytesize
    body << "xref\n0 4\n0000000000 65535 f \n"
    offsets.each { |at| body << format("%010d 00000 n \n", at) }
    body << "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"

    pdf = testpath/"sample.pdf"
    pdf.binwrite(body)

    # Once only: pdf-ocr refuses to overwrite, so a second run would stop with
    # "already exists" and the assertion would fail for the wrong reason.
    # A blank page yields no text, which is the point — the pipeline ran and
    # wrote a PDF rather than falling over.
    output = shell_output("#{bin}/pdf-ocr #{pdf} 2>&1")
    assert_match "1 page(s) OCR'd", output
    assert_path_exists testpath/"sample-ocr.pdf"
  end
end