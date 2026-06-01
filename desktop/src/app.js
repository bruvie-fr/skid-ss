// SkidSS Studio controller. Script tab = Blockly; Interface / Runtime / Config
// are forms. Interface + Runtime + Config bake into the single-script bundle.

(function () {
  let scriptWs = null;
  let activeTab = "script";
  let bundleTemplate = "";

  const configState = {
    userIds: [],
    names: [],
    settings: { maxSteps: 200000, maxLoopIterations: 100000, maxWaitSeconds: 30 },
  };

  const interfaceState = {
    title: "SkidSS",
    toggleKey: "RightShift",
    width: 760,
    height: 480,
    openOnJoin: false,
    accent: "#7c5cff",
    background: "#16161c",
    panel: "#20202a",
    text: "#ececf6",
    buttons: [], // legacy quick-bar buttons (unused; elements replace them)
    elements: [], // { id, type, x, y, w, h, bg, bgTransparency, corner, text, textColor, textSize, image, imageColor, action }
  };

  const runtimeState = {
    actions: [], // { name, mode:"verb"|"lua", verb, target, param, targetName, lua }
    join: [], // { verb, param }
    leave: [],
    gateLua: false,
  };

  // Pure codegen lives in codegen.js so it can be unit-tested under Node.
  const CG = window.SkidCodegen;
  const VERBS = CG.VERBS;
  const ACTION_VERB_IDS = CG.ACTION_VERB_IDS;
  const HOOK_VERB_IDS = CG.HOOK_VERB_IDS;
  const escapeHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const buildConfigSection = (s) => CG.buildConfigSection(s);
  const parseConfigSection = (t) => CG.parseConfigSection(t);
  const buildInterfaceConfig = () => CG.buildInterfaceConfig(interfaceState);
  const buildRuntimeTable = () => CG.buildRuntimeTable(runtimeState);

  // === Blockly (Script tab only) ===========================================

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

  // === Bundle assembly =====================================================

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
    out = replaceSection(out, M_RUNTIME_START, M_RUNTIME_END, buildRuntimeTable());
    out = replaceSection(out, M_INTERFACE_START, M_INTERFACE_END, "local CustomInterface = " + buildInterfaceConfig());
    return out;
  }

  // === Status ==============================================================

  function setStatus(text) {
    const el = document.getElementById("status");
    el.textContent = text;
    if (text) setTimeout(() => { if (el.textContent === text) el.textContent = ""; }, 4000);
  }

  function updateCode() {
    let code = "";
    if (activeTab === "script") code = generate(scriptWs);
    else if (activeTab === "interface") code = "local CustomInterface = " + buildInterfaceConfig();
    else if (activeTab === "runtime") code = buildRuntimeTable();
    else if (activeTab === "config") code = buildConfigSection(configState);
    document.getElementById("codeOut").textContent = code && code.trim() ? code : "-- nothing yet";
  }

  function switchTab(tab) {
    activeTab = tab;
    document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
    document.getElementById("scriptWorkspace").classList.toggle("hidden", tab !== "script");
    document.getElementById("interfacePane").classList.toggle("hidden", tab !== "interface");
    document.getElementById("runtimePane").classList.toggle("hidden", tab !== "runtime");
    document.getElementById("configPane").classList.toggle("hidden", tab !== "config");
    document.getElementById("ifSide").classList.toggle("hidden", tab !== "interface");

    if (tab === "script") Blockly.svgResize(scriptWs);
    else if (tab === "interface") renderInterfaceForm();
    else if (tab === "runtime") renderRuntimeForm();
    else if (tab === "config") renderConfigForm();
    updateCode();
  }

  // === Config form =========================================================

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
  }

  function wireConfigForm() {
    document.getElementById("addUserIdBtn").addEventListener("click", () => { configState.userIds.push(""); renderConfigForm(); updateCode(); focusLast("userIdRows"); });
    document.getElementById("addNameBtn").addEventListener("click", () => { configState.names.push(""); renderConfigForm(); updateCode(); focusLast("nameRows"); });
    [["cfgMaxSteps", "maxSteps"], ["cfgMaxLoopIterations", "maxLoopIterations"], ["cfgMaxWaitSeconds", "maxWaitSeconds"]].forEach(([id, key]) => {
      document.getElementById(id).addEventListener("change", (e) => { const v = parseInt(e.target.value, 10); if (!isNaN(v) && v > 0) configState.settings[key] = v; updateCode(); });
    });
    document.getElementById("loadConfigBtn").addEventListener("click", loadConfigFromFile);
  }

  async function loadConfigFromFile() {
    const T = window.__TAURI__;
    if (!(T && T.core && T.dialog && T.dialog.open)) { setStatus("File dialog only works in the Tauri app"); return; }
    try {
      const file = await T.dialog.open({ title: "Pick existing SkidSS.lua", filters: [{ name: "Lua script", extensions: ["lua"] }] });
      if (!file) return;
      const text = await T.core.invoke("read_text", { path: file });
      const parsed = parseConfigSection(text);
      if (!parsed) { setStatus("No CONFIG block found in that file"); return; }
      configState.userIds = parsed.userIds; configState.names = parsed.names;
      Object.assign(configState.settings, parsed.settings);
      renderConfigForm(); updateCode(); setStatus("Loaded CONFIG from " + file);
    } catch (e) { setStatus("Load failed: " + e); }
  }

  // === Interface GUI builder ==============================================

  let selectedId = null;
  let elIdCounter = 0;

  function actionOptions(selected) {
    const opts = ['<option value="">(no action)</option>'];
    runtimeState.actions.forEach((a) => {
      const name = (a.name || "").trim();
      if (name) opts.push('<option value="' + escapeHtml(name) + '"' + (name === selected ? " selected" : "") + ">" + escapeHtml(name) + "</option>");
    });
    return opts.join("");
  }

  function hexToRgba(hex, transparency) {
    hex = hex || "#000000";
    const r = parseInt(hex.slice(1, 3), 16) || 0;
    const g = parseInt(hex.slice(3, 5), 16) || 0;
    const b = parseInt(hex.slice(5, 7), 16) || 0;
    return "rgba(" + r + "," + g + "," + b + "," + (1 - (Number(transparency) || 0)) + ")";
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

  // One-click working executor: a sized code box + output + an Execute button
  // already wired to the code box.
  function addExecutorPreset() {
    const mk = (type, props) => { elIdCounter += 1; return Object.assign({ id: "e" + elIdCounter, type, corner: 6 }, props); };
    // Background panel (added first = behind), draggable so it moves the group.
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

  // Updates a text span (not div.textContent) so resize handles, which are
  // also children of the div, survive re-positioning.
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
      span.textContent = e.image ? "IMG " + e.image : "image";
      span.style.color = ""; span.style.fontSize = "";
    } else {
      span.textContent = "";
    }
  }

  function renderCanvas() {
    const canvas = document.getElementById("ifCanvas");
    if (!canvas) return;
    canvas.style.background = interfaceState.background || "#16161c";
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
    runtimeState.actions.forEach((a) => {
      const name = (a.name || "").trim();
      if (name) {
        const v = "action:" + name;
        opts.push('<option value="' + escapeHtml(v) + '"' + (e.action === name ? " selected" : "") + ">Action: " + escapeHtml(name) + "</option>");
      }
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
    document.querySelectorAll("[data-add]").forEach((b) => b.addEventListener("click", () => addElement(b.dataset.add)));
    const preset = document.querySelector('[data-preset="executor"]');
    if (preset) preset.addEventListener("click", addExecutorPreset);
  }

  // === Runtime form ========================================================

  function verbOptions(ids, selected) {
    return ids.map((id) => '<option value="' + id + '"' + (id === selected ? " selected" : "") + ">" + escapeHtml(VERBS[id].label) + "</option>").join("");
  }

  function buildActionRow(a, idx) {
    const wrap = document.createElement("div"); wrap.className = "action-row";
    const head = document.createElement("div"); head.className = "row";
    const name = document.createElement("input");
    name.type = "text"; name.placeholder = "action name (e.g. freeze)"; name.value = a.name || "";
    name.addEventListener("input", () => { a.name = name.value; updateCode(); });
    const mode = document.createElement("select");
    mode.innerHTML = '<option value="verb">Do a verb</option><option value="lua">Custom Lua</option>';
    mode.value = a.mode || "verb";
    mode.addEventListener("change", () => { a.mode = mode.value; renderActionRows(); updateCode(); });
    const del = document.createElement("button"); del.className = "del"; del.textContent = "×";
    del.addEventListener("click", () => { runtimeState.actions.splice(idx, 1); renderActionRows(); updateCode(); });
    head.appendChild(name); head.appendChild(mode); head.appendChild(del);
    wrap.appendChild(head);

    if ((a.mode || "verb") === "lua") {
      const ta = document.createElement("textarea");
      ta.className = "lua-area";
      ta.placeholder = "-- player, args, emit in scope\nif emit then emit(\"hi\") end";
      ta.value = a.lua || "";
      ta.addEventListener("input", () => { a.lua = ta.value; updateCode(); });
      wrap.appendChild(ta);
    } else {
      const sub = document.createElement("div"); sub.className = "row sub";
      const id = a.verb || "notify";
      const meta = VERBS[id];
      const verb = document.createElement("select");
      verb.innerHTML = verbOptions(ACTION_VERB_IDS, id);
      verb.addEventListener("change", () => { a.verb = verb.value; renderActionRows(); updateCode(); });
      sub.appendChild(verb);
      if (!meta.noTarget) {
        const target = document.createElement("select");
        target.innerHTML = '<option value="self">Triggering player</option><option value="all">All players</option><option value="name">By name</option>';
        target.value = a.target || "self";
        target.addEventListener("change", () => { a.target = target.value; renderActionRows(); updateCode(); });
        sub.appendChild(target);
      }
      if (meta.param) {
        const param = document.createElement("input");
        param.type = meta.param === "number" ? "number" : "text";
        param.placeholder = meta.param; param.value = a.param != null ? a.param : "";
        param.addEventListener("input", () => { a.param = param.value; updateCode(); });
        sub.appendChild(param);
      }
      if (!meta.noTarget && (a.target || "self") === "name") {
        const tn = document.createElement("input");
        tn.type = "text"; tn.placeholder = "player name"; tn.value = a.targetName || "";
        tn.addEventListener("input", () => { a.targetName = tn.value; updateCode(); });
        sub.appendChild(tn);
      }
      wrap.appendChild(sub);
    }
    return wrap;
  }

  function renderActionRows() {
    const box = document.getElementById("actionRows");
    box.innerHTML = "";
    if (runtimeState.actions.length === 0) { box.innerHTML = '<div class="empty">No actions yet. Click + add (e.g. a "freeze" action).</div>'; return; }
    runtimeState.actions.forEach((a, idx) => box.appendChild(buildActionRow(a, idx)));
  }

  function renderHookRows(listKey, containerId) {
    const box = document.getElementById(containerId);
    box.innerHTML = "";
    const list = runtimeState[listKey];
    if (list.length === 0) { box.innerHTML = '<div class="empty">Nothing yet.</div>'; return; }
    list.forEach((r, idx) => {
      const row = document.createElement("div"); row.className = "row sub";
      const id = r.verb || "heal";
      const meta = VERBS[id];
      const verb = document.createElement("select");
      verb.innerHTML = verbOptions(HOOK_VERB_IDS, id);
      verb.addEventListener("change", () => { r.verb = verb.value; renderHookRows(listKey, containerId); updateCode(); });
      row.appendChild(verb);
      if (meta.param) {
        const param = document.createElement("input");
        param.type = meta.param === "number" ? "number" : "text";
        param.placeholder = meta.param; param.value = r.param != null ? r.param : "";
        param.addEventListener("input", () => { r.param = param.value; updateCode(); });
        row.appendChild(param);
      }
      const del = document.createElement("button"); del.className = "del"; del.textContent = "×";
      del.addEventListener("click", () => { list.splice(idx, 1); renderHookRows(listKey, containerId); updateCode(); });
      row.appendChild(del);
      box.appendChild(row);
    });
  }

  function renderRuntimeForm() {
    renderActionRows();
    renderHookRows("join", "joinRows");
    renderHookRows("leave", "leaveRows");
    document.getElementById("rtGateLua").checked = !!runtimeState.gateLua;
  }

  function wireRuntimeForm() {
    document.getElementById("addActionBtn").addEventListener("click", () => {
      runtimeState.actions.push({ name: "", mode: "verb", verb: "freeze", target: "self", param: "" });
      renderActionRows(); updateCode();
      const rows = document.querySelectorAll("#actionRows .action-row");
      if (rows.length) rows[rows.length - 1].querySelector("input").focus();
    });
    document.getElementById("addJoinBtn").addEventListener("click", () => { runtimeState.join.push({ verb: "heal", param: "" }); renderHookRows("join", "joinRows"); updateCode(); });
    document.getElementById("addLeaveBtn").addEventListener("click", () => { runtimeState.leave.push({ verb: "freeze", param: "" }); renderHookRows("leave", "leaveRows"); updateCode(); });
    document.getElementById("rtGateLua").addEventListener("change", (e) => { runtimeState.gateLua = e.target.checked; updateCode(); });
  }

  // === Build / copy ========================================================

  function download(name, contents) {
    const blob = new Blob([contents], { type: "text/plain" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = name; a.click();
    URL.revokeObjectURL(a.href);
  }

  async function buildScript() {
    if (!bundleTemplate) { setStatus("Bundle template not loaded yet"); return; }
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
    if (!bundleTemplate) { setStatus("Bundle template not loaded yet"); return; }
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

  window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".tab").forEach((b) => b.addEventListener("click", () => switchTab(b.dataset.tab)));
    document.getElementById("copyBtn").addEventListener("click", copyTab);
    document.getElementById("copyBundleBtn").addEventListener("click", copyBundle);
    document.getElementById("buildBtn").addEventListener("click", buildScript);
    wireConfigForm();
    wireInterfaceForm();
    wireRuntimeForm();

    scriptWs = injectWs("scriptWorkspace", window.SCRIPT_TOOLBOX);
    scriptWs.addChangeListener(updateCode);
    updateCode();

    window.addEventListener("resize", () => { if (scriptWs && activeTab === "script") Blockly.svgResize(scriptWs); });
    loadBundleTemplate();
  });
})();
