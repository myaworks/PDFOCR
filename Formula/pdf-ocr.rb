# typed: false
# frozen_string_literal: true

# A prebuilt binary rather than a source build: the release already carries a
# universal `pdf-ocr`, so `brew install` does not need a toolchain, and
# `brew install --build-from-source` is not offered because there is nothing to
# build from.
class PdfOcr < Formula
  desc "Add a searchable text layer to scanned PDFs with macOS Vision"
  homepage "https://github.com/myaworks/PDFOCR"
  url "https://github.com/myaworks/PDFOCR/releases/download/v1.1.0/pdf-ocr-macos-universal.tar.gz"
  version "1.1.0"
  sha256 "d191f32c25059d8c970e6483e47fd290693eca2f103cf58b4d393a05541abf12"
  license "MIT"

  depends_on :macos

  def install
    bin.install "pdf-ocr"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pdf-ocr --version")

    # Give it something that looks like a scan and check the text comes back.
    # An empty page is enough: the point is that the pipeline runs and writes a
    # PDF, not that the recognition is good.
    (testpath/"sample.pdf").binwrite(<<~PDF)
      %PDF-1.4
      1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
      2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
      3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
      xref
      0 4
      0000000000 65535 f
      0000000009 00000 n
      0000000058 00000 n
      0000000115 00000 n
      trailer<</Size 4/Root 1 0 R>>
      startxref
      196
      %%EOF
    PDF

    system bin/"pdf-ocr", testpath/"sample.pdf"
    assert_path_exists testpath/"sample-ocr.pdf"
    assert_match "page", shell_output("#{bin}/pdf-ocr #{testpath}/sample.pdf 2>&1")
  end
end