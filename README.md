# Instagram Utility

A batch image processor for Instagram gallery formatting (4:3 aspect ratio), with EXIF text overlay for portrait shots. Available in two implementations — a Python/PyQt5 original and a native Swift/SwiftUI rewrite optimised for Apple Silicon.

---

## What it does

- Scans a folder for JPEG images
- **9:16 portrait shots** → adds a text + EXIF data overlay (ISO, aperture, shutter speed, focal length, camera & lens)
- **Already 4:3** → copied as-is (Swift version: zero re-encode)
- **Any other ratio** → expands the canvas to 4:3 with white bars
- Outputs everything to a `cropped/` subfolder
- Shows a live progress log, pie chart summary, and per-image processing-time bar chart

---

## Versions

### 🐍 Python (`crop_parallel_UI.py`)

> **Status:** reference implementation, no longer under active development. New work goes into the
> Swift version below.

PyQt5 GUI + Pillow image processing. Uses `ThreadPoolExecutor` for parallelism (limited by the Python GIL on CPU-bound work).

**Requirements**

Python 3.8+ (the EXIF parsing uses the walrus operator).

```bash
pip install -r requirements.txt
```

**Run**
```bash
python crop_parallel_UI.py
# or double-click runCrop.Command
```

---

### 🦅 Swift (`ImageProcessorSwift/`)

Native SwiftUI + Swift Charts rewrite targeting **macOS 14+** and Apple Silicon (M-series). Purpose-built to exploit M4 hardware:

| Concern | Python | Swift |
|---|---|---|
| Parallelism | `ThreadPoolExecutor` + GIL | `TaskGroup` — true multi-core |
| JPEG decode | Pillow | **ImageIO** (hardware decoder) |
| Thumbnail | Full image decode + resize | Embedded EXIF thumbnail via ImageIO |
| 4:3 copy | Re-encodes at quality=100 | `FileManager.copyItem` — zero re-encode |
| EXIF reading | `getexif()` | `CGImageSourceCopyPropertiesAtIndex` |
| Text overlay | Pillow draw | Core Graphics + Core Text |
| Settings | `settings.json` next to script | `~/Library/Application Support/` |
| UI | PyQt5 + matplotlib | SwiftUI + Swift Charts (native, dark mode) |

**Requirements**
- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

**Run (dev)**
```bash
./run_swift.sh
```

**Build a double-clickable `.app`**
```bash
./build_swift_app.sh
# Opens ImageProcessor.app when done
```

**Build manually**
```bash
cd ImageProcessorSwift
swift build            # debug
swift build -c release # optimised
```

**Run tests**
```bash
cd ImageProcessorSwift
swift test
```

---

## Project structure

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
        └── ProcessingTests.swift    # Orientation, aspect-ratio routing, failure reporting
```

---

## Known limitations

- **JPEG only.** HEIC (the iPhone default) and RAW are not read.
- **macOS only.** The Swift version targets macOS 14+; the Python version may work elsewhere but is
  untested outside macOS.
- **The Swift app overwrites the output folder.** Every run clears the existing `cropped/`
  directory without asking. The Python version asks first.
- **Not signed or notarised.** If you build the `.app` yourself that's fine; downloading a
  pre-built one would hit Gatekeeper.

---

## License

MIT — see [LICENSE](LICENSE).

