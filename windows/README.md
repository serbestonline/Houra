# Houra for Windows

The Windows version of Houra, written with Electron. It keeps the same local SQLite format as the macOS app, so a `houra.sqlite` file can be moved between the two.

```
npm install
npm test          # data layer, session engine, weekly note parser
npm start         # run from source
npm run dist      # dist/Houra-Setup-<version>.exe (run on Windows, or use the "Windows" GitHub workflow)
```

- `src/core` — store, session engine, weekly note reader, statistics (no Electron; tested with `node --test`)
- `src/main.js` — tray, windows, global shortcut (Ctrl + Alt + N), everything the windows call
- `src/ui` — the windows: panel, new session, on-screen views, detail panel, break screen, stretches
- `installer/` — Houra's own setup window (dark, frameless); `scripts/make-installer.js` draws its artwork and wraps the electron-builder installer in it
- `src/shared/icons.js` is generated from `Sources/IconData.swift` by `scripts/make-icons.js`
- The stretch animations are read from the repository's `Stretches` folder and bundled into the installer

Data lives in `%APPDATA%\Houra`. A copy run from source uses `Houra-dev` instead, so it never touches an installed Houra's data.

Copyright (c) 2026 Serbest. All rights reserved; see `../LICENSE`.
