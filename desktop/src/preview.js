// Renders a mock of the in-game executor window from the Interface form's
// config object, so you can see your UI before building the script.

(function () {
  function render(state) {
    const win = document.getElementById("pv-window");
    if (!win) return;
    const accent = document.getElementById("pv-accent");
    const titlebar = win.querySelector(".pv-titlebar");
    const title = document.getElementById("pv-title");
    const console_ = document.getElementById("pv-console");
    const buttons = document.getElementById("pv-buttons");

    win.style.background = state.bg;
    accent.style.background = state.accent;
    titlebar.style.background = state.panel;
    title.textContent = state.title;
    title.style.color = state.text;

    console_.style.background = state.panel;
    console_.innerHTML = "";
    state.logs.forEach((line) => {
      const el = document.createElement("div");
      el.className = "pv-line";
      el.textContent = line;
      el.style.color = state.text;
      console_.appendChild(el);
    });

    buttons.innerHTML = "";
    state.buttons.forEach((label) => {
      const el = document.createElement("div");
      el.className = "pv-btn";
      el.style.background = state.accent;
      el.style.color = state.text;
      el.textContent = label;
      buttons.appendChild(el);
    });
  }

  window.applyInterfacePreview = function (cfg) {
    render({
      title: cfg.title && cfg.title.trim() ? cfg.title : "SkidSS",
      accent: cfg.accent || "#7c5cff",
      bg: cfg.background || "#16161c",
      panel: cfg.panel || "#20202a",
      text: cfg.text || "#e6e6f0",
      logs: ["SkidSS ready."],
      buttons: (cfg.buttons || []).map((b) => b.label).filter((l) => l && l.trim()),
    });
  };
})();
