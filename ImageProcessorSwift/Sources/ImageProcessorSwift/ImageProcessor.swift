import Foundation
import CoreGraphics
import ImageIO
import CoreText
import AppKit
import UniformTypeIdentifiers

// MARK: - EXIF Extraction
// Uses ImageIO directly — no _getexif() hack, and works on any JPEG ImageIO can decode.

struct ExifInfo {
    var iso: String        = "N/A"
    var aperture: String   = "N/A"
    var shutterSpeed: String = "N/A"
    var camera: String     = "N/A"
    var lens: String       = "N/A"
    var focalLength: String = "N/A"
}

func extractExif(from source: CGImageSource) -> ExifInfo {
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
        return ExifInfo()
    }

    var info = ExifInfo()
    let exif = props["{Exif}"] as? [String: Any]
    let tiff = props["{TIFF}"] as? [String: Any]

    // ISO — stored as an array of integers
    if let isoRatings = exif?["ISOSpeedRatings"] as? [Int], let first = isoRatings.first {
        info.iso = "\(first)"
    }

    // Aperture — APEX value → f-number = 2^(APEX/2)
    if let av = exif?["ApertureValue"] as? Double {
        info.aperture = String(format: "f/%.1f", pow(2.0, av / 2.0))
    }

    // Shutter speed — APEX value → seconds = 2^(-APEX)
    if let sv = exif?["ShutterSpeedValue"] as? Double {
        let sec = pow(2.0, -sv)
        info.shutterSpeed = sec < 1.0
            ? "1/\(Int(round(1.0 / sec)))"
            : String(format: "%.1f", sec)
    }

    // Focal length in mm
    if let fl = exif?["FocalLength"] as? Double {
        info.focalLength = "\(Int(fl))mm"
    }

    // Camera model (TIFF IFD)
    if let model = tiff?["Model"] as? String {
        info.camera = model
    }

    // Lens model (Exif IFD)
    if let lens = exif?["LensModel"] as? String {
        info.lens = lens
    }

    return info
}

// MARK: - Canvas Expansion
// Adds white bars to reach a 4:3 canvas, same logic as expand_image() in Python.

func expandToFourThirds(_ image: CGImage) -> CGImage? {
    let w = image.width
    let h = image.height
    let aspect = Double(w) / Double(h)
    let target  = 4.0 / 3.0

    // Wider than 4:3 → add top/bottom bars; taller → add left/right bars
    let newW = aspect > target ? w : Int(Double(h) * target)
    let newH = aspect > target ? Int(Double(w) / target) : h

    guard let ctx = CGContext(
        data: nil, width: newW, height: newH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // White background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))

    // Center original image
    // Note: CGContext origin is bottom-left, so (0,0) = bottom-left of the canvas.
    ctx.draw(image, in: CGRect(
        x: (newW - w) / 2,
        y: (newH - h) / 2,
        width: w, height: h
    ))

    return ctx.makeImage()
}

// MARK: - Text Overlay
// Mirrors Python's draw.text() with 4-offset black outline + white fill.
// CGContext origin is bottom-left (y=0 at bottom), so positions are inverted vs PIL.

func addTextOverlay(
    to image: CGImage,
    line1: String,   // overlay_text  (top)
    line2: String,   // camera + lens (middle)
    line3: String,   // EXIF string   (bottom)
    fontSize: CGFloat,
    marginX: CGFloat,
    marginY: CGFloat
) -> CGImage? {
    let w = image.width
    let h = image.height

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // Draw original image first
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    let font = CTFontCreateWithName("Arial" as CFString, fontSize, nil)
    let lineSpacing = fontSize * 1.4

    // In CG (y=0 at bottom):
    //   line3 baseline = marginY              (closest to bottom)
    //   line2 baseline = marginY + lineSpacing
    //   line1 baseline = marginY + lineSpacing * 2  (furthest from bottom = "top")
    let y3 = marginY
    let y2 = marginY + lineSpacing
    let y1 = marginY + lineSpacing * 2.0

    func render(_ text: String, x: CGFloat, y: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    // Draw 4-pixel black outline (matches Python's offset loop)
    let offsets: [(CGFloat, CGFloat)] = [(-2, -2), (-2, 2), (2, -2), (2, 2)]
    for (dx, dy) in offsets {
        render(line1, x: marginX + dx, y: y1 + dy, color: .black)
        render(line2, x: marginX + dx, y: y2 + dy, color: .black)
        render(line3, x: marginX + dx, y: y3 + dy, color: .black)
    }

    // Draw white text on top
    render(line1, x: marginX, y: y1, color: .white)
    render(line2, x: marginX, y: y2, color: .white)
    render(line3, x: marginX, y: y3, color: .white)

    return ctx.makeImage()
}

// MARK: - JPEG Save
// Quality 1.0 = maximum quality, equivalent to Python's quality=100.

func saveJPEG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.jpeg.identifier as CFString,
        1, nil
    ) else { return }
    CGImageDestinationAddImage(
        dest, image,
        [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
    )
    CGImageDestinationFinalize(dest)
}

// MARK: - Single Image Processor
// Called concurrently from the task group — no shared mutable state.

func processImage(
    at url: URL,
    outputDir: URL,
    overlayText: String,
    textHeightPercent: Double,
    marginPercent: Double
) -> ProcessingResult {
    let t0 = Date()
    let filename = url.lastPathComponent

    // File size in MB
    let fileSize: Double
    if let sz = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        fileSize = Double(sz) / 1_000_000
    } else {
        fileSize = 0
    }

    // Load image via ImageIO (fast hardware-backed JPEG decoder on M4)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image  = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return ProcessingResult(
            status: .error, filename: filename,
            processingTime: 0, fileSize: fileSize,
            message: "Error: could not open \(filename)",
            thumbnail: nil
        )
    }

    // Thumbnail — ImageIO reads a JPEG thumbnail from the embedded JFIF/Exif
    // thumbnail segment instead of decoding the full image: much faster than PIL's copy().
    // `...FromImageIfAbsent` (not `...Always`) is what makes that true — `Always`
    // forces a full decode. `WithTransform` applies the EXIF orientation tag.
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: 100,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    let thumbCG  = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    let thumbnail = thumbCG.map {
        NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
    }

    let w      = image.width
    let h      = image.height
    let aspect = Double(w) / Double(h)
    let outURL = outputDir.appendingPathComponent(filename)
    let elapsed = { Date().timeIntervalSince(t0) * 1000 }

    // ── 9:16 portrait → add EXIF text overlay ──────────────────────────────
    if (0.5623 ... 0.5627).contains(aspect) {
        let exif = extractExif(from: source)
        let cameraStr = exif.lens != "N/A"
            ? "\(exif.camera) + \(exif.lens)"
            : exif.camera
        let exifStr = "ISO \(exif.iso) | \(exif.aperture) | SS \(exif.shutterSpeed) | \(exif.focalLength)"

        let output = addTextOverlay(
            to: image,
            line1: overlayText,
            line2: cameraStr,
            line3: exifStr,
            fontSize: CGFloat(h) * textHeightPercent,
            marginX:  CGFloat(w) * marginPercent,
            marginY:  CGFloat(h) * marginPercent
        ) ?? image

        saveJPEG(output, to: outURL)
        return ProcessingResult(
            status: .processed, filename: filename,
            processingTime: elapsed(), fileSize: fileSize,
            message: "Added overlay: \(filename)", thumbnail: thumbnail
        )
    }

    // ── Exact 4:3 → file copy (no re-encode, better than Python which re-encodes) ──
    if abs(aspect - 4.0 / 3.0) < 0.001 {
        try? FileManager.default.copyItem(at: url, to: outURL)
        return ProcessingResult(
            status: .skipped, filename: filename,
            processingTime: elapsed(), fileSize: fileSize,
            message: "Copied: \(filename)", thumbnail: thumbnail
        )
    }

    // ── Other ratio → expand canvas to 4:3 ─────────────────────────────────
    let expanded = expandToFourThirds(image) ?? image
    saveJPEG(expanded, to: outURL)
    return ProcessingResult(
        status: .processed, filename: filename,
        processingTime: elapsed(), fileSize: fileSize,
        message: "Processed: \(filename)", thumbnail: thumbnail
    )
}

// MARK: - Processing Service
// An `actor` ensures the directory setup/teardown is serialized while
// the actual image work runs concurrently inside the TaskGroup.

actor ImageProcessingService {

    @discardableResult
    func process(
        directory url: URL,
        settings: AppSettings,           // value-type — safe to capture in tasks
        onProgress: @MainActor @escaping (ProcessingResult) -> Void
    ) async -> [ProcessingResult] {

        let outputDir = url.appendingPathComponent("cropped")

        // Create output directory
        try? FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true
        )

        // Clear previous output
        if let existing = try? FileManager.default.contentsOfDirectory(
            at: outputDir, includingPropertiesForKeys: nil
        ) {
            for file in existing {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Collect input JPEGs
        let files = (
            try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey]
            )
        )?.filter {
            ["jpg", "jpeg"].contains($0.pathExtension.lowercased())
        } ?? []

        // ── Parallel processing via Swift structured concurrency ──────────
        // withTaskGroup schedules child tasks on the cooperative thread pool.
        // On M4, this naturally saturates P-cores and E-cores simultaneously.
        // No GIL, no thread creation overhead — pure M4 parallelism.
        return await withTaskGroup(of: ProcessingResult.self) { group in
            for file in files {
                let s = settings   // capture value copy
                group.addTask {
                    processImage(
                        at: file,
                        outputDir: outputDir,
                        overlayText: s.overlayText,
                        textHeightPercent: s.textHeightPercent,
                        marginPercent: s.marginPercent
                    )
                }
            }

            var results: [ProcessingResult] = []
            for await result in group {
                await onProgress(result)   // hop to MainActor → update UI
                results.append(result)
            }
            return results
        }
    }
}
