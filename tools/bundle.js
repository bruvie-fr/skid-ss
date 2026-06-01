// Bundles the multi-file Rojo source into one self-cloning Script the game
// owner pastes into ServerScriptService. The bundle dispatches via
// RunService:IsClient() — on first run it executes the server half, and the
// server clones the same script (with RunContext = Client) into each
// whitelisted player's PlayerGui to drive the executor UI client-side.
//
// Also writes desktop/src/bundle-template.txt so SkidSS Studio can round-trip
// user customizations without re-running this script.
//
// Usage: node tools/bundle.js [--out dist/SkidSS.lua]

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const outArg = process.argv.indexOf("--out");
const outFile = outArg >= 0 ? process.argv[outArg + 1] : "dist/SkidSS.lua";

const SHARED_ORDER = ["Config", "Util", "Net", "BlocksDefs", "BlocksInterpreter", "BlocksLua"];
const SHARED = {
  Config: "src/shared/Config.luau",
  Util: "src/shared/Util.luau",
  Net: "src/shared/Net.luau",
  BlocksDefs: "src/shared/blocks/Defs.luau",
  BlocksInterpreter: "src/shared/blocks/Interpreter.luau",
  BlocksLua: "src/shared/blocks/Lua.luau",
};

const SERVER_ORDER = ["ServerApi", "Whitelist", "Executor"];
const SERVER = {
  ServerApi: "src/server/ServerApi.luau",
  Whitelist: "src/server/Whitelist.luau",
  Executor: "src/server/Executor.luau",
};

const CLIENT_ORDER = ["Client_Theme", "Client_Palette", "Client_BlockCanvas", "Client_BlockTab", "Client_CodeTab", "Client_Window"];
const CLIENT = {
  Client_Theme: "src/client/Theme.luau",
  Client_Palette: "src/client/ui/Palette.luau",
  Client_BlockCanvas: "src/client/ui/BlockCanvas.luau",
  Client_BlockTab: "src/client/ui/BlockTab.luau",
  Client_CodeTab: "src/client/ui/CodeTab.luau",
  Client_Window: "src/client/ui/Window.luau",
};

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

function stripMarkerBlock(src, name) {
  const re = new RegExp(
    "^[ \\t]*-- BUNDLE:" + name + "_BEGIN[\\s\\S]*?-- BUNDLE:" + name + "_END[ \\t]*\\n?",
    "m"
  );
  return src.replace(re, "");
}

function replaceMarkerBlock(src, name, replacement) {
  const re = new RegExp(
    "^[ \\t]*-- BUNDLE:" + name + "_BEGIN[\\s\\S]*?-- BUNDLE:" + name + "_END[ \\t]*",
    "m"
  );
  return src.replace(re, replacement);
}

const SHARED_REWRITES = [
  [/local Shared = ReplicatedStorage:WaitForChild\("SkidSS"\)\n/g, ""],
  [/require\(script\.Parent\.Config\)/g, "SkidSS_Config"],
  [/require\(script\.Parent\.Parent\.Util\)/g, "SkidSS_Util"],
  [/require\(script\.Parent\.Defs\)/g, "SkidSS_BlocksDefs"],
  [/require\(Shared\.Config\)/g, "SkidSS_Config"],
  [/require\(Shared\.Net\)/g, "SkidSS_Net"],
  [/require\(Shared\.blocks\.Interpreter\)/g, "SkidSS_BlocksInterpreter"],
  [/require\(Shared\.blocks\.Lua\)/g, "SkidSS_BlocksLua"],
  [/require\(Shared\.blocks\.Defs\)/g, "SkidSS_BlocksDefs"],
  [/require\(ReplicatedStorage:WaitForChild\("SkidSS"\):WaitForChild\("Config"\)\)/g, "SkidSS_Config"],
  [/require\(ReplicatedStorage:WaitForChild\("SkidSS"\)\.blocks\.Defs\)/g, "SkidSS_BlocksDefs"],
  [/require\(ReplicatedStorage:WaitForChild\("SkidSS"\)\.blocks\.Lua\)/g, "SkidSS_BlocksLua"],
  [/require\(ReplicatedStorage:WaitForChild\("SkidSS"\)\.blocks\.Interpreter\)/g, "SkidSS_BlocksInterpreter"],
];

const SERVER_REWRITES = SHARED_REWRITES.concat([
  [/require\(script\.Whitelist\)/g, "SkidSS_Whitelist"],
  [/require\(script\.Executor\)/g, "SkidSS_Executor"],
  [/require\(script\.Parent\.ServerApi\)/g, "SkidSS_ServerApi"],
]);

const CLIENT_REWRITES = SHARED_REWRITES.concat([
  [/require\(script\.ui\.Window\)/g, "SkidSS_Client_Window"],
  [/require\(script\.Parent\.Parent\.Theme\)/g, "SkidSS_Client_Theme"],
  [/require\(script\.Parent\.CodeTab\)/g, "SkidSS_Client_CodeTab"],
  [/require\(script\.Parent\.BlockTab\)/g, "SkidSS_Client_BlockTab"],
  [/require\(script\.Parent\.Palette\)/g, "SkidSS_Client_Palette"],
  [/require\(script\.Parent\.BlockCanvas\)/g, "SkidSS_Client_BlockCanvas"],
]);

function rewrite(src, table) {
  for (const [pat, rep] of table) src = src.replace(pat, rep);
  return src;
}

function asIIFE(name, src) {
  return `local ${name} = (function()\n${src.replace(/\n$/, "")}\nend)()\n`;
}

function buildModule(name, file, rewrites, extraTransform) {
  let src = read(file);
  if (extraTransform) src = extraTransform(src);
  src = rewrite(src, rewrites);
  return asIIFE("SkidSS_" + name, src);
}

function whitelistTransform(src) {
  return src.replace(
    /-- BUNDLE:WHITELIST_DEFAULTS_BEGIN[\s\S]*?-- BUNDLE:WHITELIST_DEFAULTS_END/,
    "Whitelist.UserIds = WHITELIST_USERIDS\nWhitelist.Names = WHITELIST_NAMES"
  );
}

const SETTINGS_OVERRIDE = `if SETTINGS then
\tSkidSS_Config.Limits.MaxSteps = SETTINGS.maxSteps or SkidSS_Config.Limits.MaxSteps
\tSkidSS_Config.Limits.MaxLoopIterations = SETTINGS.maxLoopIterations or SkidSS_Config.Limits.MaxLoopIterations
\tSkidSS_Config.Limits.MaxWaitSeconds = SETTINGS.maxWaitSeconds or SkidSS_Config.Limits.MaxWaitSeconds
end`;

const BUNDLE_INJECT = `local function injectClient(player)
\tlocal playerGui = player:WaitForChild("PlayerGui", 10)
\tif not playerGui or playerGui:FindFirstChild("SkidSSClient") then return end
\t-- Preferred: clone the pre-baked LocalScript child shipped in the .rbxmx.
\tlocal template = script:FindFirstChild("Client")
\tif template then
\t\tlocal clone = template:Clone()
\t\tclone.Name = "SkidSSClient"
\t\tclone.Disabled = false
\t\tclone.Parent = playerGui
\t\treturn
\tend
\t-- Fallback: self-clone with a RunContext flip. Works on engines that honor
\t-- runtime RunContext changes; silently no-ops on the ones that don't.
\tlocal clone = script:Clone()
\tclone.Name = "SkidSSClient"
\tclone.Disabled = true
\tpcall(function() clone.RunContext = Enum.RunContext.Client end)
\tclone.Parent = playerGui
\tclone.Disabled = false
end`;

function buildSharedChunk() {
  return SHARED_ORDER.map((name) => buildModule(name, SHARED[name], SHARED_REWRITES)).join("\n") + "\n" + SETTINGS_OVERRIDE + "\n";
}

function buildClientBranch() {
  const parts = CLIENT_ORDER.map((name) => buildModule(name, CLIENT[name], CLIENT_REWRITES));
  let body = read("src/client/init.client.luau");
  body = stripMarkerBlock(body, "CUSTOM_INTERFACE");
  body = rewrite(body, CLIENT_REWRITES);
  parts.push(body);
  return parts.join("\n");
}

function buildServerBranch() {
  const parts = [];
  for (const name of SERVER_ORDER) {
    const extra = name === "Whitelist" ? whitelistTransform : null;
    parts.push(buildModule(name, SERVER[name], SERVER_REWRITES, extra));
  }
  let body = read("src/server/init.server.luau");
  body = stripMarkerBlock(body, "CUSTOM_RUNTIME");
  body = replaceMarkerBlock(body, "INJECT", BUNDLE_INJECT);
  body = rewrite(body, SERVER_REWRITES);
  parts.push(body);
  return parts.join("\n");
}

const HEADER = `-- SkidSS — paste this entire Script into ServerScriptService.
--
-- 1) Edit the WHITELIST tables below with your UserId(s),
--    or use SkidSS Studio to fill the CONFIG section for you.
-- 2) Save and play. Whitelisted players get the executor on join.
--
-- This script must be installed by the owner of the game (or a developer they
-- explicitly authorised). It runs server-side and grants script execution to
-- whitelisted players.
--
-- How it works: on first run the script's server-side half wires up the
-- remotes; for each whitelisted player it clones itself with
-- RunContext = Client into the player's PlayerGui, where the same source
-- branches via RunService:IsClient() and runs the executor UI.
`;

const SETTINGS_DEFAULT = `local SETTINGS = {
\tmaxSteps = 200000,
\tmaxLoopIterations = 100000,
\tmaxWaitSeconds = 30,
}`;

const TEMPLATE_RUNTIME_DEFAULT = `local CustomRuntime = {
\tonPlayerAdded = function(_player) end,
\tonPlayerRemoving = function(_player) end,
\tonRequestReceived = function(_player, _payload) return true end,
\tcustomActions = {},
}`;

const TEMPLATE_INTERFACE_DEFAULT = `local CustomInterface = function() return {} end`;

function assemble({ whitelistIds, whitelistNames, customRuntime, customInterface }) {
  const out = [
    HEADER,
    "-- ===== CONFIG (edit me, or use Studio to fill these in) =====",
    "-- Whitelist tables are HASH tables keyed by the UserId or name.",
    "-- Example: { [123456789] = true, [987654321] = true }   <-- not { 123456789 }",
    "-- Names go in quotes, lower-case: { [\"yourname\"] = true }",
    `local WHITELIST_USERIDS = ${whitelistIds || "{}"}`,
    `local WHITELIST_NAMES = ${whitelistNames || "{}"}`,
    SETTINGS_DEFAULT,
    "-- ===== END CONFIG =====",
    "",
    "-- ===== CUSTOM RUNTIME (written by Studio; safe to overwrite) =====",
    customRuntime || TEMPLATE_RUNTIME_DEFAULT,
    "-- ===== END CUSTOM RUNTIME =====",
    "",
    "-- ===== CUSTOM INTERFACE (written by Studio; safe to overwrite) =====",
    customInterface || TEMPLATE_INTERFACE_DEFAULT,
    "-- ===== END CUSTOM INTERFACE =====",
    "",
    'local RunService = game:GetService("RunService")',
    "",
    "-- ===== SHARED MODULES (run on both sides) =====",
    buildSharedChunk(),
    "-- ===== END SHARED MODULES =====",
    "",
    "if RunService:IsClient() then",
    "-- ===== CLIENT (runs in the cloned script inside PlayerGui) =====",
    buildClientBranch(),
    "-- ===== END CLIENT =====",
    "\treturn",
    "end",
    "",
    "-- ===== SERVER (do not edit) =====",
    buildServerBranch(),
    "-- ===== END SERVER =====",
  ];
  return out.join("\n");
}

function escapeCdata(text) {
  return text.split("]]>").join("]]]]><![CDATA[>");
}

function buildRbxmx(bundleSource) {
  const cdata = escapeCdata(bundleSource);
  // Disabled LocalScript child holds the same source. The server's injectClient
  // clones it (with Disabled=false) into PlayerGui per whitelisted player.
  return [
    '<roblox version="4">',
    '\t<Item class="Script" referent="RBX0">',
    '\t\t<Properties>',
    '\t\t\t<string name="Name">SkidSS</string>',
    '\t\t\t<ProtectedString name="Source"><![CDATA[' + cdata + ']]></ProtectedString>',
    '\t\t</Properties>',
    '\t\t<Item class="LocalScript" referent="RBX1">',
    '\t\t\t<Properties>',
    '\t\t\t\t<string name="Name">Client</string>',
    '\t\t\t\t<bool name="Disabled">true</bool>',
    '\t\t\t\t<ProtectedString name="Source"><![CDATA[' + cdata + ']]></ProtectedString>',
    '\t\t\t</Properties>',
    '\t\t</Item>',
    '\t</Item>',
    '</roblox>',
  ].join("\n");
}

if (require.main === module) {
  const bundle = assemble({});
  const outPath = path.join(root, outFile);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, bundle);
  const rbxmxPath = outPath.replace(/\.lua$/, ".rbxmx");
  const rbxmx = buildRbxmx(bundle);
  fs.writeFileSync(rbxmxPath, rbxmx);
  fs.mkdirSync(path.join(root, "desktop/src"), { recursive: true });
  fs.writeFileSync(path.join(root, "desktop/src/bundle-template.txt"), bundle);
  console.log("wrote", outFile, "(" + bundle.length + " bytes)");
  console.log("wrote", path.relative(root, rbxmxPath), "(" + rbxmx.length + " bytes)");
  console.log("wrote desktop/src/bundle-template.txt");
}

module.exports = { assemble, buildRbxmx };
