# Stratum — Native macOS File Manager & Storage Analyzer

**Stratum** is a high-performance native macOS 14+ file manager, disk storage analyzer, and build-artifact cleaner written in Swift (SwiftUI + AppKit) powered by low-level BSD `getattrlistbulk(2)` directory scanning, APFS `copyfile(3)` CoW cloning, `FSEvents`, and an indexed SQLite (`GRDB`) storage engine.

---

## Quick Start (Build & Launch)

### 1. Build & Launch from Terminal (One-Liner)

```bash
xcodebuild -project Stratum.xcodeproj -scheme Stratum -configuration Debug -destination 'platform=macOS' build && \
open ~/Library/Developer/Xcode/DerivedData/Stratum-*/Build/Products/Debug/Stratum.app
```

### 2. Relaunch Existing Build Immediately

If you have already built Stratum and just want to launch (or restart) the app:

```bash
killall Stratum 2>/dev/null || true
open ~/Library/Developer/Xcode/DerivedData/Stratum-*/Build/Products/Debug/Stratum.app
```

### 3. Build a Release Binary & Copy to `/Applications`

```bash
xcodebuild -project Stratum.xcodeproj -scheme Stratum -configuration Release -destination 'platform=macOS' build && \
cp -R ~/Library/Developer/Xcode/DerivedData/Stratum-*/Build/Products/Release/Stratum.app /Applications/
open /Applications/Stratum.app
```

### 4. Open & Run in Xcode

```bash
open Stratum.xcodeproj
```
Then press **`⌘R`** to build and run, or **`⌘U`** to run the unit test suite.

---

## Running Tests & Project Maintenance

### Run All Unit & Performance Tests

```bash
xcodebuild -project Stratum.xcodeproj -scheme Stratum -destination 'platform=macOS' test
```

### Regenerate `Stratum.xcodeproj` (via XcodeGen)

If you add/remove files or edit `project.yml`, regenerate the Xcode project with:

```bash
xcodegen generate
```

---

## Core Features

- **Fast Browser (`getattrlistbulk` + AppKit `NSTableView` / `NSCollectionView`):**
  - **Icon Grid (`⌘1`)**, **List View (`⌘2`)**, and **Column View (`⌘3`)** with full ancestor horizontal scroll & interactive **Column Jump Strip**.
  - Streaming directory loader (`first 200 items < 16 ms`) with live `FSEvents` monitoring.
  - **Multi-Tab Bar** (`⌘T` new tab, `⌘W` close tab), **Path Breadcrumb Bar**, **Unified Back/Forward Navigation History** across folders, Workspace Modes, Smart Folders, and Tag filters, plus a **Floating Multi-Select Batch Action Bar**.
- **Rich Right-Click Context Menus Everywhere:**
  - `Open`, dynamic **`Open With…`** (lists all compatible macOS apps with icons), `Open in New Tab`, `Open in Smart Organizer`, `Quick Look (Space)`.
  - **`New Folder`**, **`New Folder with Selection`**, and **`New File`** templates (`.md`, `.txt`, `.json`, `.py`, `.sh`, `.swift`).
  - **Finder Tags (`kMDItemUserTags` xattr):** `Urgent`, `Client`, `Draft`, `Final`, `Review`, `Archive` with 2-column sidebar filter grid and wrapping tag badges.
  - **Developer Tools:** `Open in Terminal`, `Copy Path`, `Copy Filename`, `Copy Shell-Escaped Path`, `Copy SHA-256 Checksum`, `Toggle Executable (chmod +x)`, `Scan Folder in Storage Map`.
- **Inspector Sidebar (`⌘I`):**
  - Live **Code & Text Snippet Preview** for source files, `QLThumbnailGenerator` previews, 2×4 quick action buttons, POSIX permission bits (`rwxr-xr-x (755)`), and Finder Tags editor.
- **Smart Clean & Organizer (`SmartOrganizerView`):**
  - **1-Click Category Folder Organizer:** Groups loose files in `~/Downloads`, `~/Desktop`, `~/Documents`, or any chosen folder into categorized buckets (`Documents & PDFs`, `Photos & Images`, `Installers`, `Archives`, `Screenshots`, `Videos & Media`, `Code & Scripts`)—nothing moves automatically; click any category to create its folder and move files, with 1-click **Unpack** and **Undo**.
  - **SHA-256 Verified Duplicate File Finder:** Finds byte-identical files across your workspace and lets you keep the original while trashing redundant copies.
  - **Drop Shelf & Batch Stash:** Park files from multiple folders and copy, move, or archive them all at once.
- **Storage Map (`StorageMapView`):**
  - Parallel `getattrlistbulk` recursive tree scanner with APFS hardlink deduplication, package (`node_modules`, `.app`, `.xcodeproj`) sizing, **Translucent Glass Bento Grid** category cards with neon border glow, largest files drill-down, and 1-click trash cleanup.
- **Groups by Name (`GroupsByNameView`):**
  - Aggregates repeated build/dependency folders across your projects (`node_modules`, `target`, `.next`, `.build`, `DerivedData`, `.venv`, `dist`, `__pycache__`) with staleness badges, live search filter, batch selection pills (`Select All Visible`, `Select > 100 MB`), and 1-click **Move to Trash** with undo/restore.
- **Command Palette (`⌘K`) & VS Code–Style Glass Theme Studio (`⌘,`):**
  - Fuzzy search + Spotlight (`NSMetadataQuery`) + quick actions (`> theme`, `> scan`, `> new folder`).
  - 9 built-in translucent glass themes (**Stratum Emerald Glass**, **Tokyo Night Glass**, **Catppuccin Mocha Glass**, **Cyberpunk Matrix**, **Dracula Vivid Glass**, **Rosé Pine Moon**, **Nordic Frost Glass**, **Solarized Amber Glass**, **Daylight Frosted Quartz**), full live customization of **Window/Sidebar/Card Glass Tints**, **Accent Color**, **Blur Material**, **Translucency (0–100%)**, and **Neon Border Glow**, plus **Save as Custom Theme**.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌘1` / `⌘2` / `⌘3`** | Switch Browser to **Grid** / **List** / **Column** View |
| **`⌘K`** | Open **Command Palette & Spotlight Search** |
| **`⌘T`** | New Browser Tab |
| **`⌘I`** | Toggle **Inspector Sidebar** |
| **`⌘,`** | Open **Appearance & Glass Theme Studio** |
| **`Space`** | Native macOS **Quick Look Preview** |
| **`⌘[` / `⌘]` / `⌘↑`** | Back / Forward / Enclosing Folder (or Exit Workspace Mode / Smart Folder) |
| **`⌘⇧.`** | Toggle Hidden Dotfiles |
| **`⌘⌫`** | Move Selected Items to Trash |
| **`⌘Z`** | Undo Last Move to Trash |
