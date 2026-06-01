# SkidSS

A server-side script executor for your own Roblox experience, with a whitelist
and a Scratch-style block editor. Whitelisted players get an in-game window
where they can run code on the server — by writing Luau directly, or by snapping
blocks together. They can re-skin the executor itself with blocks, and customize
the server-side runtime with blocks too.

> Install this only in games you own (or where the owner has explicitly
> authorised you to add server scripts). It runs code on the server, so treat
> the whitelist as the key to your game.

## Three parts

- **In-game executor** ([`src/`](src)) — the Roblox-side code: whitelist, server
  executor, and the windowed UI whitelisted players see.
- **Single-file build** ([`dist/SkidSS.lua`](dist/SkidSS.lua)) — everything
  above, bundled into one Script the game owner pastes into ServerScriptService.
- **SkidSS Studio** ([`desktop/`](desktop/README.md)) — a cross-platform desktop
  app (Tauri, Windows + Linux) for authoring scripts, the executor UI, and the
  server runtime with block code, then writing the single-file build for you.
  Authoring tool only; it never connects to or runs on Roblox.

## Install (recommended path: paste one Script)

1. **Build the bundle** (once):

   ```sh
   node tools/bundle.js
   ```

   Or open **SkidSS Studio**, customize, and hit **Build Script…** — same output.

2. **Paste into your game.** Open the game in Roblox Studio, paste the contents
   of `dist/SkidSS.lua` as a new **Script** in **ServerScriptService**.

3. **Add yourself to the whitelist.** At the top of the script:

   ```lua
   local WHITELIST_USERIDS = { [123456789] = true }  -- your UserId
   local WHITELIST_NAMES   = { ["yourusername"] = true }  -- lower-case
   ```

4. **Play.** Whitelisted players get the executor. **Right Shift** toggles it.

That's it — one paste, one whitelist edit. The script creates remotes, gates
every request behind the whitelist, and injects the client UI per player on
join. No model files, no asset IDs, no HTTP calls.

### What's in the bundle

The bundle has clearly marked sections at the top:

```lua
-- ===== CONFIG (edit me) =====          -- whitelist tables
-- ===== CUSTOM RUNTIME (written by Studio; safe to overwrite) =====
-- ===== CUSTOM INTERFACE (written by Studio; safe to overwrite) =====
-- ===== CLIENT SOURCE (do not edit) =====
-- ===== SERVER (do not edit) =====
```

When you re-build from Studio against an existing `SkidSS.lua`, only the two
**CUSTOM** sections change — your `CONFIG` (whitelist) is preserved verbatim.

## What's in it

- **Whitelist** — only listed players ever receive the UI.
- **Code tab** — a Luau editor inside the executor. Runs on the server via
  `loadstring` (opt-in).
- **Blocks tab** — build server scripts from blocks (loops, conditionals,
  variables, player actions). Sandboxed interpreter with step budget — can't
  hang the game, works without `loadstring`.
- **Interface tab** — block-edit the executor window (title, colours, toasts,
  quick buttons). Live preview in Studio.
- **Custom runtime** — block-edit the server's join/leave/request hooks and
  register named actions the executor can invoke. Built in Studio's Runtime tab,
  baked into the bundle.
- **Config in Studio** — Studio's Config tab edits the whitelist (UserIds +
  names) and server limits with a form. **Build Script** stamps the result
  into the bundle's CONFIG section — no need to hand-edit Lua.

## Develop (Rojo)

If you'd rather iterate on the source, the project is set up for Rojo:

```sh
rojo serve
```

| Source | Lands in |
| --- | --- |
| `src/server` | `ServerScriptService.SkidSS` |
| `src/shared` | `ReplicatedStorage.SkidSS` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.SkidSS` |

Edit [`src/server/Whitelist.luau`](src/server/Whitelist.luau) for the whitelist
in dev mode. When you're ready to ship, run `node tools/bundle.js` and use the
single-file Script.

## Adding your own blocks

In the in-game block engine, every block is one `register{}` entry in
[`src/shared/blocks/Defs.luau`](src/shared/blocks/Defs.luau). Give it a `label`
(with `%name` slots), optional inputs/fields/bodies, an `exec` (statements) or
`eval` (values), and a `toLua`. The palette, interpreter and Lua compiler all
pick it up automatically.

In Studio's Blockly editor, see [`desktop/src/blocks.js`](desktop/src/blocks.js)
and [`desktop/src/luau.js`](desktop/src/luau.js).

## Layout

```
src/                  Rojo source (canonical)
  shared/             config, networking, block engine
    blocks/           Defs, Interpreter, Lua
  server/             whitelist, request dispatch, executor
  client/             in-game windowed UI
tools/
  bundle.js           builds dist/SkidSS.lua (and Studio's template)
desktop/              SkidSS Studio (Tauri authoring app)
dist/SkidSS.lua       single-script build (paste into SSS)
```

## Safety notes

- The server re-checks the whitelist on every request and rejects wrong-side
  blocks; clients are never trusted.
- Block scripts are bounded by a step budget and loop/wait caps
  ([`Config.Limits`](src/shared/Config.luau)).
- The raw Code tab is real `loadstring`. A non-yielding infinite loop in
  hand-written Luau can still stall the server. That's why it's opt-in; prefer
  blocks for anything you'd hand to other people.
- The custom runtime's `onRequestReceived` hook can deny any request — use it
  to enforce game-specific rules (e.g. reject `mode == "lua"` from everyone but
  one UserId).
