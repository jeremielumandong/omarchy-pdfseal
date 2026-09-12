# omarchy-pdfseal

PDFSeal is a native Omarchy PDF editor: QML controls and canvas, a Rust worker,
Poppler for page rendering, and qpdf for document transformations. It runs
locally without a browser, web server, Node.js runtime, or network requests.

The interface binds directly to Omarchy's shared `Color`, `Style`, `Button`
and `TextField` components. Theme changes update the editor's colors, fonts
and controls. Document paper and ink retain their actual colors.

## Native features

- Draw, type or import signatures, with Script, Casual and Formal fonts; use eight stamp presets.
- Add and edit text, comments, ink, highlights and boxes; move, resize, delete, undo and redo.
- Use a draggable color picker or sample colors directly from the PDF.
- Find text and cover/retype existing PDF text with approximate fonts.
- Rotate, reorder, remove, duplicate, extract, split, merge and crop pages.
- Add watermarks and page numbers; convert images to PDF and export PDF pages as PNG/JPEG.
- Preview lossless, image and Compact compression before saving or replacing the document.
- Fill interactive text, checkbox, radio and dropdown fields, or detected flat-form boxes and underlines; flatten forms.
- Recognize English text locally with OCR.
- Apply content-removing redaction with verification; keep attachments only when explicitly selected.
- Export a new PDF with optional AES-256 protection, preserving the original file.
- Pinch or Ctrl+wheel to zoom, and follow Omarchy theme changes automatically.

Certificate-based digital seals, recipient fields, handoff packages are still being ported. Drawn and typed signatures
are visual annotations. Office conversion is unavailable in the reference
Privseal implementation. Text annotations support Windows-1252 characters;
comments support Unicode.

## Install

Requires Omarchy's Quickshell plugin system, `qpdf`, `poppler`, and Python 3
for installation. Install missing PDF dependencies with:

```sh
omarchy pkg add qpdf poppler
# For local English OCR:
omarchy pkg add tesseract tesseract-data-eng
```

For local testing, build version **1.0.0** from source with a Rust toolchain:

```sh
git clone git@github.com:jeremielumandong/omarchy-pdfseal.git
cd omarchy-pdfseal
bash scripts/build.sh
python3 scripts/install.py
```

An archive created locally with `scripts/package.sh` includes the compiled
worker and can be installed directly with `python3 scripts/install.py`.

The installer copies the plugin to
`$XDG_CONFIG_HOME/omarchy/plugins/arkane.pdfseal` (normally
`~/.config/omarchy/plugins/arkane.pdfseal`), creates the PDFSeal desktop entry,
rescans plugins and enables the bar widget. Existing installations are backed
up under `$XDG_STATE_HOME/omarchy-pdfseal/backups`.

Click **PDFSeal** in the bar or application launcher. Open a PDF, select a
tool, and draw or click on the page. **Select** lets you drag an existing mark.
Clicking the bar button again focuses the existing editor, including from
another workspace, while keeping your document and edits open.

For text, choose **Text**, click where it belongs, and type directly on the
page. The tool returns to **Select**. Double-click existing text (or click
**Edit selected text**) to change its value. **Enter** or clicking away saves;
**Escape** cancels; **Shift+Enter** adds a line. Empty text is discarded.
Choose **Sans / Serif / Mono**, ink color, and **A− / A+** in the sidebar.
Each finished text edit is a single undo step.

**Signature** offers Draw, Type (Script / Casual / Formal), and local image
import. Signature images keep transparency and remain reusable for this
session. **Stamp** offers the same eight presets as Privseal, including dated
Received and Approved. Drag a placed signature/stamp and resize with its
bottom-right handle. Image input supports PNG, JPEG and WebP up to 32 MB and
8192 pixels per side; prepared signatures are capped at 4096 pixels.

**Export PDF** saves a new copy. An empty export password creates an
unencrypted file, including when the input was encrypted.

Shortcuts: `Ctrl+O` open, `Ctrl+S` export, `Ctrl+Z` undo,
`Ctrl+Shift+Z` redo, and `Delete` remove the selected annotation.

```sh
omarchy bar move arkane.pdfseal --section right
omarchy-shell shell summon arkane.pdfseal '{}'
```

**Right-click PDFSeal in the bar** to open the display menu and choose
**Icon only** or **Text only**. Your choice is saved in Omarchy's bar settings.
The document/signature icon follows the bar's
theme colors. Vertical bars use the compact icon. You can also switch with:

```sh
omarchy bar set arkane.pdfseal displayMode icon
omarchy bar set arkane.pdfseal displayMode text
omarchy bar set arkane.pdfseal displayMode both
```

This source repository includes a Rust crate. `omarchy plugin add` clones
source without running build hooks, so use the installer after building or
unpacking a local archive. See the [Omarchy plugin contract](https://github.com/basecamp/omarchy/blob/quattro/shell/README.md).

## Document tools

**Tools** operates on the document including your edits. Page transformations
clear annotation undo history, matching Privseal; export a copy to save the
result. Split and image exports create a new subfolder without overwriting
existing files. Cancel stops active rendering or OCR and keeps the open PDF.

**Edit PDF text** covers the selected line in white and writes its replacement
with an approximate standard font. The old text remains embedded. **Redact**
removes content: mark regions and choose **Apply true redaction**, or export.
Affected pages are rebuilt at 300 DPI and lose text selection. Verification
refuses output if covered text still occurs elsewhere. Attachments are removed
by default; the redaction tool exposes an explicit keep option.

**Compress** previews before/after size. Lossless preserves quality; Smaller
images recompresses eligible images; Compact converts pages to 120 DPI JPEG
images and removes text selection, links and form interactivity. **OCR** uses
the local Tesseract English model to add an invisible searchable layer.

## Build and distribute

Developers need a Rust toolchain (edition 2024) in addition to the runtime
dependencies. From this folder:

```sh
bash scripts/build.sh
python3 scripts/install.py
```

To create an Omarchy plugin archive for the build machine's CPU:

```sh
bash scripts/package.sh
```

This produces `release/omarchy-pdfseal-1.0.0-linux-x86_64.tar.gz` (or the
current architecture) plus a SHA-256 checksum. Users do not compile code.
Build on an Omarchy/Arch machine for an Omarchy release. It relies on the
host's Omarchy, Qt, libc, qpdf and Poppler packages; it is not a general Linux
AppImage. The plugin has no auto-updater; install a new version to update it.
Export and close open documents before updating plugin code.

## Resource use and privacy

The bar widget loads its editor only on first use. The Rust process starts
when a document opens, then exits when the editor closes. PDF parsing and
Poppler rendering happen outside the shell's UI thread.

Only the current page is decoded by QML. Previews are rendered on demand,
debounced, capped at 2600 pixels on the longest side, and cached for the most
recent 12 page/size combinations. Returning to a cached page avoids rendering
it again. Large or complex PDFs can still take time to parse or render.

The worker keeps a snapshot and previews in a private `pdfseal-*` directory
under `$XDG_RUNTIME_DIR` (or the system temporary directory when unavailable).
Normal worker exit removes it. An abnormal termination can leave temporary
files until session cleanup. Export writes a temporary file in the destination
folder and renames it into place after qpdf succeeds. Passwords travel over
stdin, not command-line arguments.

## Verify

```sh
cargo test --locked --manifest-path native/Cargo.toml
bash scripts/build.sh
bash tests/ui-smoke.sh
python3 tests/geometry-smoke.py
python3 tests/jobs-smoke.py
python3 -m unittest discover -s tests -p '*_test.py'
```

Native tests cover crop/rotation geometry, preview caching, text and ink
export, page order, encryption, original-file preservation and cleanup.
The UI smoke test needs a running Hyprland session and QtTest. It checks a
fixture PDF, icon/text modes, theme bindings, real clicks and typing, text
resizing and undo/redo, cross-workspace focus without losing edits, and export.

## Remove

Export any unsaved work, close PDFSeal, then:

```sh
python3 ~/.config/omarchy/plugins/arkane.pdfseal/scripts/uninstall.py
```

Exported PDFs and installation backups are preserved.

Pinch the PDF to zoom, or use Ctrl+mouse wheel. Clicking an object gives it keyboard focus: Delete or Backspace removes it, and Undo restores it. Normal PDFs open immediately; the password dialog appears only when the PDF requires a password.

**Custom color…** opens a movable picker with a draggable shade area, hue slider and hex input. Choose **Eyedropper from PDF**, then click the page to match its color. The chosen color updates selected text or becomes the ink for new text and drawings; Escape cancels sampling.

**Fill forms** shows interactive fields in Select mode. Text edits are grouped into one undo step. Read-only fields remain locked. When no interactive fields exist, PDFSeal detects light boxes and underlines on unrotated vector pages; this is a heuristic, so use Text for missed regions. Export keeps interactive fields editable; **Tools → Flatten forms** makes their appearances permanent.
