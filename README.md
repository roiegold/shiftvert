# Shiftvert

**Drag. Hold ⇧. Done.**

**[shiftvert.com](https://shiftvert.com)** · free and open source · macOS 14+

A tiny Mac menu-bar app: **start dragging files, then hold ⇧ Shift** and a wheel of formats appears around the cursor. Tap **⌥ Option** mid-drag to switch to tools (compress, trim, zip…), and ⇧ to switch back. Drop the file on an option and the converted copy appears next to the original. Everything happens on your Mac — nothing is uploaded, and the app has no network code at all.

No Shift-drag? Use the menu-bar icon → **Convert Files…** and click an option instead.

## What it can do

| Files | Options |
|---|---|
| Images (PNG, JPG, HEIC, TIFF, GIF, WebP…) | PNG · JPG · HEIC · TIFF · GIF · BMP · AVIF (if your Mac can write it) · PDF · Compress (saves a smaller JPG, or HEIC if it has transparency) · Resize 50% · Crop (drag the box, aspect ratios, size in % or exact pixels) · Strip EXIF (removes GPS location etc.) · Merge PDF (2+ images into one PDF) |
| Video (MOV, MP4, M4V; AVI if QuickTime Player can play it) | MP4 · MOV · M4V · GIF (first 15 s) · M4A (audio) · Compress (720p) · Trim |
| Audio (MP3, WAV, AIFF, M4A, FLAC…) | M4A · WAV · AIFF · FLAC · Compress · Trim |
| PDF | Pages → PNG/JPG · TXT · Compress · Split pages · Merge |
| Documents (Word, RTF, ODT, HTML, TXT, Markdown as plain text) | PDF · DOCX · RTF · TXT · HTML · ODT |
| Anything (incl. folders) | Zip |

Originals are never changed or overwritten; results get names like `photo compressed.jpg` or `photo 2.png`.

## Install

1. Download `Shiftvert.zip` from [shiftvert.com](https://shiftvert.com). Safari unzips it for you; in Chrome, click it in the downloads list.
2. Drag **Shiftvert** from Downloads into **Applications** in the Finder sidebar, then double-click it there.
3. macOS says Apple couldn't check it for malware (it isn't registered with Apple's paid developer program). That's expected: click **Done** (or **OK**), not Move to Trash.
4. Open **Apple menu → System Settings → Privacy & Security**, scroll to the bottom and click **Open Anyway** next to “Shiftvert” was blocked, then confirm with Touch ID or your password. If macOS asks once more, click **Open Anyway** again. The button only shows for about an hour after you try to open the app. You do this once per download, so again after an update. You never need Terminal, `sudo` or to turn off Gatekeeper.
5. A welcome note explains the gesture and has an **Open Shiftvert at login** checkbox, and a ⟳ icon stays in the menu bar. If you can't see it (a crowded menu bar or the notch can hide it), open Shiftvert again and its menu appears at the pointer.
6. Start dragging a file, then hold ⇧ Shift. The first time you convert something on the Desktop or in Documents or Downloads, macOS may ask to let Shiftvert use that folder; allow it so results can be saved next to your files.

### Check your download

Each [release](https://github.com/roiegold/shiftvert/releases/latest) lists the SHA-256 checksum of `Shiftvert.zip`. To compare, run `shasum -a 256 ~/Downloads/Shiftvert.zip` in Terminal (the checksum is for the .zip, so check it before Safari unzips it, or download with another browser).

## Website & releases

The download page lives in [`docs/`](docs/index.html) and is served by GitHub Pages (Settings → Pages → *Deploy from a branch* → `main` / `/docs`). Its download button always points at the newest release's `Shiftvert.zip`, so shipping an update is:

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist` and the "latest version" in the site's Updating note (`docs/index.html`, `id="update"`), then run `./build.sh`.
2. On GitHub: Releases → *Draft a new release* → tag like `v1.1` → attach `dist/Shiftvert.zip` (keep that exact file name) → in the notes, write "Download **Shiftvert.zip** under Assets (not Source code)" and paste the checksum from `dist/Shiftvert.zip.sha256` → Publish.

## Build it yourself

Building needs macOS 15.6 or later with Apple's Command Line Tools 26 (`xcode-select --install`), because the code uses the macOS 26 SDK; Xcode isn't required. The app you build runs on macOS 14 or later.

```bash
./build.sh
```

This produces `dist/Shiftvert.app` (runs on Apple Silicon and Intel), `dist/Shiftvert.zip` to share and its checksum in `dist/Shiftvert.zip.sha256`. Debug symbols are stripped, so the app doesn't carry your Mac's folder paths, and the build stops if it ever would.

Test any conversion from Terminal without the UI:

```bash
swift build
.build/debug/Shiftvert --list photo.heic
.build/debug/Shiftvert --run JPG photo.heic
.build/debug/Shiftvert --run Trim --range 0:05-0:20 clip.mov
```

Record the product video (a scripted, beat-synced demo of the real wheel; your terminal needs Screen Recording permission). The recorder is only in demo builds, so the app people download has no screen-recording code:

```bash
./build.sh demo                                                                 # dist/demo/Shiftvert.app
dist/demo/Shiftvert.app/Contents/MacOS/Shiftvert --demo /tmp/shiftvert-demo.mov      # 9:16
swift scripts/export-video.swift /tmp/shiftvert-demo.mov video/Shiftvert-demo-vertical.mp4
dist/demo/Shiftvert.app/Contents/MacOS/Shiftvert --demo /tmp/wide.mov --wide          # 16:9 for the website
swift scripts/export-video.swift /tmp/wide.mov docs/demo.mp4 1280 720 1.6       # small copy for the website
```

The demo needs macOS 15+ (ScreenCaptureKit). It records only Shiftvert's own windows, with its original synthesized soundtrack.

## Updates

Shiftvert never checks for updates on its own (it has no network code). Use the menu-bar icon → **Check for Updates…** to see the latest version on [shiftvert.com](https://shiftvert.com/#update), and download it again to update: quit Shiftvert from its menu first, replace the app in Applications, then approve it with **Open Anyway** again.

## Security notes

- Uses only Apple's built-in frameworks and tools (`ImageIO`, `AVFoundation`, `PDFKit`, `/usr/bin/afconvert`, `/usr/bin/textutil`, `/usr/bin/ditto`). It has no third-party code and no network access.
- Tools are started directly, never through a shell, so a weird file name can't run commands.
- Needs no Accessibility or Full Disk Access. macOS may ask once to allow Shiftvert to use the Desktop, Documents or Downloads folder, so results can be saved next to your files. It only reads the dragged files while Shift is held.
- The downloadable app has no screen-recording code and no debug symbols; the product-video recorder is only in `./build.sh demo` builds.
- Signed ad-hoc with the hardened runtime. To get rid of the "unverified developer" warning, you'd need an Apple Developer ID ($99/yr) and notarization.

## Limits

- MP3 and WebP *output* aren't possible with Apple's built-in encoders (input works). AVIF output shows up only if your Mac can write it.
- No MKV or WebM. AVI only if QuickTime Player can play it.
- Markdown is converted as plain text: the markup isn't rendered.
- Word and ODT files with pictures can only become TXT: macOS's built-in converter would leave the pictures out.
- Right-to-left text (Hebrew, Arabic) pulled from PDFs can come out in the wrong order. Shiftvert spots this for Hebrew and says so instead of saving scrambled text.
- Drags that aren't real files (images dragged out of a browser or Photos) don't trigger the wheel. Save the file first.
- Pick the file up first, then press ⇧. Holding ⇧ before you click is Finder's shortcut for adding files to the selection, so the drag would carry extra files (Shiftvert leaves out the one you just converted). To convert several files on purpose, select them with ⌘-click.
