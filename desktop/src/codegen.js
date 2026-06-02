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
    L.push("\tbackgroundTransparency = " + num(state.backgroundTransparency, 0) + ",");
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
      "local WHITELIST_URL = " + (state.whitelistUrl ? JSON.stringify(state.whitelistUrl) : "nil"),
      "local WEBHOOK_URL = " + (state.webhookUrl ? JSON.stringify(state.webhookUrl) : "nil"),
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
    const urlMatch = section.match(/WHITELIST_URL\s*=\s*"([^"]*)"/);
    const webhookMatch = section.match(/WEBHOOK_URL\s*=\s*"([^"]*)"/);
    return { userIds, names, settings, whitelistUrl: urlMatch ? urlMatch[1] : "", webhookUrl: webhookMatch ? webhookMatch[1] : "" };
  }

  return {
    buildInterfaceConfig, buildConfigSection, parseConfigSection, buildRbxmx,
  };
});
