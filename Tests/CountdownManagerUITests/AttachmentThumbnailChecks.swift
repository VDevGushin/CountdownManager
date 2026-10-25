import CoreGraphics
import CountdownManagerUI
import Foundation

@MainActor
func testAttachmentThumbnailMedia(in directory: URL) async throws {
    let files = try UISmokeAttachmentMedia.make(in: directory)
    let originalBytes = try files.map { try Data(contentsOf: $0) }
    precondition(files.count == 15 && CGPDFDocument(files[1] as CFURL)?.numberOfPages == 2)
    let loader = AttachmentThumbnailLoader()
    for index in [0, 2] {
        guard let image = await loader.thumbnail(for: files[index], scale: 2) else {
            preconditionFailure("A valid synthetic image/video must produce a real thumbnail")
        }
        requireBoundedAttachmentThumbnail(image, maximum: 88)
    }
    guard let mini = await loader.thumbnail(for: files[0], scale: 2, pointSize: 36) else {
        preconditionFailure("The mini-panel must receive a real small preview")
    }
    requireBoundedAttachmentThumbnail(mini, maximum: 72)
    guard let firstPage = await loader.thumbnail(for: files[1], scale: 100) else {
        preconditionFailure("The first page of a valid PDF must render")
    }
    requireBoundedAttachmentThumbnail(firstPage, maximum: 132)
    try requireRedPDFPage(firstPage)

    let corruptPDF = directory.appendingPathComponent("Invalid.pdf")
    try Data("Not a PDF".utf8).write(to: corruptPDF)
    for file in [files[3], corruptPDF, directory.appendingPathComponent("Missing.png"), directory] {
        let fallback = await loader.thumbnail(for: file, scale: 2)
        precondition(fallback == nil, "Corrupt, missing, unsupported and directory inputs need a type fallback")
    }
    let richText = directory.appendingPathComponent("Preview.rtf")
    try Data(#"{\rtf1\ansi A document preview, beyond photos and movies.}"#.utf8).write(to: richText)
    let unknownType = directory.appendingPathComponent("Unknown.countdown-preview-test")
    try Data([0, 255, 17, 64]).write(to: unknownType)
    for file in [files[4], richText, unknownType] {
        let preview = await loader.thumbnail(for: file, scale: 2, pointSize: 36)
        if let preview { requireBoundedAttachmentThumbnail(preview, maximum: 72) }
        print("Attachment Quick Look: \(file.pathExtension) → \(preview == nil ? "fallback" : "preview")")
    }
    let cancelled = Task { @MainActor in await loader.thumbnail(for: files[0], scale: 2) }
    cancelled.cancel() // Main-actor isolation makes this cancellation happen before the child can start.
    let cancelledResult = await cancelled.value
    precondition(cancelledResult == nil, "A pre-cancelled request must not publish an image")
    loader.cancel()
    loader.cancel()
    let recovered = await loader.thumbnail(for: files[1], scale: 1)
    precondition(recovered != nil, "Cancellation must not poison the next attachment request")
    let after = try files.map { try Data(contentsOf: $0) }
    precondition(originalBytes == after, "Thumbnail generation must never mutate imported files")
    print("PASS attachment thumbnails: real PNG/MP4, PDF page zero, bounded raster, corrupt/missing/type fallback, pre-cancellation and unchanged file bytes")
}

private func requireBoundedAttachmentThumbnail(_ image: CGImage, maximum: Int) {
    precondition(image.width > 0 && image.height > 0 && image.width <= maximum && image.height <= maximum,
                 "A thumbnail must remain bounded to its 44-point display scale")
}

private func requireRedPDFPage(_ image: CGImage) throws {
    guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let bytes = context.data else { throw CocoaError(.fileReadUnknown) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
    let pixel = bytes.assumingMemoryBound(to: UInt8.self).advanced(by: (8 * 16 + 8) * 4)
    precondition(Int(pixel[0]) > Int(pixel[1]) + 80 && Int(pixel[0]) > Int(pixel[2]) + 80,
                 "The red first PDF page must be selected, rather than its green second page")
}
