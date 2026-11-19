# Build prompt: Stratum, a native macOS file manager

I want you to build a native macOS file manager. The working name is "Stratum" (a placeholder, feel free to keep it out of anything hard to rename). I've attached `stratum-design.html`, a clickable design prototype of the whole app. I also have an existing app, wimys_crumb, whose disk-scanning engine should be reused for two of the features. Both are described below.

This is a large project, so please start by reading the design file and the wimys_crumb engine, then give me a short plan with milestones before writing code. Ask me about anything that is ambiguous instead of guessing.

## What I'm after

A file manager I'd use every day in place of Finder: fast, keyboard-friendly, and good-looking in the way the best Mac apps are. It should feel like it belongs on macOS, not like a web app in a window. Smoothness matters more to me than feature count. The app must never beachball, including while scanning a 500 GB disk or opening a folder with 100,000 items.

## Tech choice

Use Swift, with SwiftUI for most of the interface and AppKit where SwiftUI is too slow or too limited. I considered Rust and Go and decided against both, for these reasons:

- The things that make a Mac file manager feel right are all Apple frameworks: window materials and vibrancy, the system accent color, Quick Look, the Trash, Finder tags, drag and drop with file promises, FSEvents, Spotlight metadata. From Swift these are direct calls. From Rust or Go each one needs a bridge, and the UI toolkits available there don't look or behave natively.
- wimys_crumb is already Swift, so its engine can be reused as source instead of being ported.
- Raw speed isn't the constraint. The slow part of a file manager is filesystem calls, and Swift can call the same low-level APIs (`getattrlistbulk`, `fts`) that Rust or Go would.

Where SwiftUI struggles, drop to AppKit without asking: the file list and icon grid for large folders (`NSTableView` / `NSCollectionView` with cell reuse), and anything needing precise drag-and-drop or keyboard handling. Use `xcodegen` with a `project.yml` the way wimys_crumb does, so the project file isn't hand-edited. Target macOS 14 or later unless you see a reason to go newer, and tell me if you do.

The app needs to read the whole disk, so it can't be sandboxed in the Mac App Store sense. Plan for Developer ID distribution, and include a first-run screen that explains Full Disk Access and links to the right System Settings pane.

## The design file

`stratum-design.html` is a single self-contained prototype. Open it in a browser and click through every screen first (the sidebar's Tools section switches screens, and the search field opens the command palette). Then read its source as a spec:

- The markup inside `<template id="tpl">` is the layout. Every size, radius, spacing value and color is in an inline `style`. Treat those as the intended measurements, then translate them to native controls. Don't embed a web view.
- `{{name}}` placeholders are filled from the `renderVals()` method of the `Component` class in the last `<script>`. The short script before it is only a renderer for this file, so ignore it. The `Component` class also holds the sample data and the interaction logic (what selecting, toggling and navigating do), so read it to understand behavior.
- The file contains all screens in one window. Each is a container whose `display` is switched by a `screen` value: `browser`, `split`, `groups`, `storage`, `settings`, plus a command palette overlay.

The screens are:

- **Browser.** Sidebar (favorites, tools, smart folders, locations with eject, tags, disk usage card), toolbar (back/forward, path bar, view switcher, new folder, split, share, tags, transfer progress, search), tabs, an icon grid and a list view grouped by kind, an inspector with preview, metadata, tags and versions, and a status bar with the path and selection size.
- **Dual pane.** Two independent panes side by side, a list with expandable folders on the left and column view on the right. A batch bar appears when items are selected (copy to other pane, move, batch rename, compress, trash). There is a "shelf" for parking files to drop elsewhere later, and a transfers panel with progress, speed, pause, cancel, undo and conflict review.
- **Command palette (Cmd-K).** One field for finding files by name or by content, with filter chips (kind, date), running actions, and jumping to screens. It has a preview column and keyboard hints.
- **Groups by name.** Described below.
- **Storage map.** Described below.
- **Settings, Appearance.** Theme, accent, translucency, blur, density.

Sample file names, sizes and dates in the design are invented. Not every button in the prototype is wired up, so where behavior isn't shown, do what a Mac user would expect and tell me what you chose.

## Appearance: please deviate from the design here

The prototype draws a dark indigo wallpaper behind the window and fills buttons and selections with an indigo-to-violet gradient. Both were stand-ins. In the real app:

- **No built-in background or gradient.** The window uses real macOS materials (`NSVisualEffectView` or the SwiftUI equivalents) so the user's actual desktop shows through the sidebar and toolbar, the way it does in Finder, Notes or Xcode. The content area is more opaque than the sidebar so file names stay readable.
- **Accent comes from the system by default.** Use `NSColor.controlAccentColor` and follow changes live. Selections, the active sidebar row, progress bars, primary buttons and (optionally) folder icons take that color as a solid fill, not a gradient.
- **Settings offers alternatives:** follow system (default), pick from a palette of about 20 colors, enter a custom color, or "match wallpaper", which samples the current desktop picture and picks one harmonious accent from it. If you think a subtle two-tone treatment looks good for the wallpaper option, show me, but keep it restrained. The gradient colors in the prototype are not a brief.
- **Follow system light and dark mode**, with an override in Settings. The prototype only shows dark. Derive the light version from the same structure.
- **Respect Reduce Transparency and Increase Contrast.** Keep text at readable contrast over any wallpaper.

The goal is that it looks like a first-party Mac app that someone cared about a lot: restrained, with the color coming from the user's own desktop and accent choice.

## Groups and Storage map: reuse wimys_crumb

Repository: https://github.com/AbyAbyss/wimys_crumb (Swift, SwiftUI, GRDB/SQLite). Clone it and read `wimys_crumb/Engine/` and `wimys_crumb-implementation-plan.md` before designing these two features.

**Groups by name** finds folders that share a name across the disk (`node_modules`, `.venv`, `DerivedData`, `target`, `Pods`, `Caches`, `__pycache__` and so on), totals them, and shows them as a bubble chart next to a list. Clicking a bubble expands that group in the list to show each folder's path and size. Folders or whole groups can be ticked, a "Stale only" filter narrows to groups not touched recently, and "Free X GB" moves the selection to the Trash with Undo. The design file shows the layout, and `GroupsView.swift` in the repo shows the existing behavior, including a confirmation sheet for large cleanups.

**Storage map** shows what's using a disk: a treemap of the top-level categories or folders that you can click into, the largest items in the selected block, and a cleanup list (duplicates, old downloads, large unused files, Trash, caches) with a running total.

I've read through the engine. The architecture is sound and is the reason that app doesn't hang, so please keep it:

- The scan is a streaming walk inside an actor that writes directories to SQLite in batches of 2,000 and keeps no per-file objects in memory. Memory stays flat regardless of disk size.
- Progress is throttled to about one update per 100 ms, and pause and cancel are checked every 256 entries.
- Folder totals are rolled up afterwards in SQL, bottom-up by depth, using indexes on parent, name and depth.
- Groups are a query on the indexed `name` column against a catalog of known names (`GroupCatalog.swift`). Adding a name needs no schema change.
- Large files are kept in bounded per-type heaps instead of storing every file.
- Deletes go through `DeleteService.swift`, which refuses protected system paths, uses the Trash, and can restore.

Reuse `ScanDatabase`, `ScanDatabaseQueries`, `Aggregator`, `GroupCatalog`, `BoundedMinHeap`, `FileTypeClassifier`, `DeleteService` and the treemap layout as a starting point. A few things in the walker are worth checking and probably improving. Measure before and after on a real disk and tell me the numbers:

- **Package contents.** The enumerator is created with `.skipsPackageDescendants`. As far as I can tell that means files inside `.app` bundles, photo libraries and similar packages are never visited, so those would show as near zero bytes. Please verify, and if so, walk into packages for sizing while still displaying them as single items.
- **Walker speed.** It uses `FileManager.enumerator` with `URLResourceValues` on a single task, and builds a standardized path string for every entry to work out depth. `getattrlistbulk` (or `fts`) fetches a whole directory's attributes in one call and is typically several times faster. Consider that, with a few worker threads walking subtrees in parallel and one writer feeding SQLite.
- **Where the loop runs.** The hot loop runs on the Swift concurrency pool with `Task.yield()`. A long blocking loop is better on its own thread or dispatch queue so it can't starve other async work.
- **Double counting.** Hard links and APFS clones are counted once per path. Dedupe hard links by inode at least.
- **Staying fresh.** After the first scan, use FSEvents to rescan only the subtrees that changed instead of the whole disk.

If after reading it you think a different design would be better, tell me why before changing direction.

## Performance requirements

These are the reasons the app exists, so please treat them as acceptance criteria and measure them:

- Nothing touches the filesystem on the main thread. Directory listing, sizing, thumbnails, search and scanning all happen off it and deliver results in batches.
- A folder with 100,000 items opens with the first rows visible almost immediately and scrolls at full frame rate. That means lazy, reused cells and attributes fetched in bulk.
- Thumbnails and Quick Look previews load asynchronously, are cached, and are cancelled when their cell scrolls away.
- Copy, move and delete run in a queue with progress, pause, cancel and conflict handling, and never block browsing.
- A full-disk scan keeps memory flat and the UI responsive throughout, and can be paused or cancelled at once.
- Folder contents update live through FSEvents without re-reading the whole folder.

### Additional Low-Level Performance Guardrails

- **Swift Concurrency Pool Isolation:** Never run blocking POSIX filesystem calls (`getattrlistbulk`, `fts_read`, `statfs`, `copyfile`) directly on Swift's cooperative thread pool (`Task {}`), as blocking all CPU cores will deadlock `@MainActor` animations. Run raw filesystem loops on dedicated custom `DispatchQueue`s and bridge back via `AsyncStream`.
- **100k Folder Rendering Pipeline:**
  1. Do not use SwiftUI `List`/`LazyVGrid` or `NSDiffableDataSource` for primary file browsers. Use `NSTableView` and `NSCollectionView` with traditional index-based data sources.
  2. Stream directory reads via `getattrlistbulk` requesting `ATTR_CMN_NAME`, `ATTR_CMN_OBJTYPE`, `ATTR_CMN_MODTIME`, `ATTR_CMN_FLAGS`, `ATTR_FILE_TOTALSIZE`, and `ATTR_CMN_FILEID` in one syscall per batch.
  3. Render the first 200 items immediately (<16ms) before full sorting completes. Pre-compute natural sort keys (`localizedStandardCompare`) off the main thread.
- **Icon & Thumbnail Two-Tier Pipeline:** Never call `NSWorkspace.shared.icon(forFile:)` on the main thread during scrolling. Tier 1 (synchronous, 0ms): look up cached `UTType` icon by extension. Tier 2 (async, cancellable): enqueue a `QLThumbnailGenerator` request tied to the cell's reuse lifecycle, cancelling immediately in `prepareForReuse()`.
- **Cloud Stub Safety:** Check `SF_DATALESS` in `ATTR_CMN_FLAGS` (or `NSURLUbiquitousItemDownloadingStatusKey`). Never trigger full file reads, hash checks, or forced downloads on evicted iCloud/Dropbox files during browsing or disk scanning.
- **Copy Engine (`<copyfile.h>`):** Implement the file transfer queue using Darwin's `copyfile()` C API with `COPYFILE_CLONE` (instant APFS Copy-on-Write on same volume) and `copyfile_state_t` callbacks for real-time byte progress, bandwidth calculation, pause (`SIGSTOP`/condition lock), and clean cancellation.
- **FSEvents Coalescing:** Coalesce `FSEventStream` notifications with a 150ms debounce window so a `git checkout` or `npm install` creating 10,000 files in 2 seconds triggers a single batched UI refresh rather than 10,000 reloads.

## Build order

Please build in milestones I can run, roughly:

1. App shell with real materials and system accent, sidebar, toolbar, and a browser that lists real folders in icon and list view with selection, navigation, the path bar and Quick Look.
2. File operations: copy, move, rename, new folder, Trash with Undo, drag and drop, the transfer queue and conflict handling.
3. Tabs, dual pane, inspector, tags, and the status bar.
4. Command palette and search (names first, contents through Spotlight).
5. The scan engine brought over from wimys_crumb with the fixes above, then Groups and Storage map on top of it.
6. Settings, appearance options, the shelf, batch rename, smart folders.

Write tests for the engine pieces (walker, rollup, group queries, delete and restore) since mistakes there can lose data or report wrong sizes. For UI, run the app and check your work against the design before telling me a milestone is done.

## Safety

This app deletes and moves people's files, so:

- Destructive actions go to the Trash, never a permanent delete, unless I explicitly add that later.
- Never operate on protected system paths. Keep and extend the protected list from `DeleteService.swift`.
- Every bulk action shows what it will affect before it runs and can be undone.
- Test file operations in a temporary directory, not on my real folders.

## Ideas beyond the design

These aren't in the prototype. I'd like your opinion on which are worth doing and when, not all of them at once:

- Folder sizes in list view, computed lazily and cached from the scan database.
- Git status badges on files inside repositories.
- Browsing inside archives (zip, tar) without extracting.
- A duplicate finder that compares by size first, then hash, so it stays fast.
- Per-folder view settings that are remembered.
- "Open in Terminal" and "Copy path" everywhere, and a configurable list of external editors.
- Keyboard-only operation for everything, with a shortcut cheat sheet.
- Batch rename with live preview (find and replace, numbering, date from metadata).
- Saved searches as smart folders.
- Network locations (SMB, SFTP) with the same transfer queue.
- Scan history, so I can see what grew since last week (wimys_crumb already stores snapshots for this).

If you see something a great file manager needs that I've missed, say so.
