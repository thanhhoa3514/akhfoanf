import SwiftUI
import PDFKit

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// JPEG data for persisting pet photos / camera scans.
    func jpegDataCompat(quality: CGFloat = 0.85) -> Data? {
        #if canImport(UIKit)
        return jpegData(compressionQuality: quality)
        #else
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    nonisolated var cgImageCompat: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #else
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}

enum Thumbnailer {
    /// Small preview for a stored document (first PDF page or the image itself).
    nonisolated static func thumbnail(for url: URL, mimeType: String, size: CGSize = CGSize(width: 160, height: 200)) -> PlatformImage? {
        if mimeType == "application/pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return topOfPage(page, size: size) ?? page.thumbnail(of: size, for: .mediaBox)
        }
        return PlatformImage(contentsOfFile: url.path)
    }

    /// Renders the top-left part of a page, zoomed, so a 56pt thumbnail shows the letterhead and
    /// title instead of a near-blank miniature of a whole A4 sheet.
    nonisolated private static func topOfPage(_ page: PDFPage, size: CGSize, zoom: CGFloat = 1.8) -> PlatformImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, size.width > 0, size.height > 0 else { return nil }
        let regionWidth = box.width / zoom
        let regionHeight = regionWidth * size.height / size.width
        let region = CGRect(x: box.minX, y: box.maxY - regionHeight, width: regionWidth, height: regionHeight)

        let width = Int(size.width), height = Int(size.height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = size.width / region.width
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let cgImage = ctx.makeImage() else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: size.width / 2, height: size.height / 2))
        #endif
    }
}

// MARK: - Zoom navigation transition (iOS 18+ only; plain push elsewhere)

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Namespace shared by a NavigationStack so list thumbnails can zoom into detail views.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ZoomDestinationModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func zoomSource<ID: Hashable>(id: ID) -> some View { modifier(ZoomSourceModifier(id: id)) }
    func zoomDestination<ID: Hashable>(id: ID) -> some View { modifier(ZoomDestinationModifier(id: id)) }

    /// Inline navigation title on iPhone; no-op on macOS where it does not exist.
    @ViewBuilder
    func inlineTitleOnPhone() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

enum SystemSettings {
    /// Opens the app's page in system Settings (iOS) — used when notifications are denied.
    @MainActor
    static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
