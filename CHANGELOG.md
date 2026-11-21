# Changelog

All notable changes to Peel. Newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.2] - 2026-11-21

Draw freely, and clear the shelf in one go.

### Added
- **Pen** in the editor (P): draw anything freehand, in any of the six colours.
- **Clear Shelf**: the trash button next to the shelf's search, or Clear Shelf… in the menu bar menu. It asks first, then moves every capture to the Trash (Finder's Put Back restores them). Copies you saved to Photos or a folder stay.

## [1.1] - 2026-11-02

Save straight to Photos.

### Changed
- **Save adds to your Photos library** by default. macOS asks once, the first time, for permission to add photos only: Peel can't see or read your library. Prefer a folder? Settings › Captures › "Save button adds to" › A folder.
- Settings explain the difference between your saved copies and the shelf's own captures folder.

## [1.0] - 2026-11-02

First version.

### Added
- **One shortcut** (⇧⌘2) to capture an area, or a window with Space. The menu bar icon also captures a window or the full screen.
- **The shelf** (⇧⌘1): every capture, newest first. Click to copy, drag into any app, pin on screen, save as PNG or JPG, or move to the Trash.
- **Edit:** arrow, box, highlight, text, solid redaction and crop, in six colours. Done adds an edited copy; the original stays.
- **Copy text** out of any capture, and **search** captures by the words in them. Read on your Mac with Apple's Vision; nothing is uploaded.
- **Welcome tour** on first launch (permission, shortcuts, how to use, settings), then no windows at launch ever again. Launch at Login in Settings.
- Captures are kept for a month by default (1 day to forever); older ones go to the Trash.
- Updates itself from GitHub, like Swivel, and only accepts updates signed with the same developer certificate.
