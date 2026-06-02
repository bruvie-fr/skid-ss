(function () {
  const TOKEN_KEY = "skidss_token";
  const state = { token: localStorage.getItem(TOKEN_KEY) || null, username: null, pageKey: null };

  async function api(pathName, opts) {
    opts = opts || {};
    const headers = { "content-type": "application/json" };
    if (state.token) headers["authorization"] = "Bearer " + state.token;
    const res = await fetch(pathName, {
      method: opts.method || "GET",
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    });
    let data = {};
    try { data = await res.json(); } catch (e) {}
    if (!res.ok) throw new Error(data.error || ("HTTP " + res.status));
    return data;
  }

  function setSession(d) {
    state.token = d.token; state.username = d.username; state.pageKey = d.pageKey;
    localStorage.setItem(TOKEN_KEY, d.token);
  }
  function clear() {
    state.token = null; state.username = null; state.pageKey = null;
    localStorage.removeItem(TOKEN_KEY);
  }

  window.SkidAuth = {
    state,
    isLoggedIn: () => !!state.token && !!state.username,
    async signup(u, p) { setSession(await api("/api/signup", { method: "POST", body: { username: u, password: p } })); return state; },
    async login(u, p) { setSession(await api("/api/login", { method: "POST", body: { username: u, password: p } })); return state; },
    logout() { clear(); },

    async restore() {
      if (!state.token) return false;
      try { const d = await api("/api/me"); state.username = d.username; state.pageKey = d.pageKey; return true; }
      catch (e) { clear(); return false; }
    },
    async getProject() { return (await api("/api/project")).project; },
    async putProject(project) { return api("/api/project", { method: "PUT", body: { project } }); },
  };
})();
