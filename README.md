# Instagram Utility

[![build](https://github.com/merajc/Instagram-Utility/actions/workflows/build.yml/badge.svg)](https://github.com/merajc/Instagram-Utility/actions/workflows/build.yml)

A small macOS app that turns a folder of mixed-aspect-ratio photos into a set that fits an
Instagram gallery grid.

Instagram crops every grid preview to 4:3. Upload a mix of portrait and landscape shots and the
tiles come out inconsistent. This tool fixes that before you upload: it pads each photo onto a
white 4:3 canvas, leaves photos that are already 4:3 untouched, and gives 9:16 portrait shots a
text overlay of their EXIF camera settings.

There are two implementations: a native Swift/SwiftUI app (the one to use) and the original
Python/PyQt5 script it grew out of.

---

## What it does to each photo

| Photo | What happens |
|---|---|
| **9:16 portrait** (0.5625 ± 0.0002) | Text overlay: your caption, camera + lens, and ISO / aperture / shutter speed / focal length |
| **Already 4:3** (within 0.001) | Swift copies the file byte-for-byte; Python re-encodes at quality 100 |
| **Any other ratio** | Centred on white, canvas expanded to 4:3 |
| **Has an EXIF rotation tag** | Rotated to the orientation it was shot in *before* any of the above, so portrait photos measure as portrait |

Output goes to `cropped/` inside the folder you picked. Anything already in `cropped/` is removed
at the start of a run (the Python version asks first; the Swift version doesn't).

Only files directly inside the chosen folder are processed — subfolders are not scanned.

---

## Requirements

**Swift version** — macOS 14 (Sonoma) or later, plus Xcode Command Line Tools:

```bash
xcode-select --install
```

**Python version** — Python 3.8 or later. The EXIF code uses the walrus operator.

```bash
pip install -r requirements.txt
```

---

## Run it

### Swift (recommended)

```bash
./run_swift.sh
```

To build a double-clickable app in the repo root:

```bash
./build_swift_app.sh    # builds release, creates ImageProcessor.app, opens it
```

Or build manually:

```bash
cd ImageProcessorSwift
swift build -c release
```

### Python (legacy)

```bash
python3 crop_parallel_UI.py
# or double-click runCrop.Command
```

Still functional, no longer developed. Bug fixes that matter land in the Swift version.

---

## Using it

1. **Select Folder** — the folder of JPEGs you want to prepare.
2. **Overlay Text** — the caption printed on 9:16 portraits. Saved between sessions.
3. **Text Height / Margin** — both as a percentage of the image dimensions; these only affect the
   overlay.
4. Watch the log, the progress bar, and when it finishes: a summary donut, a per-image timing
   chart, and CPU/memory figures in the Python version.

Both versions show the same results, with one difference worth knowing: a file that is already
4:3 is *copied* by the Swift version (no generation loss) and *re-encoded* by the Python version.

---

## What the overlay looks like

Three lines, bottom-left, white text with a 4px black outline:

```
France, January 2026
Sony A7 IV + FE 35mm F1.8
ISO 400 | f/1.8 | SS 1/250 | 35mm
```

Missing EXIF renders as `N/A` rather than hiding the line, so the overlay stays aligned across a
batch. Text size and margin are percentages of image height, so the overlay scales with resolution.

---

## Verifying it works

```bash
cd ImageProcessorSwift
swift test
```

Six tests, covering: EXIF orientation deciding the aspect ratio, the landscape and 9:16 branches,
byte-for-byte copying of exact 4:3, overlay on a photo with no EXIF at all, APEX-to-f-number
conversion, and unreadable input being reported as an error rather than silently skipped.

CI runs the same suite, a release build, and a Python syntax check on every push to `main` and on
every pull request.

---

## The two implementations

|  | Swift (current) | Python (legacy) |
|---|---|---|
| UI | SwiftUI + Swift Charts | PyQt5 + matplotlib |
| Parallelism | Task group, bounded to the core count | `ThreadPoolExecutor`, limited by the GIL |
| EXIF | ImageIO | Pillow `getexif()` |
| Already-4:3 files | Copied, no re-encode | Re-encoded at quality 100 |
| Settings | `~/Library/Application Support/ImageProcessorSwift/settings.json` | `settings.json` next to the script |
| Tests | 6 | none |

---

## Project layout

```
Instagram-Utility/
├── crop_parallel_UI.py              # Python/PyQt5 version
├── requirements.txt                 # Python dependencies
├── settings.json                    # Python settings (persisted)
├── runCrop.Command                  # macOS double-click launcher (Python)
├── run_swift.sh                     # Dev launcher (Swift)
├── build_swift_app.sh               # Release .app builder (Swift)
└── ImageProcessorSwift/
    ├── Package.swift
    ├── Sources/ImageProcessorSwift/
    │   ├── ImageProcessorApp.swift  # @main SwiftUI entry point
    │   ├── Models.swift             # Shared types & AppSettings
    │   ├── ImageProcessor.swift     # Core processing + ImageProcessingService actor
    │   ├── ViewModel.swift          # @MainActor @Observable state
    │   ├── ContentView.swift        # Main SwiftUI layout
    │   └── ChartView.swift          # Swift Charts (pie + bar + hover tooltip)
    └── Tests/ImageProcessorSwiftTests/
        └── ProcessingTests.swift    # Orientation, ratio routing, EXIF, failure reporting
```

---

## Known limitations

- **JPEG only.** HEIC (the iPhone default) and RAW are not read.
- **Top level only.** Subfolders are not scanned.
- **The Swift app overwrites `cropped/` without asking.** The Python version confirms first.
- **macOS only.** The Swift app targets macOS 14+; the Python version is untested elsewhere.
- **Not signed or notarised.** Building the `.app` yourself is fine; a pre-built binary would hit
  Gatekeeper.

---

## Licence

MIT — see [LICENSE](LICENSE).
