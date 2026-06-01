// Pure Lua codegen for SkidSS Studio's forms. No DOM / Blockly deps, so it can
// be unit-tested under Node as well as loaded in the browser.

(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SkidCodegen = api;
})(typeof self !== "undefined" ? self : this, function () {
  const q = (s) => JSON.stringify(String(s == null ? "" : s));
  const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };

  function hexToRgbLua(hex) {
    hex = hex || "#000000";
    const r = parseInt(hex.slice(1, 3), 16) || 0;
    const g = parseInt(hex.slice(3, 5), 16) || 0;
    const b = parseInt(hex.slice(5, 7), 16) || 0;
    return "Color3.fromRGB(" + r + ", " + g + ", " + b + ")";
  }

  const VERBS = {
    notify: { label: "Notify message", param: "text", noTarget: true },
    kick: { label: "Kick", param: "reason" },
    heal: { label: "Heal" },
    kill: { label: "Kill" },
    freeze: { label: "Freeze" },
    unfreeze: { label: "Unfreeze" },
    walkspeed: { label: "Set WalkSpeed", param: "number" },
    health: { label: "Set Health", param: "number" },
    bring: { label: "Bring to me" },
  };
  const ACTION_VERB_IDS = ["notify", "kick", "heal", "kill", "freeze", "unfreeze", "walkspeed", "health", "bring"];
  const HOOK_VERB_IDS = ["heal", "freeze", "unfreeze", "walkspeed", "health", "kick"];

  function verbBody(id, param, P) {
    switch (id) {
      case "notify": return "if emit then emit(" + q(param || "") + ') else print("[SkidSS] " .. ' + q(param || "") + ") end";
      case "kick": return P + ":Kick(" + q(param || "Kicked") + ")";
      case "heal": return "local _h = _hum(" + P + ") if _h then _h.Health = _h.MaxHealth end";
      case "kill": return "local _h = _hum(" + P + ") if _h then _h.Health = 0 end";
      case "freeze": return "local _h = _hum(" + P + ") if _h then _h.WalkSpeed = 0 _h.JumpPower = 0 _h.JumpHeight = 0 end";
      case "unfreeze": return "local _h = _hum(" + P + ") if _h then _h.WalkSpeed = 16 _h.JumpPower = 50 _h.JumpHeight = 7.2 end";
      case "walkspeed": return "local _h = _hum(" + P + ") if _h then _h.WalkSpeed = " + num(param, 16) + " end";
      case "health": return "local _h = _hum(" + P + ") if _h then _h.Health = " + num(param, 100) + " end";
      case "bring": return "if " + P + ".Character and player.Character then " + P + ".Character:PivotTo(player.Character:GetPivot()) end";
      default: return "";
    }
  }

  function actionDef(a) {
    const name = (a.name || "").trim();
    if (!name) return "";
    const head = "CustomRuntime.customActions[" + q(name) + "] = function(player, args, emit)";
    let body;
    if (a.mode === "lua") {
      body = (a.lua || "").replace(/\r/g, "").split("\n").map((l) => "\t" + l).join("\n");
    } else {
      const id = a.verb || "notify";
      const meta = VERBS[id] || {};
      if (meta.noTarget) {
        body = "\t" + verbBody(id, a.param, "player");
      } else {
        const inner = verbBody(id, a.param, "t");
        if (a.target === "all") {
          body = "\tfor _, t in Players:GetPlayers() do " + inner + " end";
        } else if (a.target === "name") {
          body = "\tfor _, t in Players:GetPlayers() do if string.lower(t.Name) == string.lower(" + q(a.targetName || "") + ") then " + inner + " end end";
        } else {
          body = "\tlocal t = player " + inner;
        }
      }
    }
    return head + "\n" + body + "\nend";
  }

  function buildRuntimeTable(state) {
    const L = [];
    L.push('local Players = game:GetService("Players")');
    L.push('local function _hum(p) local c = p and p.Character return c and c:FindFirstChildOfClass("Humanoid") end');
    L.push("local CustomRuntime = {");
    L.push("\tonPlayerAdded = function(player)");
    state.join.forEach((r) => { if (r.verb) L.push("\t\tdo local t = player " + verbBody(r.verb, r.param, "t") + " end"); });
    L.push("\tend,");
    L.push("\tonPlayerRemoving = function(player)");
    state.leave.forEach((r) => { if (r.verb) L.push("\t\tdo local t = player " + verbBody(r.verb, r.param, "t") + " end"); });
    L.push("\tend,");
    L.push("\tonRequestReceived = function(player, _payload)");
    if (state.gateLua) L.push('\t\tif _payload.mode == "lua" then return false end');
    L.push("\t\treturn true");
    L.push("\tend,");
    L.push("\tcustomActions = {},");
    L.push("}");
    state.actions.forEach((a) => { const d = actionDef(a); if (d) L.push(d); });
    return L.join("\n");
  }

  function normalizeAsset(v) {
    v = String(v == null ? "" : v).trim();
    if (v === "") return "";
    if (/^\d+$/.test(v)) return "rbxassetid://" + v;
    return v;
  }

  function elementToLua(e) {
    const p = [];
    p.push("type = " + q(e.type || "panel"));
    p.push("x = " + num(e.x, 0));
    p.push("y = " + num(e.y, 0));
    p.push("w = " + num(e.w, 0.1));
    p.push("h = " + num(e.h, 0.1));
    if (e.type !== "image" && e.bg) p.push("bg = " + hexToRgbLua(e.bg));
    if (e.bgTransparency != null && e.bgTransparency !== "") p.push("bgTransparency = " + num(e.bgTransparency, 0));
    if (e.corner) p.push("corner = " + num(e.corner, 0));
    if (e.borderThickness) {
      p.push("borderColor = " + hexToRgbLua(e.borderColor || "#ffffff"));
      p.push("borderThickness = " + num(e.borderThickness, 1));
    }
    if (e.draggable) p.push("draggable = true");
    if (e.type === "label" || e.type === "button" || e.type === "codebox") {
      if (e.text != null) p.push("text = " + q(e.text));
    }
    if (e.type === "label" || e.type === "button" || e.type === "codebox" || e.type === "output") {
      if (e.textColor) p.push("textColor = " + hexToRgbLua(e.textColor));
      if (e.textSize) p.push("textSize = " + num(e.textSize, 16));
    }
    if (e.type === "codebox") p.push("name = " + q(e.name || "main"));
    if (e.type === "image") {
      p.push("image = " + q(normalizeAsset(e.image)));
      if (e.imageColor) p.push("imageColor = " + hexToRgbLua(e.imageColor));
    }
    if (e.type === "button") {
      if (e.action) p.push("action = " + q(e.action));
      else if (e.execute) p.push("execute = " + q(e.execute));
    }
    return "{ " + p.join(", ") + " }";
  }

  function escapeCdata(text) {
    return String(text).split("]]>").join("]]]]><![CDATA[>");
  }

  // Wraps assembled bundle source in a Roblox .rbxmx model: a Script or
  // ModuleScript named SkidSS with a disabled "Client" LocalScript child
  // (same source). injectClient clones that child into PlayerGui.
  function buildRbxmx(source, className) {
    const cls = className === "ModuleScript" ? "ModuleScript" : "Script";
    const src = cls === "ModuleScript" ? source.replace(/\n*$/, "") + "\n\nreturn true\n" : source;
    const cdata = escapeCdata(src);
    return [
      '<roblox version="4">',
      '\t<Item class="' + cls + '" referent="RBX0">',
      "\t\t<Properties>",
      '\t\t\t<string name="Name">SkidSS</string>',
      '\t\t\t<ProtectedString name="Source"><![CDATA[' + cdata + "]]></ProtectedString>",
      "\t\t</Properties>",
      '\t\t<Item class="LocalScript" referent="RBX1">',
      "\t\t\t<Properties>",
      '\t\t\t\t<string name="Name">Client</string>',
      '\t\t\t\t<bool name="Disabled">true</bool>',
      '\t\t\t\t<ProtectedString name="Source"><![CDATA[' + cdata + "]]></ProtectedString>",
      "\t\t\t</Properties>",
      "\t\t</Item>",
      "\t</Item>",
      "</roblox>",
    ].join("\n");
  }

  function buildInterfaceConfig(state) {
    const L = ["function() return {"];
    L.push("\ttitle = " + q(state.title || "SkidSS") + ",");
    L.push("\taccent = " + hexToRgbLua(state.accent) + ",");
    L.push("\tbackground = " + hexToRgbLua(state.background) + ",");
    L.push("\tpanel = " + hexToRgbLua(state.panel) + ",");
    L.push("\ttext = " + hexToRgbLua(state.text) + ",");
    L.push("\ttoggleKey = " + q(state.toggleKey || "RightShift") + ",");
    if (state.width) L.push("\twidth = " + num(state.width, 760) + ",");
    if (state.height) L.push("\theight = " + num(state.height, 480) + ",");
    if (state.openOnJoin) L.push("\topenOnJoin = true,");
    const btns = (state.buttons || []).filter((b) => b.label && b.label.trim());
    if (btns.length) {
      L.push("\tbuttons = {");
      btns.forEach((b) => L.push("\t\t{ label = " + q(b.label) + (b.action ? ", action = " + q(b.action) : "") + " },"));
      L.push("\t},");
    }
    const els = state.elements || [];
    if (els.length) {
      L.push("\telements = {");
      els.forEach((e) => L.push("\t\t" + elementToLua(e) + ","));
      L.push("\t},");
    }
    L.push("} end");
    return L.join("\n");
  }

  function buildConfigSection(state) {
    const validIds = state.userIds.map((s) => parseInt(String(s).trim(), 10)).filter((n) => Number.isFinite(n) && n > 0);
    const validNames = state.names.map((s) => String(s).trim().toLowerCase()).filter((s) => s.length > 0);
    const ids = validIds.length ? "\n" + validIds.map((n) => "\t[" + n + "] = true,").join("\n") + "\n" : "";
    const names = validNames.length ? "\n" + validNames.map((s) => "\t[" + JSON.stringify(s) + "] = true,").join("\n") + "\n" : "";
    return [
      "local WHITELIST_USERIDS = {" + ids + "}",
      "local WHITELIST_NAMES = {" + names + "}",
      "local SETTINGS = {",
      "\tmaxSteps = " + state.settings.maxSteps + ",",
      "\tmaxLoopIterations = " + state.settings.maxLoopIterations + ",",
      "\tmaxWaitSeconds = " + state.settings.maxWaitSeconds + ",",
      "}",
    ].join("\n");
  }

  function parseConfigSection(text) {
    const sIdx = text.indexOf("-- ===== CONFIG");
    const eIdx = text.indexOf("-- ===== END CONFIG");
    if (sIdx === -1 || eIdx === -1) return null;
    const section = text.slice(sIdx, eIdx);
    const userIds = [];
    const userBlock = section.match(/WHITELIST_USERIDS\s*=\s*\{([\s\S]*?)\}/);
    if (userBlock) { const re = /\[\s*(\d+)\s*\]\s*=\s*true/g; let m; while ((m = re.exec(userBlock[1])) !== null) userIds.push(m[1]); }
    const names = [];
    const nameBlock = section.match(/WHITELIST_NAMES\s*=\s*\{([\s\S]*?)\}/);
    if (nameBlock) { const re = /\[\s*"([^"]*)"\s*\]\s*=\s*true/g; let m; while ((m = re.exec(nameBlock[1])) !== null) names.push(m[1]); }
    const settings = { maxSteps: 200000, maxLoopIterations: 100000, maxWaitSeconds: 30 };
    const setBlock = section.match(/SETTINGS\s*=\s*\{([\s\S]*?)\}/);
    if (setBlock) { const re = /(\w+)\s*=\s*(\d+)/g; let m; while ((m = re.exec(setBlock[1])) !== null) settings[m[1]] = Number(m[2]); }
    return { userIds, names, settings };
  }

  return {
    VERBS, ACTION_VERB_IDS, HOOK_VERB_IDS,
    buildRuntimeTable, buildInterfaceConfig, buildConfigSection, parseConfigSection, buildRbxmx,
  };
});
