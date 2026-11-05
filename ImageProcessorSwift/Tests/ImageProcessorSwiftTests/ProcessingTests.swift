import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ImageProcessorSwift

/// Covers the decisions `processImage` makes about a file: orientation, aspect-ratio
/// routing, and whether the output is actually written.
final class ProcessingTests: XCTestCase {

    private var workDir: URL!
    private var outputDir: URL!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(".artifacts", isDirectory: true)
        workDir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        outputDir = workDir.appendingPathComponent("cropped", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir, FileManager.default.fileExists(atPath: workDir.path) {
            try FileManager.default.removeItem(at: workDir)
        }
    }

    // MARK: - Fixtures

    enum FixtureError: Error { case couldNotCreateContext, couldNotWrite }

    /// Writes a solid-colour JPEG, optionally carrying an Exif orientation tag (1–8)
    /// and/or extra ImageIO properties such as camera metadata.
    @discardableResult
    private func writeJPEG(
        width: Int,
        height: Int,
        orientation: UInt32? = nil,
        extraProperties: [CFString: Any] = [:],
        named name: String
    ) throws -> URL {
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            let image = ctx.makeImage()
        else { throw FixtureError.couldNotCreateContext }

        let url = workDir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw FixtureError.couldNotWrite }

        var props: [CFString: Any] = extraProperties
        props[kCGImageDestinationLossyCompressionQuality] = 0.95
        if let orientation {
            props[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw FixtureError.couldNotWrite }
        return url
    }

    private func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (image.width, image.height)
    }

    private func process(_ url: URL) -> ProcessingResult {
        processImage(
            at: url,
            outputDir: outputDir,
            overlayText: "Test Overlay",
            textHeightPercent: 0.02,
            marginPercent: 0.05
        )
    }

    // MARK: - Orientation

    /// A portrait phone photo is stored landscape with "rotate 90°" in Exif. If the tag is
    /// ignored the image measures 16:9 and gets bars on the wrong axis.
    func testExifOrientationDecidesTheAspectRatio() throws {
        let source = try writeJPEG(width: 1600, height: 900, orientation: 6, named: "stored-landscape.jpg")

        let result = process(source)

        XCTAssertEqual(result.status, .processed,
                       "orientation 6 turns 1600x900 into 900x1600, which is the 9:16 overlay path")
        XCTAssertEqual(result.message, "Added overlay: stored-landscape.jpg")
        XCTAssertEqual(pixelSize(of: outputDir.appendingPathComponent("stored-landscape.jpg"))?.width, 900)
        XCTAssertEqual(pixelSize(of: outputDir.appendingPathComponent("stored-landscape.jpg"))?.height, 1600)
    }

    /// Control: the same pixels with no orientation tag are genuinely landscape and get bars.
    func testLandscapeWithoutOrientationIsExpanded() throws {
        let source = try writeJPEG(width: 1600, height: 900, named: "landscape.jpg")

        let result = process(source)

        XCTAssertEqual(result.status, .processed)
        XCTAssertEqual(result.message, "Processed: landscape.jpg")
        let size = pixelSize(of: outputDir.appendingPathComponent("landscape.jpg"))
        XCTAssertEqual(size?.width, 1600)
        XCTAssertEqual(size?.height, 1200)
    }

    // MARK: - Aspect ratio routing

    func testExactFourThirdsIsCopiedByteForByte() throws {
        let source = try writeJPEG(width: 800, height: 600, named: "exact.jpg")

        let result = process(source)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.message, "Copied: exact.jpg")
        let input = try Data(contentsOf: source)
        let output = try Data(contentsOf: outputDir.appendingPathComponent("exact.jpg"))
        XCTAssertEqual(input, output, "the 4:3 path must not re-encode")
    }

    /// Regression: an image with no Exif block at all used to be able to fall into the
    /// error path. It should just get an overlay with "N/A" metadata.
    func testNineSixteenWithoutExifGetsOverlay() throws {
        let source = try writeJPEG(width: 900, height: 1600, named: "no-exif.jpg")

        let result = process(source)

        XCTAssertEqual(result.status, .processed)
        XCTAssertEqual(result.message, "Added overlay: no-exif.jpg")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outputDir.appendingPathComponent("no-exif.jpg").path
        ))
    }

    // MARK: - EXIF extraction

    /// ApertureValue and ShutterSpeedValue are APEX-encoded, not f-numbers and fractions.
    func testExifIsConvertedFromApex() throws {
        let exif: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [400],
            kCGImagePropertyExifApertureValue: 1.6959938131099002,   // f/1.8
            kCGImagePropertyExifShutterSpeedValue: 7.965784284662087, // 1/250
            kCGImagePropertyExifFocalLength: 35.0,
            kCGImagePropertyExifLensModel: "Sample 35mm f/1.8"
        ]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFModel: "Sample Camera X1"]

        let url = try writeJPEG(
            width: 900, height: 1600,
            extraProperties: [
                kCGImagePropertyExifDictionary: exif,
                kCGImagePropertyTIFFDictionary: tiff
            ],
            named: "exif.jpg"
        )

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return XCTFail("could not read back the fixture")
        }
        let info = extractExif(from: source)

        XCTAssertEqual(info.iso, "400")
        XCTAssertEqual(info.aperture, "f/1.8")
        XCTAssertEqual(info.shutterSpeed, "1/250")
        XCTAssertEqual(info.focalLength, "35mm")
        XCTAssertEqual(info.camera, "Sample Camera X1")
        XCTAssertEqual(info.lens, "Sample 35mm f/1.8")
    }

    // MARK: - Failure reporting

    /// A missing input must be reported as an error, not silently skipped.
    func testUnreadableInputIsReportedAsError() throws {
        let missing = workDir.appendingPathComponent("does-not-exist.jpg")

        let result = process(missing)

        XCTAssertEqual(result.status, .error)
        XCTAssertTrue(result.message.hasPrefix("Error"))
    }
}
