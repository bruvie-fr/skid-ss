const http = require("http");
const https = require("https");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const SITE_DIR = path.join(ROOT, "desktop", "src");
const DATA_DIR = path.join(ROOT, "data");
const PROJECTS_DIR = path.join(DATA_DIR, "projects");
const USERS_FILE = path.join(DATA_DIR, "users.json");
const SESSIONS_FILE = path.join(DATA_DIR, "sessions.json");
const PORT = Number(process.argv[2] || process.env.PORT) || 8080;

const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_BODY = 1024 * 1024;
const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;

fs.mkdirSync(PROJECTS_DIR, { recursive: true });

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    return fallback;
  }
}
function writeJson(file, obj) {
  fs.writeFileSync(file, JSON.stringify(obj, null, 2));
}
function projectFile(username) {
  return path.join(PROJECTS_DIR, username.toLowerCase() + ".json");
}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}
function makeUser(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  return { salt, hash: hashPassword(password, salt), pageKey: crypto.randomBytes(9).toString("hex"), createdAt: Date.now() };
}
function verifyPassword(user, password) {
  if (!user) return false;
  const h = hashPassword(password, user.salt);
  const a = Buffer.from(h, "hex");
  const b = Buffer.from(user.hash, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function newSession(username) {
  const sessions = readJson(SESSIONS_FILE, {});

  const now = Date.now();
  for (const t of Object.keys(sessions)) if (sessions[t].expires < now) delete sessions[t];
  const token = crypto.randomBytes(24).toString("hex");
  sessions[token] = { username, expires: now + SESSION_TTL_MS };
  writeJson(SESSIONS_FILE, sessions);
  return token;
}
function usernameFromToken(token) {
  if (!token) return null;
  const sessions = readJson(SESSIONS_FILE, {});
  const s = sessions[token];
  if (!s || s.expires < Date.now()) return null;
  return s.username;
}
function bearer(req) {
  const h = req.headers["authorization"] || "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(body);
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error("body too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) return resolve({});
      try { resolve(JSON.parse(raw)); } catch (e) { reject(new Error("invalid JSON")); }
    });
    req.on("error", reject);
  });
}

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".txt": "text/plain; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".jpg": "image/jpeg", ".ico": "image/x-icon",
};
function serveStatic(req, res, urlPath) {
  if (urlPath === "/") urlPath = "/index.html";
  const filePath = path.join(SITE_DIR, path.normalize(urlPath));
  if (filePath !== SITE_DIR && !filePath.startsWith(SITE_DIR + path.sep)) {
    res.writeHead(403); res.end("forbidden"); return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end("not found"); return; }
    res.writeHead(200, { "content-type": MIME[path.extname(filePath)] || "application/octet-stream", "cache-control": "no-store" });
    res.end(data);
  });
}

let tunnelUrl = null;
function envPublicBase() {
  const v = process.env.PUBLIC_URL || process.env.SKIDSS_PUBLIC_URL || process.env.RENDER_EXTERNAL_URL;
  if (v) return v.replace(/\/+$/, "");
  if (process.env.RAILWAY_PUBLIC_DOMAIN) return "https://" + process.env.RAILWAY_PUBLIC_DOMAIN.replace(/\/+$/, "");
  return null;
}

function publicBase(req) {
  const e = envPublicBase();
  if (e) return e;
  if (tunnelUrl) return tunnelUrl;
  const host = (req && req.headers && req.headers.host) || ("localhost:" + PORT);
  const fwd = req && req.headers && String(req.headers["x-forwarded-proto"] || "").split(",")[0];
  const proto = fwd || (/^(localhost|127\.|0\.0\.0\.0)/.test(host) ? "http" : "https");
  return proto + "://" + host;
}

function startTunnel() {
  let proc;
  try {
    proc = require("child_process").spawn("cloudflared", ["tunnel", "--url", "http://localhost:" + PORT], { stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    console.log("  tunnel: cloudflared not found. Install it, set PUBLIC_URL=..., or deploy for a public URL.");
    return;
  }
  const scan = (buf) => {
    const m = String(buf).match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (m && !tunnelUrl) { tunnelUrl = m[0]; console.log("  public (tunnel): " + tunnelUrl); }
  };
  proc.stdout.on("data", scan);
  proc.stderr.on("data", scan);
  proc.on("error", () => console.log("  tunnel: cloudflared failed to start"));
}

function postDiscord(url, content, username) {
  try {
    const u = new URL(url);
    const payload = { content: content.slice(0, 1900) };
    if (username) payload.username = username;
    const data = JSON.stringify(payload);
    const r = https.request(
      { hostname: u.hostname, path: u.pathname + u.search, method: "POST", headers: { "content-type": "application/json", "content-length": Buffer.byteLength(data) } },
      (resp) => resp.resume()
    );
    r.on("error", () => {});
    r.write(data); r.end();
  } catch (e) {}
}

const DEFAULT_WEBHOOK_TEMPLATE =
  "**{player}** ({userId}) ran the executor in **{game}** — {players} in server\n```\n{script}\n```\nJoin: {joinlink}";

function renderTemplate(tmpl, vars) {
  return String(tmpl).replace(/\{(\w+)\}/g, (m, k) =>
    Object.prototype.hasOwnProperty.call(vars, k) ? String(vars[k]) : m
  );
}

const webhookRate = {};
function findUserByPageKey(pageKey) {
  const users = readJson(USERS_FILE, {});
  return Object.keys(users).find((name) => users[name].pageKey === pageKey) || null;
}
function cleanText(s, n) {
  return String(s == null ? "" : s).replace(/@(everyone|here)/gi, "@​$1").slice(0, n);
}

async function handleApi(req, res, parts) {

  const route = parts.join("/");

  if (req.method === "POST" && route === "signup") {
    const body = await readBody(req);
    const username = String(body.username || "").trim();
    const password = String(body.password || "");
    if (!USERNAME_RE.test(username)) return send(res, 400, { error: "username must be 3–20 letters/digits/underscore" });
    if (password.length < 6) return send(res, 400, { error: "password must be at least 6 characters" });
    const users = readJson(USERS_FILE, {});
    if (users[username.toLowerCase()]) return send(res, 409, { error: "username taken" });
    const user = makeUser(password);
    users[username.toLowerCase()] = user;
    writeJson(USERS_FILE, users);
    writeJson(projectFile(username), { whitelist: { userIds: [], names: [] } });
    return send(res, 200, { token: newSession(username.toLowerCase()), pageKey: user.pageKey, username });
  }

  if (req.method === "POST" && route === "login") {
    const body = await readBody(req);
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    const users = readJson(USERS_FILE, {});
    const user = users[username];
    if (!verifyPassword(user, password)) return send(res, 401, { error: "wrong username or password" });
    return send(res, 200, { token: newSession(username), pageKey: user.pageKey, username });
  }

  if (req.method === "GET" && route === "me") {
    const username = usernameFromToken(bearer(req));
    if (!username) return send(res, 401, { error: "not logged in" });
    const users = readJson(USERS_FILE, {});
    const user = users[username];
    if (!user) return send(res, 401, { error: "unknown user" });
    return send(res, 200, { username, pageKey: user.pageKey });
  }

  if (req.method === "GET" && route === "config") {
    return send(res, 200, { publicUrl: publicBase(req) });
  }

  if (route === "project") {
    const username = usernameFromToken(bearer(req));
    if (!username) return send(res, 401, { error: "not logged in" });
    if (req.method === "GET") {
      return send(res, 200, { project: readJson(projectFile(username), {}) });
    }
    if (req.method === "PUT") {
      const body = await readBody(req);
      if (typeof body.project !== "object" || body.project === null) return send(res, 400, { error: "no project" });
      writeJson(projectFile(username), body.project);
      return send(res, 200, { ok: true });
    }
  }

  if (req.method === "GET" && parts[0] === "whitelist" && parts[1]) {
    const pageKey = parts[1];
    const users = readJson(USERS_FILE, {});
    const hit = Object.keys(users).find((u) => users[u].pageKey === pageKey);
    if (!hit) return send(res, 404, { error: "unknown page" });
    const project = readJson(projectFile(hit), {});
    const wl = (project && project.whitelist) || {};
    return send(res, 200, { userIds: wl.userIds || [], names: wl.names || [] });
  }

  if (req.method === "POST" && parts[0] === "webhook" && parts[1]) {
    const pageKey = parts[1];
    const now = Date.now();
    if (webhookRate[pageKey] && now - webhookRate[pageKey] < 1500) return send(res, 429, { error: "rate limited" });
    webhookRate[pageKey] = now;
    const username = findUserByPageKey(pageKey);
    if (!username) return send(res, 404, { error: "unknown page" });
    const project = readJson(projectFile(username), {});
    const target = project && project.discordWebhook;
    if (!target || !/^https:\/\/(discord(app)?\.com)\/api\/webhooks\//i.test(target)) {
      return send(res, 200, { ok: true, skipped: true });
    }
    const body = await readBody(req);
    const placeId = parseInt(body.placeId, 10) || 0;
    const jobId = String(body.jobId || "");
    const gamelink = "https://www.roblox.com/games/" + placeId;
    const joinlink = jobId
      ? "https://www.roblox.com/games/start?placeId=" + placeId + "&gameInstanceId=" + encodeURIComponent(jobId)
      : gamelink;
    const vars = {
      player: cleanText(body.player, 60),
      userId: String(parseInt(body.userId, 10) || 0),
      game: cleanText(body.place, 80),
      placeId: String(placeId),
      jobId: cleanText(jobId, 80),
      players: String(parseInt(body.players, 10) || 1),
      mode: cleanText(body.mode, 20),
      script: cleanText(body.script, 1500),
      joinlink: joinlink,
      gamelink: gamelink,
    };
    const content = renderTemplate(project.webhookTemplate || DEFAULT_WEBHOOK_TEMPLATE, vars);
    postDiscord(target, content, cleanText(project.webhookUsername || "SkidSS", 80));
    return send(res, 200, { ok: true });
  }

  return send(res, 404, { error: "unknown endpoint" });
}

const server = http.createServer((req, res) => {
  let pathname = "/";
  try { pathname = decodeURIComponent((req.url || "/").split("?")[0]); } catch (e) {}
  if (pathname.startsWith("/api/")) {
    const parts = pathname.slice(5).split("/").filter(Boolean);
    handleApi(req, res, parts).catch((e) => send(res, 400, { error: String(e.message || e) }));
    return;
  }
  if (req.method !== "GET") { res.writeHead(405); res.end("method not allowed"); return; }
  serveStatic(req, res, pathname);
});

server.listen(PORT, () => {
  console.log("SkidSS backend → http://localhost:" + PORT);
  console.log("  site:   " + SITE_DIR);
  console.log("  data:   " + DATA_DIR);
  const e = envPublicBase();
  if (e) console.log("  public: " + e);
  if (process.argv.includes("--tunnel") || process.env.SKIDSS_TUNNEL) startTunnel();
  else if (!e) console.log("  public: local only — run `node server.js --tunnel` (cloudflared) or set PUBLIC_URL=... for a public URL");
});
