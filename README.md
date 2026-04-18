# MacNotepad

`MacNotepad` is a macOS plain-text editor inspired by Microsoft Windows Notepad.

It supports:

- multiple windows
- tabbed `.txt` documents
- plain text editing
- `Open`, `Save`, `Save As`, `Find`, `Replace`, and `Go To`
- word wrap, font controls, and status bar
- temporary session restore for closed windows and tabs

## Run locally

```bash
swift build
swift run
```

## Build a real `.app`

```bash
./scripts/build_app.sh
```

That creates:

```bash
dist/MacNotepad.app
```

## Share the app

1. Build the release app bundle with `./scripts/build_app.sh`
2. Zip `dist/MacNotepad.app`
3. Upload the zip to GitHub Releases, Google Drive, or send it directly

## Repo layout

- [Package.swift](/Users/kyawkyawtun/Documents/Codex/2026-04-18-i-want-to-create-mac-notepad/Package.swift)
- [Sources/MacNotepad](/Users/kyawkyawtun/Documents/Codex/2026-04-18-i-want-to-create-mac-notepad/Sources/MacNotepad)
- [scripts/build_app.sh](/Users/kyawkyawtun/Documents/Codex/2026-04-18-i-want-to-create-mac-notepad/scripts/build_app.sh)
- [App/Info.plist](/Users/kyawkyawtun/Documents/Codex/2026-04-18-i-want-to-create-mac-notepad/App/Info.plist)
