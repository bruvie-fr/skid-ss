const fs = require("fs");
const http = require("http");
const path = require("path");

const root = path.resolve(__dirname, "..", "desktop", "src");
const port = Number(process.argv[2] || process.env.PORT) || 5173;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
};

http
  .createServer((req, res) => {
    let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    if (urlPath === "/") urlPath = "/index.html";
    const filePath = path.join(root, path.normalize(urlPath));

    if (filePath !== root && !filePath.startsWith(root + path.sep)) {
      res.statusCode = 403;
      res.end("forbidden");
      return;
    }
    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.statusCode = 404;
        res.end("not found: " + urlPath);
        return;
      }
      res.setHeader("content-type", MIME[path.extname(filePath)] || "application/octet-stream");
      res.setHeader("cache-control", "no-store");
      res.end(data);
    });
  })
  .listen(port, () => {
    console.log("SkidSS Studio (web) → http://localhost:" + port);
    console.log("serving " + root);
  });
