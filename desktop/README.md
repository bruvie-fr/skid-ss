# SkidSS Studio

A cross-platform desktop app (Windows / Linux) for authoring SkidSS with
**block code**, then writing the single-file `SkidSS.lua` the game owner pastes
into ServerScriptService.

Authoring tool only — it writes `.lua` files, never connects to Roblox.

## What it does

Four tabs:

- **Script** (blocks) — ad-hoc admin scripts the user runs inside the
  executor's Code tab. Compiled live to Luau, **Copy Luau** copies it.
- **Interface** (blocks + live preview) — block-edit the executor window
  (title, accent, console messages, quick buttons).
- **Runtime** (blocks) — block-edit the server's core hooks
  (`onPlayerAdded`, `onPlayerRemoving`, `onRequestReceived`) and register
  custom actions the executor can invoke by name.
- **Config** (form) — edit everything that isn't blocks: the whitelist
  (UserIds + names) and server limits (max steps / loop iterations / wait
  seconds). **Load from existing SkidSS.lua…** populates the form from a file
  so round-trip preserves your settings.

The Interface, Runtime, and Config tabs all feed into **Build Script…**, which
writes a complete `SkidSS.lua` — every section filled in — ready to paste.

## Prerequisites

- [Rust](https://rustup.rs) (the Tauri build toolchain).
- Node.js (only to run the bundled Tauri CLI).
- Linux also needs the Tauri system deps (webkit2gtk, etc.):
  <https://tauri.app/start/prerequisites/>.

Blockly is vendored under [`src/vendor/blockly`](src/vendor/blockly) so the app
works fully offline.

## Run / build

```sh
cd desktop
npm install            # fetches the Tauri CLI
npm run tauri dev      # develop
npm run tauri build    # produces a Windows .exe / Linux AppImage + .deb
```

Build artifacts land in `src-tauri/target/release/bundle/`.

> Studio reads `desktop/src/bundle-template.txt` to know what bundle to write.
> If you've added/removed Lua files in the project, regenerate it with
> `node tools/bundle.js` from the repo root before building Studio.

## Preview the UI without building (no Rust)

The frontend is plain static files, so you can open it in a browser:

```sh
python -m http.server --directory src 5599
# then open http://localhost:5599
```

Block editing, preview and Luau generation all work. **Build Script…** falls
back to a normal browser download (the native save dialog only exists inside
the Tauri app).

## Build Script flow

1. Customize the **Runtime** tab (hooks + custom actions) and **Interface** tab.
2. Click **Build Script…**. Studio:
   - Saves to the path you pick. If the file already exists and contains the
     same marker structure, Studio **rewrites only** the `CUSTOM RUNTIME` and
     `CUSTOM INTERFACE` sections — your `CONFIG` (whitelist) is preserved
     verbatim.
   - Otherwise, it writes a fresh bundle with an empty `CONFIG` block for you
     to fill in.
3. **Copy Bundle** copies the same bundle to the clipboard if you'd rather
   paste it directly.

The **Script** tab (ad-hoc admin scripts) is **not** part of the bundle —
**Copy Luau** copies its current generated code, ready to paste into the
executor's Code tab in-game.

## Adding blocks

- Define the block in [`src/blocks.js`](src/blocks.js) and add it to whichever
  toolbox(es) it belongs in (`SCRIPT_TOOLBOX`, `INTERFACE_TOOLBOX`,
  `RUNTIME_TOOLBOX`).
- Add its Luau generator in [`src/luau.js`](src/luau.js).

Standard blocks (if / loops / math / text / variables) come from Blockly's
bundled Lua generator — you only write generators for the Roblox-specific
blocks.
