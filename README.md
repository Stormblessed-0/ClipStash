# ClipStash

A small, private clipboard history manager for macOS, in the spirit of
[Ditto](https://ditto-cp.sourceforge.io/) on Windows.

ClipStash sits in your menu bar, quietly remembers everything you copy, and
gives it back to you with a keystroke. **Everything stays on your Mac.** There
is no account, no sync, no network access of any kind.

## Features

- **Records text and images** copied from any app, de-duplicated.
- **⌃' (Control + apostrophe)** opens your history anywhere. The shortcut is
  configurable in Settings.
- **Select an item and it is pasted** into the text field you were in, and it
  becomes the current clipboard item. Type to search, arrow keys to move,
  ↩ to paste, ⇧↩ to copy without pasting, ⌘⌫ to delete one item, esc to close.
- **Survives restarts.** History is saved to
  `~/Library/Application Support/ClipStash/` and reloaded on launch.
- **Starts at login** (on by default, toggle in Settings or the menu bar menu).
- **Clear All** button in the popup and in Settings wipes every stored item
  and file from disk.
- **Runs passively** as a menu bar item with no Dock icon.
- Respects the `org.nspasteboard.ConcealedType` convention, so passwords copied
  from password managers are never recorded.

## Install

1. Download the latest `ClipStash-x.y.z.zip` from the
   [Releases](../../releases) page and unzip it.
2. Move **ClipStash.app** to your **Applications** folder. If you are not an
   administrator on your Mac, use `~/Applications` in your home folder instead
   (create it if it does not exist).
3. The app is not notarized with Apple, so the first launch needs one extra
   step: **right-click ClipStash.app → Open → Open**. If macOS still refuses,
   run this once in Terminal (adjust the path if you used `~/Applications`):

   ```bash
   xattr -dr com.apple.quarantine /Applications/ClipStash.app
   ```

4. On first launch ClipStash asks for **Accessibility** access. This is what
   lets it press ⌘V in the app you were using. Without it, selecting an item
   still copies it to the clipboard; you just paste by hand.
   System Settings → Privacy & Security → Accessibility → enable ClipStash.
5. Press **⌃'** and start using it.

### Login item

ClipStash registers itself as a login item the first time it runs. You will see
it under System Settings → General → Login Items. Turn it off there, in
ClipStash Settings, or from the menu bar menu.

## Usage

| Action                        | How                                  |
| ----------------------------- | ------------------------------------ |
| Open history                  | ⌃' (configurable), or menu bar icon  |
| Filter                        | Just start typing                    |
| Move selection                | ↑ / ↓                                |
| Paste selected item           | ↩ or click                           |
| Copy only (no paste)          | ⇧↩                                   |
| Delete selected item          | ⌘⌫ or the × on the row               |
| Clear everything              | **Clear All** button (click twice)   |
| Close                         | esc, or click anywhere else          |
| Settings                      | ⚙ in the popup, or menu bar → Settings… |

## Where your data lives

```
~/Library/Application Support/ClipStash/
├── history.json     ordered list of entries (newest first)
└── images/          PNG files for copied images
~/Library/Preferences/com.clipstash.app.plist   your settings
```

Delete that folder (or use **Clear All**) and the history is gone. Nothing is
stored anywhere else.

## Build from source

Requires macOS 13 or newer and either Xcode or the Xcode Command Line Tools
(`xcode-select --install`). No other dependencies.

```bash
git clone <this repository>
cd ClipStash
scripts/build-app.sh
open dist
```

`scripts/build-app.sh` produces `dist/ClipStash.app` and `dist/ClipStash-<version>.zip`.
The app is ad-hoc signed so it runs locally; distributing a notarized build
would require an Apple Developer ID.

For a quick debug build without packaging: `swift build && .build/debug/ClipStash`
(note that Login Items and stable Accessibility grants need the packaged
`.app`, so use the script for real use).

## Releasing

Tag a commit and push the tag. GitHub Actions builds the app and attaches the
zip to a new release:

```bash
echo 1.0.1 > VERSION
git commit -am "Release 1.0.1"
git tag v1.0.1
git push && git push --tags
```

## Project layout

```
Sources/ClipStash/
├── main.swift                 AppKit entry point
├── AppDelegate.swift          wires everything together, first-launch setup
├── ClipboardMonitor.swift     polls NSPasteboard for new content
├── HistoryStore.swift         in-memory list + JSON/PNG persistence
├── ClipItem.swift             a single history entry
├── HotKeyManager.swift        global shortcut via Carbon RegisterEventHotKey
├── KeyCombo.swift             shortcut model + display names
├── PasteService.swift         writes to pasteboard and sends ⌘V
├── HistoryPanelController.swift  the floating, non-activating popup window
├── HistoryView.swift          SwiftUI list, search, Clear All
├── HistoryViewModel.swift     filtering and keyboard selection
├── SettingsView.swift         settings window
├── StatusBarController.swift  menu bar icon and menu
├── LoginItemManager.swift     launch at login (SMAppService + fallback)
└── AppSettings.swift          UserDefaults-backed preferences
Resources/Info.plist           bundle metadata (LSUIElement = menu bar only)
scripts/build-app.sh           builds and packages the .app + .zip
scripts/make-icon.swift        regenerates Resources/AppIcon.icns
.github/workflows/             CI build and tag-triggered releases
```

## License

MIT. See [LICENSE](LICENSE).
