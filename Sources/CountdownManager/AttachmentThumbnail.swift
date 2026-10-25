import AppKit
import CountdownCore
import PDFKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Owns one cancellable native request. Its result is a small raster, never a persisted cache.
@MainActor
package final class AttachmentThumbnailLoader: ObservableObject {
    private var token: UUID?
    private var request: QLThumbnailGenerator.Request?
    private var continuation: CheckedContinuation<CGImage?, Never>?

    package init() {}

    package func thumbnail(for url: URL, scale: CGFloat, pointSize: CGFloat = 44) async -> CGImage? {
        cancel()
        guard !Task.isCancelled, url.isFileURL else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        let scale = scale.isFinite ? min(3, max(1, scale)) : 1
        let size = pointSize.isFinite ? min(256, max(1, pointSize)) : 44
        let current = UUID()
        token = current
        if type?.conforms(to: .pdf) == true {
            let image = await AttachmentPDFThumbnailRenderer.shared.firstPage(
                at: url, pixels: Int(ceil(size * scale))
            )
            guard token == current, !Task.isCancelled else { return nil }
            token = nil
            return image
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        self.request = request
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, token == current else {
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                    let candidate = representation?.type == .thumbnail ? representation?.cgImage : nil
                    let maximum = Int(ceil(size * scale))
                    let image = candidate.flatMap { $0.width <= maximum && $0.height <= maximum ? $0 : nil }
                    Task { @MainActor [weak self] in self?.finish(current, image: image) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(current) }
        }
    }

    package func cancel() {
        guard let token else { return }
        cancel(token)
    }

    private func cancel(_ current: UUID) {
        guard token == current else { return }
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        finish(current, image: nil)
    }

    private func finish(_ current: UUID, image: CGImage?) {
        guard token == current else { return }
        token = nil
        request = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: image)
    }
}

/// PDFKit objects remain local to this serial, non-UI actor. Only a bounded first-page bitmap escapes.
private actor AttachmentPDFThumbnailRenderer {
    static let shared = AttachmentPDFThumbnailRenderer()

    func firstPage(at url: URL, pixels: Int) -> CGImage? {
        autoreleasepool {
            guard !Task.isCancelled, let document = PDFDocument(url: url), !document.isLocked,
                  let page = document.page(at: 0), let reference = page.pageRef,
                  let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let pageBounds = reference.getBoxRect(.mediaBox)
            guard !pageBounds.isInfinite, !pageBounds.isEmpty, !pageBounds.isNull else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.concatenate(reference.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(reference)
            guard !Task.isCancelled else { return nil }
            return context.makeImage()
        }
    }
}

struct AttachmentThumbnail: View {
    private struct RequestIdentity: Hashable {
        let attachmentID: UUID
        let pixels: Int
    }

    let attachment: EventAttachment
    let fallbackSymbol: String
    let controlID: String
    let resolveURL: @MainActor () async -> URL?
    var pointSize: CGFloat = 44
    var canvasSize: CGSize?
    var showsUnavailableLabel = false
    @StateObject private var loader = AttachmentThumbnailLoader()
    @State private var image: CGImage?
    @State private var isLoading = false
    @State private var isUnavailable = false
    @Environment(\.displayScale) private var displayScale

    private var isMovie: Bool {
        UTType(filenameExtension: (attachment.name as NSString).pathExtension)?.conforms(to: .movie) == true
    }

    private var requestIdentity: RequestIdentity {
        let size = pointSize.isFinite ? min(256, max(1, pointSize)) : 44
        let scale = displayScale.isFinite ? min(3, max(1, displayScale)) : 1
        return RequestIdentity(attachmentID: attachment.id, pixels: Int(ceil(size * scale)))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable().scaledToFit()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 20))
                    if showsUnavailableLabel, isUnavailable {
                        Text("Копия недоступна")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: canvasSize?.width ?? pointSize, height: canvasSize?.height ?? pointSize)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottomTrailing) {
            if image != nil, isMovie {
                Image(systemName: "film")
                    .accessibilityHidden(true)
                    .font(.system(size: 9, weight: .medium))
                    .padding(3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
        .uiSmokeControl(id: controlID, value: { image != nil ? "ready" : (isLoading ? "loading" : "fallback") })
        .task(id: requestIdentity) {
            image = nil
            isLoading = true
            isUnavailable = false
            guard let url = await resolveURL(), !Task.isCancelled else {
                guard !Task.isCancelled else { return }
                isUnavailable = true
                isLoading = false
                return
            }
            let thumbnail = await loader.thumbnail(for: url, scale: displayScale, pointSize: pointSize)
            guard !Task.isCancelled else { return }
            image = thumbnail
            isLoading = false
        }
        .onDisappear { loader.cancel() }
    }
}
