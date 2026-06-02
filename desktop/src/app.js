(function () {
  let scriptWs = null;
  let activeTab = "script";
  let bundleTemplate = "";

  const configState = {
    userIds: [],
    names: [],
    settings: { maxSteps: 200000, maxLoopIterations: 100000, maxWaitSeconds: 30 },
    serverBase: "",
    webhookUrl: "",
    whitelistUrl: "",
    discordWebhook: "",
    webhookUsername: "",
    webhookTemplate: "",
  };

  const interfaceState = {
    title: "SkidSS",
    toggleKey: "RightShift",
    width: 760,
    height: 480,
    openOnJoin: false,
    accent: "#7c5cff",
    background: "#16161c",
    backgroundTransparency: 1,
    panel: "#20202a",
    text: "#ececf6",
    buttons: [],
    elements: [],
  };

  const CG = window.SkidCodegen;
  const escapeHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const buildConfigSection = (s) => CG.buildConfigSection(s);
  const parseConfigSection = (t) => CG.parseConfigSection(t);
  const buildInterfaceConfig = () => CG.buildInterfaceConfig(interfaceState);

  const RUNTIME_DEFAULT = [
    "local CustomRuntime = {",
    "\tonPlayerAdded = function(_player) end,",
    "\tonPlayerRemoving = function(_player) end,",
    "\tonRequestReceived = function(_player, _payload) return true end,",
    "\tcustomActions = {},",
    "}",
  ].join("\n");
  function buildRuntimeSection() {
    const code = generate(scriptWs);
    return code && code.trim() ? RUNTIME_DEFAULT + "\n\n" + code : RUNTIME_DEFAULT;
  }

  function blockActionNames() {
    if (!scriptWs || !scriptWs.getBlocksByType) return [];
    try {
      return scriptWs.getBlocksByType("runtime_register_action", false)
        .map((b) => (b.getFieldValue("NAME") || "").trim())
        .filter((n) => n);
    } catch (e) { return []; }
  }

  function makeTheme() {
    try {
      return Blockly.Theme.defineTheme("skidss", {
        base: Blockly.Themes.Classic,
        componentStyles: {
          workspaceBackgroundColour: "#1b1b22",
          toolboxBackgroundColour: "#22222c",
          toolboxForegroundColour: "#e6e6f0",
          flyoutBackgroundColour: "#1e1e27",
          flyoutForegroundColour: "#c9c9d6",
          flyoutOpacity: 1,
          scrollbarColour: "#3a3a47",
          insertionMarkerColour: "#ffffff",
          insertionMarkerOpacity: 0.3,
        },
      });
    } catch (e) { return undefined; }
  }
  const theme = makeTheme();

  function injectWs(divId, toolbox) {
    return Blockly.inject(divId, {
      toolbox, theme, renderer: "zelos",
      grid: { spacing: 24, length: 2, colour: "#2a2a36", snap: true },
      zoom: { controls: true, wheel: true, startScale: 0.85, maxScale: 2, minScale: 0.4 },
      trashcan: true,
      move: { scrollbars: true, drag: true, wheel: true },
    });
  }

  function generate(ws) {
    if (!ws) return "";
    try { return Blockly.Lua.workspaceToCode(ws); }
    catch (e) { return "-- generation error: " + e; }
  }

  const M_CONFIG_START = "-- ===== CONFIG (edit me, or use Studio to fill these in) =====";
  const M_CONFIG_END = "-- ===== END CONFIG =====";
  const M_RUNTIME_START = "-- ===== CUSTOM RUNTIME (written by Studio; safe to overwrite) =====";
  const M_RUNTIME_END = "-- ===== END CUSTOM RUNTIME =====";
  const M_INTERFACE_START = "-- ===== CUSTOM INTERFACE (written by Studio; safe to overwrite) =====";
  const M_INTERFACE_END = "-- ===== END CUSTOM INTERFACE =====";

  function replaceSection(text, startMarker, endMarker, newContent) {
    const s = text.indexOf(startMarker);
    const e = text.indexOf(endMarker);
    if (s === -1 || e === -1 || e < s) return text;
    return text.slice(0, s + startMarker.length) + "\n" + newContent + "\n" + text.slice(e);
  }

  function assembleBundle(template) {
    let out = replaceSection(template, M_CONFIG_START, M_CONFIG_END, buildConfigSection(configState));
    out = replaceSection(out, M_RUNTIME_START, M_RUNTIME_END, buildRuntimeSection());
    out = replaceSection(out, M_INTERFACE_START, M_INTERFACE_END, "local CustomInterface = " + buildInterfaceConfig());
    return out;
  }

  function setStatus(text) {
    const el = document.getElementById("status");
    el.textContent = text;
    if (text) setTimeout(() => { if (el.textContent === text) el.textContent = ""; }, 4000);
  }

  function updateCode() {
    let code = "";
    if (activeTab === "script") code = buildRuntimeSection();
    else if (activeTab === "interface") code = "local CustomInterface = " + buildInterfaceConfig();
    else if (activeTab === "config") code = buildConfigSection(configState);
    document.getElementById("codeOut").textContent = code && code.trim() ? code : "-- nothing yet";
  }

  function switchTab(tab) {
    activeTab = tab;
    document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
    document.getElementById("scriptWorkspace").classList.toggle("hidden", tab !== "script");
    document.getElementById("interfacePane").classList.toggle("hidden", tab !== "interface");
    document.getElementById("configPane").classList.toggle("hidden", tab !== "config");
    document.getElementById("ifSide").classList.toggle("hidden", tab !== "interface");

    if (tab === "script") Blockly.svgResize(scriptWs);
    else if (tab === "interface") renderInterfaceForm();
    else if (tab === "config") renderConfigForm();
    updateCode();
  }

  function renderRow(container, value, onLive, onDelete, placeholder) {
    const row = document.createElement("div");
    row.className = "row";
    const input = document.createElement("input");
    input.type = "text"; input.value = value; input.placeholder = placeholder;
    input.addEventListener("input", () => onLive(input.value));
    const del = document.createElement("button");
    del.className = "del"; del.textContent = "×";
    del.addEventListener("click", onDelete);
    row.appendChild(input); row.appendChild(del);
    container.appendChild(row);
    return input;
  }

  function focusLast(containerId) {
    const inputs = document.querySelectorAll("#" + containerId + " input");
    if (inputs.length) { const last = inputs[inputs.length - 1]; last.focus(); last.select(); }
  }

  function renderConfigForm() {
    const userBox = document.getElementById("userIdRows");
    userBox.innerHTML = "";
    if (configState.userIds.length === 0) userBox.innerHTML = '<div class="empty">No UserIds yet. Click + add to gate the executor.</div>';
    else configState.userIds.forEach((id, idx) => renderRow(userBox, String(id),
      (v) => { configState.userIds[idx] = String(v); updateCode(); },
      () => { configState.userIds.splice(idx, 1); renderConfigForm(); updateCode(); }, "123456789"));

    const nameBox = document.getElementById("nameRows");
    nameBox.innerHTML = "";
    if (configState.names.length === 0) nameBox.innerHTML = '<div class="empty">No names. Click + add (prefer UserIds — names change).</div>';
    else configState.names.forEach((name, idx) => renderRow(nameBox, name,
      (v) => { configState.names[idx] = String(v); updateCode(); },
      () => { configState.names.splice(idx, 1); renderConfigForm(); updateCode(); }, "yourusername"));

    document.getElementById("cfgMaxSteps").value = configState.settings.maxSteps;
    document.getElementById("cfgMaxLoopIterations").value = configState.settings.maxLoopIterations;
    document.getElementById("cfgMaxWaitSeconds").value = configState.settings.maxWaitSeconds;
    updatePageInfo();
  }

  function wireConfigForm() {
    document.getElementById("addUserIdBtn").addEventListener("click", () => { configState.userIds.push(""); renderConfigForm(); updateCode(); focusLast("userIdRows"); });
    document.getElementById("addNameBtn").addEventListener("click", () => { configState.names.push(""); renderConfigForm(); updateCode(); focusLast("nameRows"); });
    [["cfgMaxSteps", "maxSteps"], ["cfgMaxLoopIterations", "maxLoopIterations"], ["cfgMaxWaitSeconds", "maxWaitSeconds"]].forEach(([id, key]) => {
      document.getElementById(id).addEventListener("change", (e) => { const v = parseInt(e.target.value, 10); if (!isNaN(v) && v > 0) configState.settings[key] = v; updateCode(); });
    });
    document.getElementById("loadConfigBtn").addEventListener("click", loadConfigFromFile);
  }

  function applyLoadedConfig(text, sourceName) {
    const parsed = parseConfigSection(text);
    if (!parsed) { setStatus("No CONFIG block found in that file"); return; }
    configState.userIds = parsed.userIds; configState.names = parsed.names;
    Object.assign(configState.settings, parsed.settings);
    if (parsed.whitelistUrl) configState.whitelistUrl = parsed.whitelistUrl;
    if (parsed.webhookUrl) configState.webhookUrl = parsed.webhookUrl;
    renderConfigForm(); updateCode(); setStatus("Loaded CONFIG from " + sourceName);
  }

  async function loadConfigFromFile() {
    const T = window.__TAURI__;
    if (T && T.core && T.dialog && T.dialog.open) {

      try {
        const file = await T.dialog.open({ title: "Pick existing SkidSS.lua", filters: [{ name: "Lua script", extensions: ["lua"] }] });
        if (!file) return;
        const text = await T.core.invoke("read_text", { path: file });
        applyLoadedConfig(text, file);
      } catch (e) { setStatus("Load failed: " + e); }
      return;
    }

    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".lua,.txt";
    input.addEventListener("change", () => {
      const file = input.files && input.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => applyLoadedConfig(String(reader.result || ""), file.name);
      reader.onerror = () => setStatus("Load failed: " + reader.error);
      reader.readAsText(file);
    });
    input.click();
  }

  let selectedId = null;
  let elIdCounter = 0;

  function hexToRgba(hex, transparency) {
    hex = hex || "#000000";
    const r = parseInt(hex.slice(1, 3), 16) || 0;
    const g = parseInt(hex.slice(3, 5), 16) || 0;
    const b = parseInt(hex.slice(5, 7), 16) || 0;
    return "rgba(" + r + "," + g + "," + b + "," + (1 - (Number(transparency) || 0)) + ")";
  }

  function imagePreviewUrl(v) {
    v = String(v == null ? "" : v).trim();
    if (!v) return "";
    let id = null;
    if (/^\d+$/.test(v)) id = v;
    else { const m = v.match(/^rbxassetid:\/\/(\d+)$/i); if (m) id = m[1]; }
    if (id) return "https://www.roblox.com/asset-thumbnail/image?assetId=" + id + "&width=420&height=420&format=png";
    if (/^https?:\/\//i.test(v)) return v;
    return "";
  }

  function defaultElement(type) {
    elIdCounter += 1;
    const stagger = (elIdCounter % 6) * 0.03;
    const base = { id: "e" + elIdCounter, type, x: 0.06 + stagger, y: 0.08 + stagger, w: 0.18, h: 0.1, corner: 8 };
    if (type === "label") return Object.assign(base, { h: 0.06, text: "Label", textColor: "#ffffff", textSize: 18, bg: "#000000", bgTransparency: 1, corner: 0 });
    if (type === "button") return Object.assign(base, { h: 0.07, text: "Button", textColor: "#ffffff", textSize: 16, bg: "#7c5cff", bgTransparency: 0, action: "", execute: "" });
    if (type === "image") return Object.assign(base, { w: 0.12, h: 0.21, image: "", imageColor: "#ffffff", bg: "#000000", bgTransparency: 1, corner: 0 });
    if (type === "codebox") return Object.assign(base, { w: 0.3, h: 0.18, name: "main", text: "", textColor: "#d4d4e2", textSize: 14, bg: "#15151b", bgTransparency: 0, corner: 6 });
    if (type === "output") return Object.assign(base, { w: 0.3, h: 0.18, textColor: "#9fe0b0", textSize: 13, bg: "#15151b", bgTransparency: 0, corner: 6 });
    return Object.assign(base, { bg: "#202028", bgTransparency: 0 });
  }

  function addExecutorPreset() {
    const mk = (type, props) => { elIdCounter += 1; return Object.assign({ id: "e" + elIdCounter, type, corner: 6 }, props); };

    const bg = mk("panel", { x: 0.02, y: 0.05, w: 0.56, h: 0.66, bg: "#16161c", bgTransparency: 0.04, corner: 10, borderColor: "#2c2c38", borderThickness: 1, draggable: true });
    const title = mk("label", { text: "Executor — drag here", x: 0.04, y: 0.07, w: 0.5, h: 0.04, bg: "#000000", bgTransparency: 1, textColor: "#8a8a9a", textSize: 14, corner: 0 });
    const cb = mk("codebox", { name: "main", x: 0.04, y: 0.13, w: 0.52, h: 0.3, bg: "#15151b", bgTransparency: 0, textColor: "#d4d4e2", textSize: 14, text: 'print("hello")' });
    const out = mk("output", { x: 0.04, y: 0.45, w: 0.52, h: 0.16, bg: "#15151b", bgTransparency: 0, textColor: "#9fe0b0", textSize: 13 });
    const btn = mk("button", { text: "Execute", x: 0.04, y: 0.63, w: 0.16, h: 0.06, bg: "#7c5cff", textColor: "#ffffff", textSize: 16, action: "", execute: "main" });
    interfaceState.elements.push(bg, title, cb, out, btn);
    selectedId = btn.id;
    renderCanvas(); renderProps(); updateCode();
  }

  function addElement(type) {
    const el = defaultElement(type);
    interfaceState.elements.push(el);
    selectedId = el.id;
    renderCanvas(); renderProps(); updateCode();
  }

  function selectedElement() {
    return interfaceState.elements.find((e) => e.id === selectedId) || null;
  }

  function positionDiv(div, e) {
    div.style.left = (e.x * 100) + "%";
    div.style.top = (e.y * 100) + "%";
    div.style.width = (e.w * 100) + "%";
    div.style.height = (e.h * 100) + "%";
    div.style.borderRadius = (e.corner || 0) + "px";
    div.style.background = e.type === "image" ? "rgba(255,255,255,0.06)" : hexToRgba(e.bg, e.bgTransparency);
    div.style.border = Number(e.borderThickness) > 0
      ? Math.min(4, Number(e.borderThickness)) + "px solid " + (e.borderColor || "#fff")
      : "none";
    let span = div.querySelector(".el-text");
    if (!span) { span = document.createElement("span"); span.className = "el-text"; div.appendChild(span); }
    if (e.type === "label" || e.type === "button") {
      span.textContent = e.text || "";
      span.style.color = e.textColor || "#fff";
      span.style.fontSize = Math.max(8, Math.round((e.textSize || 14) * 0.72)) + "px";
    } else if (e.type === "codebox") {
      span.textContent = e.text && e.text.trim() ? e.text : "-- code box";
      span.style.color = e.textColor || "#d4d4e2";
      span.style.fontSize = Math.max(8, Math.round((e.textSize || 14) * 0.72)) + "px";
    } else if (e.type === "output") {
      span.textContent = "output…";
      span.style.color = e.textColor || "#9fe0b0";
      span.style.fontSize = Math.max(8, Math.round((e.textSize || 13) * 0.72)) + "px";
    } else if (e.type === "image") {

      div.style.backgroundImage = "";
      const url = imagePreviewUrl(e.image);
      const placeholder = e.image ? "🖼 #" + e.image : "🖼 image";
      let img = div.querySelector("img.el-img");
      if (!url) {
        if (img) img.remove();
        span.textContent = placeholder;
      } else {
        if (!img) {
          img = document.createElement("img");
          img.className = "el-img";
          img.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:contain;pointer-events:none;";
          div.insertBefore(img, div.firstChild);
        }
        img.onload = function () { span.textContent = ""; };
        img.onerror = function () { if (img && img.parentNode) img.parentNode.removeChild(img); span.textContent = placeholder; };
        if (img.getAttribute("src") !== url) img.src = url;
        span.textContent = (img.complete && img.naturalWidth) ? "" : placeholder;
      }
      span.style.color = "#9a9aa8"; span.style.fontSize = "11px";
    } else {
      span.textContent = "";
    }
  }

  function renderCanvas() {
    const canvas = document.getElementById("ifCanvas");
    if (!canvas) return;
    canvas.style.background = hexToRgba(interfaceState.background || "#16161c", interfaceState.backgroundTransparency || 0);
    canvas.innerHTML = "";
    interfaceState.elements.forEach((e) => {
      const div = document.createElement("div");
      div.className = "el el-" + e.type + (e.id === selectedId ? " selected" : "");
      positionDiv(div, e);
      div.addEventListener("mousedown", (ev) => startDrag(ev, e, canvas));
      if (e.id === selectedId) {
        ["nw", "ne", "sw", "se"].forEach((corner) => {
          const handle = document.createElement("div");
          handle.className = "handle handle-" + corner;
          handle.addEventListener("mousedown", (ev) => startResize(ev, e, div, canvas, corner));
          div.appendChild(handle);
        });
      }
      canvas.appendChild(div);
    });
  }

  function startDrag(ev, e, canvas) {
    ev.preventDefault();
    if (selectedId !== e.id) {
      selectedId = e.id;
      renderCanvas();
      renderProps();
    }
    const div = canvas.querySelector(".el.selected");
    if (!div) return;
    const rect = canvas.getBoundingClientRect();
    const offX = (ev.clientX - rect.left) / rect.width - e.x;
    const offY = (ev.clientY - rect.top) / rect.height - e.y;
    const onMove = (m) => {
      e.x = Math.max(0, Math.min(1 - e.w, (m.clientX - rect.left) / rect.width - offX));
      e.y = Math.max(0, Math.min(1 - e.h, (m.clientY - rect.top) / rect.height - offY));
      positionDiv(div, e);
    };
    const onUp = () => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);
      updateCode();
    };
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  }

  function startResize(ev, e, div, canvas, corner) {
    ev.preventDefault();
    ev.stopPropagation();
    const rect = canvas.getBoundingClientRect();
    const start = { mx: ev.clientX, my: ev.clientY, x: e.x, y: e.y, w: e.w, h: e.h };
    const MIN = 0.03;
    const onMove = (m) => {
      const dx = (m.clientX - start.mx) / rect.width;
      const dy = (m.clientY - start.my) / rect.height;
      let x = start.x, y = start.y, w = start.w, h = start.h;
      if (corner.indexOf("e") !== -1) w = start.w + dx;
      if (corner.indexOf("s") !== -1) h = start.h + dy;
      if (corner.indexOf("w") !== -1) { x = start.x + dx; w = start.w - dx; }
      if (corner.indexOf("n") !== -1) { y = start.y + dy; h = start.h - dy; }
      if (w < MIN) { if (corner.indexOf("w") !== -1) x = start.x + start.w - MIN; w = MIN; }
      if (h < MIN) { if (corner.indexOf("n") !== -1) y = start.y + start.h - MIN; h = MIN; }
      x = Math.max(0, x); y = Math.max(0, y);
      w = Math.min(w, 1 - x); h = Math.min(h, 1 - y);
      e.x = x; e.y = y; e.w = w; e.h = h;
      positionDiv(div, e);
    };
    const onUp = () => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);
      renderProps();
      updateCode();
    };
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  }

  function propRow(label, inputEl) {
    const row = document.createElement("label");
    row.className = "prop";
    const span = document.createElement("span"); span.textContent = label;
    row.appendChild(span); row.appendChild(inputEl);
    return row;
  }
  function numInput(value, step, min, max, onChange) {
    const i = document.createElement("input");
    i.type = "number"; i.value = value; i.step = step;
    if (min != null) i.min = min; if (max != null) i.max = max;
    i.addEventListener("input", () => onChange(i.value));
    return i;
  }
  function textInput(value, onChange) {
    const i = document.createElement("input");
    i.type = "text"; i.value = value == null ? "" : value;
    i.addEventListener("input", () => onChange(i.value));
    return i;
  }
  function colorInput(value, onChange) {
    const i = document.createElement("input");
    i.type = "color"; i.value = value || "#000000";
    i.addEventListener("input", () => onChange(i.value));
    return i;
  }

  function buttonTargetOptions(e) {
    const opts = ['<option value="">(no action)</option>'];
    blockActionNames().forEach((name) => {
      const v = "action:" + name;
      opts.push('<option value="' + escapeHtml(v) + '"' + (e.action === name ? " selected" : "") + ">Action: " + escapeHtml(name) + "</option>");
    });
    interfaceState.elements.filter((x) => x.type === "codebox").forEach((cb) => {
      const name = cb.name || "main";
      const v = "exec:" + name;
      opts.push('<option value="' + escapeHtml(v) + '"' + (e.execute === name ? " selected" : "") + ">Execute code box: " + escapeHtml(name) + "</option>");
    });
    return opts.join("");
  }

  function renderProps() {
    const box = document.getElementById("ifProps");
    if (!box) return;
    const e = selectedElement();
    box.innerHTML = "";
    if (!e) { box.innerHTML = '<div class="empty">Click an element on the canvas to edit it.</div>'; return; }
    const setNum = (key, def) => (v) => { e[key] = Number(v); if (!Number.isFinite(e[key])) e[key] = def; renderCanvas(); updateCode(); };
    const setVal = (key) => (v) => { e[key] = v; renderCanvas(); updateCode(); };

    const grid = document.createElement("div"); grid.className = "prop-grid";
    grid.appendChild(propRow("X (0-1)", numInput(e.x, 0.01, 0, 1, setNum("x", 0))));
    grid.appendChild(propRow("Y (0-1)", numInput(e.y, 0.01, 0, 1, setNum("y", 0))));
    grid.appendChild(propRow("W (0-1)", numInput(e.w, 0.01, 0.02, 1, setNum("w", 0.1))));
    grid.appendChild(propRow("H (0-1)", numInput(e.h, 0.01, 0.02, 1, setNum("h", 0.1))));
    grid.appendChild(propRow("Corner", numInput(e.corner || 0, 1, 0, 64, setNum("corner", 0))));
    box.appendChild(grid);

    if (e.type === "codebox") {
      box.appendChild(propRow("Name (for execute)", textInput(e.name || "main", setVal("name"))));
    }
    if (e.type !== "image") {
      box.appendChild(propRow("Background", colorInput(e.bg, setVal("bg"))));
      box.appendChild(propRow("Transparency", numInput(e.bgTransparency || 0, 0.1, 0, 1, setNum("bgTransparency", 0))));
    }
    if (e.type === "image") {
      box.appendChild(propRow("Asset id", textInput(e.image, setVal("image"))));
      box.appendChild(propRow("Tint", colorInput(e.imageColor || "#ffffff", setVal("imageColor"))));
    }
    if (e.type === "label" || e.type === "button" || e.type === "codebox") {
      box.appendChild(propRow(e.type === "codebox" ? "Starting text" : "Text", textInput(e.text, setVal("text"))));
    }
    if (e.type === "label" || e.type === "button" || e.type === "codebox" || e.type === "output") {
      box.appendChild(propRow("Text color", colorInput(e.textColor || "#ffffff", setVal("textColor"))));
      box.appendChild(propRow("Text size", numInput(e.textSize || 16, 1, 8, 48, setNum("textSize", 16))));
    }

    const bgrid = document.createElement("div"); bgrid.className = "prop-grid";
    bgrid.appendChild(propRow("Border", colorInput(e.borderColor || "#ffffff", setVal("borderColor"))));
    bgrid.appendChild(propRow("Border width", numInput(e.borderThickness || 0, 1, 0, 8, setNum("borderThickness", 0))));
    box.appendChild(bgrid);

    if (e.type === "panel") {
      const row = document.createElement("label"); row.className = "checkrow";
      const cbx = document.createElement("input"); cbx.type = "checkbox"; cbx.checked = !!e.draggable;
      cbx.addEventListener("change", () => { e.draggable = cbx.checked; updateCode(); });
      row.appendChild(cbx);
      row.appendChild(document.createTextNode(" Draggable (moves the whole HUD)"));
      box.appendChild(row);
    }

    if (e.type === "button") {
      const sel = document.createElement("select");
      sel.innerHTML = buttonTargetOptions(e);
      sel.addEventListener("change", () => {
        const v = sel.value;
        if (v.indexOf("action:") === 0) { e.action = v.slice(7); e.execute = ""; }
        else if (v.indexOf("exec:") === 0) { e.execute = v.slice(5); e.action = ""; }
        else { e.action = ""; e.execute = ""; }
        updateCode();
      });
      box.appendChild(propRow("On click", sel));
    }

    const layer = document.createElement("div"); layer.className = "prop-grid";
    const idxOf = () => interfaceState.elements.findIndex((x) => x.id === e.id);
    const mkLayer = (label, fn) => {
      const b = document.createElement("button"); b.className = "btn small"; b.textContent = label;
      b.addEventListener("click", fn); return b;
    };
    layer.appendChild(mkLayer("Send to back", () => {
      const i = idxOf();
      if (i > 0) { const [it] = interfaceState.elements.splice(i, 1); interfaceState.elements.unshift(it); renderCanvas(); renderProps(); updateCode(); }
    }));
    layer.appendChild(mkLayer("Bring to front", () => {
      const i = idxOf();
      if (i !== -1 && i < interfaceState.elements.length - 1) { const [it] = interfaceState.elements.splice(i, 1); interfaceState.elements.push(it); renderCanvas(); renderProps(); updateCode(); }
    }));
    box.appendChild(layer);

    const del = document.createElement("button");
    del.className = "btn small del-el"; del.textContent = "Delete element";
    del.addEventListener("click", () => {
      interfaceState.elements = interfaceState.elements.filter((x) => x.id !== e.id);
      selectedId = null; renderCanvas(); renderProps(); updateCode();
    });
    box.appendChild(del);
  }

  function renderInterfaceForm() {
    const s = interfaceState;
    document.getElementById("ifTitle").value = s.title;
    document.getElementById("ifToggleKey").value = s.toggleKey;
    document.getElementById("ifWidth").value = s.width;
    document.getElementById("ifHeight").value = s.height;
    document.getElementById("ifOpenOnJoin").checked = !!s.openOnJoin;
    document.getElementById("ifAccent").value = s.accent;
    document.getElementById("ifBackground").value = s.background;
    document.getElementById("ifBackgroundTransparency").value = s.backgroundTransparency;
    document.getElementById("ifPanel").value = s.panel;
    document.getElementById("ifText").value = s.text;
    renderCanvas();
    renderProps();
  }

  function wireInterfaceForm() {
    const bind = (id, key, isCheck) => {
      const el = document.getElementById(id);
      const ev = el.tagName === "SELECT" || isCheck ? "change" : "input";
      el.addEventListener(ev, () => {
        interfaceState[key] = isCheck ? el.checked : el.value;
        if (key === "background") renderCanvas();
        updateCode();
      });
    };
    bind("ifTitle", "title"); bind("ifToggleKey", "toggleKey");
    bind("ifWidth", "width"); bind("ifHeight", "height");
    bind("ifOpenOnJoin", "openOnJoin", true);
    bind("ifAccent", "accent"); bind("ifBackground", "background"); bind("ifPanel", "panel"); bind("ifText", "text");
    const bt = document.getElementById("ifBackgroundTransparency");
    if (bt) bt.addEventListener("input", () => {
      interfaceState.backgroundTransparency = Math.max(0, Math.min(1, Number(bt.value) || 0));
      renderCanvas(); updateCode();
    });
    document.querySelectorAll("[data-add]").forEach((b) => b.addEventListener("click", () => addElement(b.dataset.add)));
    const preset = document.querySelector('[data-preset="executor"]');
    if (preset) preset.addEventListener("click", addExecutorPreset);
  }

  function download(name, contents) {
    const blob = new Blob([contents], { type: "text/plain" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = name; a.click();
    URL.revokeObjectURL(a.href);
  }

  async function buildScript() {
    if (!bundleTemplate) { setStatus("Bundle template not loaded — serve over HTTP (node tools/serve-web.js), not file://"); return; }
    if (!window.SkidAuth || !SkidAuth.isLoggedIn()) { openAuth(); setStatus("Log in first — your page provides the live whitelist + webhook"); return; }
    if (!/^https:\/\/(discord(app)?\.com)\/api\/webhooks\//i.test(configState.discordWebhook || "")) {
      switchTab("config"); setStatus("A Discord webhook URL is required (Config → Discord webhook)"); return;
    }
    try { await SkidAuth.putProject(currentProject()); } catch (e) { setStatus("Save failed: " + e.message); return; }
    const bundle = assembleBundle(bundleTemplate);
    const classEl = document.getElementById("buildClass");
    const className = (classEl && classEl.value) || "Script";
    const rbxmx = CG.buildRbxmx(bundle, className);
    const T = window.__TAURI__;
    if (T && T.core && T.dialog && T.dialog.save) {
      try {
        const targetPath = await T.dialog.save({ title: "Save SkidSS model", defaultPath: "SkidSS.rbxmx", filters: [{ name: "Roblox model", extensions: ["rbxmx"] }] });
        if (!targetPath) return;
        await T.core.invoke("save_text", { path: targetPath, contents: rbxmx });
        setStatus("Wrote " + targetPath + " (" + className + ")");
      } catch (e) { setStatus("Build failed: " + e); }
    } else {
      download("SkidSS.rbxmx", rbxmx);
      setStatus("Downloaded SkidSS.rbxmx (" + className + ")");
    }
  }

  async function copyBundle() {
    if (!bundleTemplate) { setStatus("Bundle template not loaded — serve over HTTP (node tools/serve-web.js), not file://"); return; }
    const bundle = assembleBundle(bundleTemplate);
    try { await navigator.clipboard.writeText(bundle); setStatus("Copied SkidSS.lua to clipboard (" + bundle.length + " chars)"); }
    catch (e) { setStatus("Copy failed: " + e); }
  }

  async function copyTab() {
    const code = document.getElementById("codeOut").textContent;
    try { await navigator.clipboard.writeText(code); setStatus("Copied " + activeTab + " Luau"); }
    catch (e) { setStatus("Copy failed: " + e); }
  }

  async function loadBundleTemplate() {
    try { const r = await fetch("bundle-template.txt", { cache: "no-store" }); if (r.ok) bundleTemplate = await r.text(); }
    catch (e) {}
  }

  function currentProject() {
    let blocks = {};
    try { blocks = Blockly.serialization.workspaces.save(scriptWs); } catch (e) {}
    return {
      blocks,
      interface: interfaceState,
      settings: configState.settings,
      whitelist: {
        userIds: configState.userIds.map((s) => parseInt(String(s).trim(), 10)).filter((n) => Number.isFinite(n) && n > 0),
        names: configState.names.map((s) => String(s).trim().toLowerCase()).filter((s) => s.length > 0),
      },
      discordWebhook: configState.discordWebhook || "",
      webhookUsername: configState.webhookUsername || "",
      webhookTemplate: configState.webhookTemplate || "",
    };
  }

  function loadProject(p) {
    p = p || {};
    if (p.blocks && scriptWs) { try { Blockly.serialization.workspaces.load(p.blocks, scriptWs); } catch (e) {} }
    if (p.interface && typeof p.interface === "object") Object.assign(interfaceState, p.interface);
    if (p.whitelist) {
      configState.userIds = (p.whitelist.userIds || []).map(String);
      configState.names = (p.whitelist.names || []).map(String);
    }
    if (p.settings && typeof p.settings === "object") Object.assign(configState.settings, p.settings);
    configState.discordWebhook = p.discordWebhook || "";
    configState.webhookUsername = p.webhookUsername || "";
    configState.webhookTemplate = p.webhookTemplate || "";
    if (activeTab === "interface") renderInterfaceForm();
    else if (activeTab === "config") renderConfigForm();
    updateCode();
  }

  function apiBase() {
    return (configState.serverBase || window.location.origin || "").replace(/\/+$/, "");
  }

  function updatePageInfo() {
    const pk = document.getElementById("cfgPageKey");
    const sb = document.getElementById("cfgServerBase");
    const wl = document.getElementById("wlUrl");
    const wh = document.getElementById("cfgWebhook");
    const key = window.SkidAuth && SkidAuth.state.pageKey;
    if (key) {
      configState.whitelistUrl = apiBase() + "/api/whitelist/" + key;
      configState.webhookUrl = apiBase() + "/api/webhook/" + key;
    }
    if (pk) pk.value = key || "";
    if (sb && document.activeElement !== sb) sb.value = configState.serverBase || "";
    if (wh && document.activeElement !== wh) wh.value = configState.discordWebhook || "";
    const whn = document.getElementById("cfgWebhookName");
    const wht = document.getElementById("cfgWebhookTemplate");
    if (whn && document.activeElement !== whn) whn.value = configState.webhookUsername || "";
    if (wht && document.activeElement !== wht) wht.value = configState.webhookTemplate || "";
    if (wl) wl.textContent = configState.whitelistUrl || "— log in —";
  }

  async function loadServerConfig() {
    try {
      const r = await fetch("/api/config");
      if (!r.ok) return;
      const d = await r.json();
      if (d.publicUrl && !configState.serverBase) { configState.serverBase = d.publicUrl; updatePageInfo(); }
    } catch (e) {}
  }

  function renderAccount() {
    const el = document.getElementById("acct");
    if (!el || !window.SkidAuth) return;
    if (SkidAuth.isLoggedIn()) {
      el.innerHTML = '<span class="acct-name">@' + escapeHtml(SkidAuth.state.username) + '</span> <button id="saveBtn" class="btn">Save page</button> <button id="logoutBtn" class="btn">Log out</button>';
      document.getElementById("saveBtn").addEventListener("click", doSave);
      document.getElementById("logoutBtn").addEventListener("click", () => { SkidAuth.logout(); renderAccount(); updatePageInfo(); setStatus("Logged out"); });
    } else {
      el.innerHTML = '<button id="loginBtn" class="btn">Log in / Sign up</button>';
      document.getElementById("loginBtn").addEventListener("click", openAuth);
    }
  }

  function openAuth() {
    document.getElementById("authMsg").textContent = "Log in to save your page online. It's only editable with your password.";
    document.getElementById("authModal").classList.remove("hidden");
    document.getElementById("authUser").focus();
  }
  function closeAuth() { document.getElementById("authModal").classList.add("hidden"); }

  async function afterAuth() {
    closeAuth(); renderAccount();
    try { loadProject(await SkidAuth.getProject()); } catch (e) {}
    updatePageInfo();
    setStatus("Signed in as @" + SkidAuth.state.username);
  }
  async function doLogin() {
    try { await SkidAuth.login(document.getElementById("authUser").value.trim(), document.getElementById("authPass").value); await afterAuth(); }
    catch (e) { document.getElementById("authMsg").textContent = "Login failed: " + e.message; }
  }
  async function doSignup() {
    try { await SkidAuth.signup(document.getElementById("authUser").value.trim(), document.getElementById("authPass").value); await afterAuth(); }
    catch (e) { document.getElementById("authMsg").textContent = "Sign up failed: " + e.message; }
  }
  async function doSave() {
    if (!SkidAuth.isLoggedIn()) { openAuth(); return; }
    try { await SkidAuth.putProject(currentProject()); setStatus("Saved to your page"); }
    catch (e) { setStatus("Save failed: " + e.message); }
  }
  async function initAccount() {
    if (!window.SkidAuth) return;
    renderAccount();
    if (await SkidAuth.restore()) {
      renderAccount();
      try { loadProject(await SkidAuth.getProject()); } catch (e) {}
      updatePageInfo();
    }
  }

  window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".tab").forEach((b) => b.addEventListener("click", () => switchTab(b.dataset.tab)));
    document.getElementById("copyBtn").addEventListener("click", copyTab);
    document.getElementById("copyBundleBtn").addEventListener("click", copyBundle);
    document.getElementById("buildBtn").addEventListener("click", buildScript);
    wireConfigForm();
    wireInterfaceForm();

    document.getElementById("authLogin").addEventListener("click", doLogin);
    document.getElementById("authSignup").addEventListener("click", doSignup);
    document.getElementById("authClose").addEventListener("click", closeAuth);
    const cfgSb = document.getElementById("cfgServerBase");
    if (cfgSb) cfgSb.addEventListener("input", () => { configState.serverBase = cfgSb.value.trim(); updatePageInfo(); });
    const cfgWh = document.getElementById("cfgWebhook");
    if (cfgWh) cfgWh.addEventListener("input", () => { configState.discordWebhook = cfgWh.value.trim(); });
    const cfgWhName = document.getElementById("cfgWebhookName");
    if (cfgWhName) cfgWhName.addEventListener("input", () => { configState.webhookUsername = cfgWhName.value; });
    const cfgWhTmpl = document.getElementById("cfgWebhookTemplate");
    if (cfgWhTmpl) cfgWhTmpl.addEventListener("input", () => { configState.webhookTemplate = cfgWhTmpl.value; });

    scriptWs = injectWs("scriptWorkspace", window.SCRIPT_TOOLBOX);
    scriptWs.addChangeListener(updateCode);
    updateCode();

    window.addEventListener("resize", () => { if (scriptWs && activeTab === "script") Blockly.svgResize(scriptWs); });
    loadBundleTemplate();
    loadServerConfig();
    initAccount();
  });
})();
