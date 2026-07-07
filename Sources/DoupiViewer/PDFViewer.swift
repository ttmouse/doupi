import PDFKit
import SwiftUI

/// Displays PDF files using PDFKit.PDFView.
struct PDFViewer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1.0)
        return pdfView
    }

    func updateNSView(_ nsView: PDFKit.PDFView, context: Context) {
        if let currentDoc = nsView.document,
           let currentURL = currentDoc.documentURL,
           currentURL == url {
            return
        }
        nsView.document = PDFDocument(url: url)
    }
}
