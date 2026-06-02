# SkidSS

A server-side script executor for your own Roblox experience, with a whitelist
and a Scratch-style block editor. Whitelisted players get an in-game window
where they can run code on the server — by writing Luau directly, or by snapping
blocks together. They can re-skin the executor itself with blocks, and customize
the server-side runtime with blocks too.



## Three parts

- **In-game executor** ([`src/`](src)) — the Roblox-side code: whitelist, server
  executor, and the windowed UI whitelisted players see.
- **Single-file build** ([`dist/SkidSS.lua`](dist/SkidSS.lua)) — everything
  above, bundled into one Script the game owner pastes into ServerScriptService.
- **SkidSS Studio** ([`desktop/`](desktop/README.md)) — a block-coding app for
  authoring scripts, the executor UI, and the server runtime, then writing the
  single-file build for you. Runs as a **desktop app** (Tauri, Windows + Linux)
  or as a **website** — `node tools/serve-web.js`, or host `desktop/src/` on any
  static host. Authoring tool only; it never connects to or runs on Roblox.

## Install

SkidSS is two pieces: a small **server** (`server.js`) that hosts the Studio site and
your account / whitelist / webhook API, and the **executor model** you build there and
paste into your own Roblox game. Pick the **Hosted** path for a live whitelist + Discord
webhook, or the **Standalone** path for a single pasted Script with no backend.

### Prerequisites

- **[Node.js](https://nodejs.org) 18 or newer** — runs the server, the bundler, and the
  static Studio. Check with `node --version`.
- **[Git](https://git-scm.com)** — to clone the repo.
- **Roblox Studio** — to install the model into a game you own.
- *Optional:* **[Rojo](https://rojo.space)** (+ [Aftman](https://github.com/LPGhatguy/aftman))
  to iterate on the Roblox source; **Rust + [Tauri](https://tauri.app) prerequisites** to
  build the desktop app instead of using the website.

### Hosted path (accounts + live whitelist + webhook)

1. **Get the code.**

   ```sh
   git clone https://github.com/bruvie-fr/skid-ss.git
   cd skid-ss
   ```

2. **Start the server.**

   ```sh
   node server.js              # serves the Studio + API on http://localhost:8080
   ```

   It hosts the Studio site *and* the API on one origin. Accounts and projects are stored
   as JSON under `data/` (created on first run, gitignored). Set `PORT` to change the port.

3. **Make your page.** Open the server URL in a browser, click **Sign up** (top-right),
   pick a username + password. Your whole project saves to your page and is editable only
   with that password — **Log in** anytime to get back to it.

4. **Build your executor** across the three tabs, then **Save page**:
   - **Script** — snap blocks for the server runtime (`when a player joins`,
     `define action`, plus any logic). Leave it empty for a plain code runner.
   - **Interface** — lay out the in-game GUI, or use the executor preset for a ready-made
     code box + output + run button.
   - **Config** — add whitelisted **UserIds / usernames**, and your **Discord webhook URL**
     (required — SkidSS proxies it to Discord for you; customise the message + bot name).

5. **Download the model.** Click **Build .rbxmx…**. It bakes in your page's live-whitelist
   URL and webhook proxy — no secrets, the password is never baked in.

6. **Install it in your game** — see [In your Roblox game](#in-your-roblox-game).

7. **Manage members live.** Add/remove people in **Config → Whitelist**, then **Save page**.
   The game re-reads your list on join — no rebuild, no re-paste.

   > For a **real** Roblox server (not just Studio) to reach your machine, the server needs
   > a public URL — see [Going public](#going-public).

### Standalone path (one Script, no backend)

No accounts, live updates, or webhook — just a single Script you edit by hand:

1. Build the bundle (or use **Build Script…** in the Studio):

   ```sh
   node tools/bundle.js        # writes dist/SkidSS.lua and dist/SkidSS.rbxmx
   ```

2. Paste `dist/SkidSS.lua` as a **Script** in **ServerScriptService**.
3. Set the whitelist at the top of the script:

   ```lua
   local WHITELIST_USERIDS = { [123456789] = true }      -- your UserId
   local WHITELIST_NAMES   = { ["yourusername"] = true } -- lower-case
   ```

### In your Roblox game

1. Open your game (one you **own**) in Roblox Studio.
2. **Game Settings → Security → Allow HTTP Requests → On** (needed for the live whitelist
   + webhook; the Standalone path works without it).
3. Drag the `.rbxmx` into **ServerScriptService** (or paste `SkidSS.lua` as a Script).
   Delete any older SkidSS first.
4. Press **Play**. Whitelisted players get the executor; **Right Shift** toggles the
   built-in window, and your custom GUI shows automatically.

### Going public

A live game server must reach your backend at a public HTTPS URL — `localhost` only works
inside Studio on your own machine. The Studio reads the URL from `/api/config` and bakes
it into the model. Any of:

- **Deploy `server.js`** to any Node host — the public URL is auto-detected from the
  request host / `PUBLIC_URL` / common platform variables.
- **Your own domain** (e.g. `diyss.duckdns.org`): point it at the box and open the Studio
  there, or run `PUBLIC_URL=https://diyss.duckdns.org node server.js`.
- **Quick test from your own machine:** `node server.js --tunnel` opens a temporary public
  URL via [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/).

Run the server behind **HTTPS** in production — passwords are scrypt-hashed, but the
session token and webhook still travel over the wire.

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
- **Code tab** — a Luau editor inside the executor. Runs on the server via a
  **built-in Luau interpreter** — no `loadstring`, no
  `ServerScriptService.LoadStringEnabled` toggle. Works the moment the model is
  pasted in. See [interpreter scope](#raw-lua-interpreter) for what it supports.
- **Blocks tab** — build server scripts from blocks (loops, conditionals,
  variables, player actions). Sandboxed interpreter with step budget — can't
  hang the game.
- **Interface tab** — block-edit the executor window (title, colours, toasts,
  quick buttons). Live preview in Studio.
- **Server runtime in blocks** — the **Script** tab's blocks ARE the server
  runtime: snap together `when a player joins`, `define action`, `reject request`,
  and any logic. They're baked into the bundle and run server-side.
- **Live whitelist** — with the backend (below), the executor fetches your
  whitelist from your page on join, so you add/remove members on the site with no
  rebuild. The baked CONFIG list is the offline fallback.
- **Discord webhook (optional)** — set a webhook **proxy** URL (Roblox blocks
  discord.com directly) and the executor logs who ran what, in which game.
- **Config in Studio** — the Config tab edits the whitelist + server limits + your
  page/webhook URLs; **Build .rbxmx** stamps them into the bundle's CONFIG section.

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

## Backend reference

[`server.js`](server.js) is zero-dependency (Node built-ins + JSON files under `data/`).
Endpoints:

| Method / path | Auth | Purpose |
| --- | --- | --- |
| `POST /api/signup` · `POST /api/login` | – | create / sign in; returns a session token + pageKey |
| `GET` · `PUT /api/project` | Bearer token | load / save your project |
| `GET /api/config` | – | the server's public URL (for baking into the model) |
| `GET /api/whitelist/:pageKey` | – (public) | `{ userIds, names }` the game reads on join |
| `POST /api/webhook/:pageKey` | – | relays a usage post to your stored Discord webhook |
| `GET /*` | – | the static Studio site from `desktop/src` |

- Passwords are **scrypt-hashed**; sessions are random server-stored tokens. Run behind
  **HTTPS** in production.
- The public whitelist read exposes only the allow-list — knowing it grants nothing (adds
  still need your password). The Discord webhook is stored on your page and **never** baked
  into the game; the game posts to `/api/webhook/:pageKey`, which relays to Discord (Roblox
  can't reach discord.com directly).
- `data/` is gitignored. JSON-file storage suits self-hosting, not high scale.
- **Offline:** without the backend, serve the Studio statically
  (`node tools/serve-web.js`) — you just can't log in, save, or use the live whitelist /
  webhook.

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
- Block scripts and the raw Code tab are both bounded by step / time / recursion
  budgets and loop/wait caps ([`Config.Limits`](src/shared/Config.luau)), so a
  runaway script (even `while true do end`) is aborted instead of stalling the
  server.
- The Code tab is a **trusted-user** tool: like `loadstring`, interpreted code
  can do anything the server can. The budgets stop accidental freezes, not a
  determined whitelisted user — so guard the whitelist accordingly.
- The custom runtime's `onRequestReceived` hook can deny any request — use it
  to enforce game-specific rules (e.g. reject `mode == "lua"` from everyone but
  one UserId).

### Raw-Lua interpreter

The Code tab runs through a tree-walking Luau interpreter
([`src/server/LuaInterp.luau`](src/server/LuaInterp.luau)) instead of
`loadstring`. Because it runs inside real Luau, interpreted tables/functions are
real values, so metatables, the standard library and the **whole Roblox API**
(`game`, `workspace`, services, Instances, datatypes, `task`, …) work normally.

**Supported:** locals/globals, multiple assignment & returns, varargs, full
operators & precedence, `.`/`[]`/`:` access and calls, `if`/`while`/`repeat`,
numeric & generic `for`, `break`, `return`, `continue`, functions/closures,
metatables, and Luau compound assignment (`+=`, `..=`, …).

**`require` works** — both `require(ModuleScript)` and `require(assetId)` for
published code you own; required modules run as native Luau, so it doubles as the
escape hatch for anything the interpreter's subset doesn't cover.

**Not in v1:** full type annotations are parsed but **discarded** (only simple
forms are tolerated; exotic types error), and there is no backtick string
interpolation or `goto`/labels. Prefer untyped scripts.
