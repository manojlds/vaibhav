import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import Fastify from "fastify";
import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import fastifyStatic from "@fastify/static";
import * as pty from "@lydell/node-pty";
import { WebSocketServer } from "ws";

const execFileAsync = promisify(execFile);

const PORT = parseInt(process.env.PORT || "9090", 10);
const HOST = process.env.HOST || "127.0.0.1";
const SHARE_DIR = path.join(homedir(), "vaibhav-share");
const GHOSTTY_DIST = path.dirname(
  new URL(import.meta.resolve("ghostty-web")).pathname,
);

// Ensure share directory exists
await fs.mkdir(SHARE_DIR, { recursive: true });

// --- Fastify setup ---
const app = Fastify({ logger: false });
await app.register(cors, { origin: true });
await app.register(multipart, { limits: { fileSize: 50 * 1024 * 1024 } });

// Serve ghostty-web assets (JS + WASM) at /ghostty/
await app.register(fastifyStatic, {
  root: GHOSTTY_DIST,
  prefix: "/ghostty/",
  decorateReply: false,
});

// Serve shared files at /files/ with directory listing
await app.register(fastifyStatic, {
  root: SHARE_DIR,
  prefix: "/files/",
  decorateReply: false,
  index: false,
  list: {
    format: "html",
    render(dirs, files) {
      const items = [
        ...dirs.map((d) => `<li>📁 <a href="${d.href}">${d.name}/</a></li>`),
        ...files.map((f) => `<li>📄 <a href="${f.href}">${f.name}</a></li>`),
      ];
      return `<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Files</title><style>body{font-family:system-ui;background:#1a1a2e;color:#e0e0e0;padding:20px}
a{color:#00d9ff;text-decoration:none}a:hover{text-decoration:underline}
ul{list-style:none;padding:0}li{padding:8px 0;font-size:1.1em}</style></head>
<body><h2>📁 Shared Files</h2><ul>${items.length ? items.join("") : "<li>No files yet</li>"}</ul></body></html>`;
    },
  },
});

// Serve public UI (decorateReply: true for sendFile support)
await app.register(fastifyStatic, {
  root: path.join(import.meta.dirname, "public"),
  prefix: "/",
});

// --- Helpers ---
const PROJECTS_FILE = path.join(
  process.env.XDG_CONFIG_HOME || path.join(homedir(), ".config"),
  "vaibhav",
  "projects",
);

function tmuxEnv() {
  return {
    ...process.env,
    PATH: `${path.join(homedir(), "bin")}:${path.join(homedir(), ".cargo", "bin")}:${process.env.PATH}`,
  };
}

async function tmuxExec(args, timeout = 5000) {
  const { stdout } = await execFileAsync("tmux", args, {
    timeout,
    env: tmuxEnv(),
  });
  return stdout;
}

async function loadProjects() {
  try {
    const content = await fs.readFile(PROJECTS_FILE, "utf8");
    return content
      .split("\n")
      .filter((l) => l.trim() && !l.startsWith("#"))
      .map((l) => {
        const eq = l.indexOf("=");
        return { name: l.slice(0, eq), path: l.slice(eq + 1) };
      });
  } catch {
    return [];
  }
}

async function activeTmuxSessions() {
  try {
    const out = await tmuxExec([
      "list-sessions",
      "-F",
      "#{session_name}",
    ]);
    return out.trim().split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

// --- API routes (tmux-native) ---
app.get("/api/status", async () => {
  const [projects, sessions] = await Promise.all([
    loadProjects(),
    activeTmuxSessions(),
  ]);
  const activeSet = new Set(sessions);
  return {
    projects: projects.map((p) => ({
      ...p,
      active: activeSet.has(p.name),
    })),
    sessions,
  };
});

app.post("/api/kill", async (req) => {
  const { session = "" } = req.body || {};
  if (!session) return { ok: false, error: "session name required" };
  try {
    await tmuxExec(["kill-session", "-t", session]);
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

app.post("/api/open", async (req) => {
  const { project = "", tool = "" } = req.body || {};
  if (!project) return { ok: false, error: "project name required" };

  const projects = await loadProjects();
  const proj = projects.find((p) => p.name === project);
  if (!proj) return { ok: false, error: `project not found: ${project}` };

  const sessions = await activeTmuxSessions();
  const exists = sessions.includes(project);

  try {
    if (exists) {
      // Session exists — add tool window if requested
      if (tool) {
        const winOut = await tmuxExec([
          "list-windows",
          "-t",
          project,
          "-F",
          "#{window_name}",
        ]);
        const windows = winOut.trim().split("\n").filter(Boolean);
        if (!windows.includes(tool)) {
          await tmuxExec([
            "new-window",
            "-t",
            project,
            "-n",
            tool,
            "-c",
            proj.path,
            tool,
          ]);
        }
        await tmuxExec(["select-window", "-t", `${project}:${tool}`]);
      }
    } else {
      // Create new session
      if (tool) {
        await tmuxExec([
          "new-session",
          "-d",
          "-s",
          project,
          "-c",
          proj.path,
          "-n",
          tool,
          tool,
        ]);
        await tmuxExec([
          "new-window",
          "-t",
          project,
          "-n",
          "shell",
          "-c",
          proj.path,
        ]);
        await tmuxExec(["select-window", "-t", `${project}:${tool}`]);
      } else {
        await tmuxExec([
          "new-session",
          "-d",
          "-s",
          project,
          "-c",
          proj.path,
          "-n",
          "shell",
        ]);
      }
    }
    return { ok: true, session: project };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

// --- Upload ---
app.post("/api/upload", async (req, reply) => {
  const data = await req.file();
  if (!data) {
    return reply.code(400).send({ ok: false, error: "No file provided" });
  }

  const subdir = (data.fields.subdir?.value || "")
    .replace(/\.\./g, "")
    .replace(/^\/+|\/+$/g, "");
  const original = path.basename(data.filename);
  const now = new Date();
  const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}-${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}${String(now.getSeconds()).padStart(2, "0")}`;
  const filename = `${stamp}_${original}`;

  const destDir = subdir
    ? path.join(SHARE_DIR, subdir)
    : SHARE_DIR;
  await fs.mkdir(destDir, { recursive: true });
  const destPath = path.join(destDir, filename);

  const chunks = [];
  for await (const chunk of data.file) {
    chunks.push(chunk);
  }
  await fs.writeFile(destPath, Buffer.concat(chunks));

  const relPath = subdir ? `${subdir}/${filename}` : filename;
  return {
    ok: true,
    filename,
    path: destPath,
    url: `/files/${relPath}`,
  };
});

// --- Clean URL routes ---
app.get("/terminal", async (req, reply) => {
  return reply.sendFile("terminal.html");
});

app.get("/upload", async (req, reply) => {
  return reply.sendFile("upload.html");
});

// --- tmux session list for terminal picker ---
app.get("/api/tmux-sessions", async () => {
  try {
    const { stdout } = await execFileAsync("tmux", [
      "list-sessions",
      "-F",
      "#{session_name}:#{session_windows}:#{session_attached}",
    ], { timeout: 3000, env: tmuxEnv() });
    const sessions = stdout
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const [name, windows, attached] = line.split(":");
        return { name, windows: parseInt(windows), attached: parseInt(attached) > 0 };
      });
    return { ok: true, sessions };
  } catch {
    return { ok: true, sessions: [] };
  }
});

// --- WebSocket PTY for ghostty-web ---
const wss = new WebSocketServer({ noServer: true });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const session = url.pathname.replace(/^\/ws\/?/, "").replace(/\/$/, "");
  const cols = parseInt(url.searchParams.get("cols") || "120", 10);
  const rows = parseInt(url.searchParams.get("rows") || "30", 10);

  console.log(`[ws] connect session="${session}" cols=${cols} rows=${rows}`);

  // Attach to tmux session, or spawn a plain shell if no session specified
  let cmd, args;
  if (session) {
    cmd = "tmux";
    args = ["attach-session", "-t", session];
  } else {
    cmd = process.env.SHELL || "/bin/bash";
    args = [];
  }

  const ptyProcess = pty.spawn(cmd, args, {
    name: "xterm-256color",
    cols,
    rows,
    cwd: homedir(),
    env: { ...process.env, TERM: "xterm-256color", COLORTERM: "truecolor" },
  });

  ptyProcess.onData((data) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(data);
    }
  });

  ptyProcess.onExit(({ exitCode, signal }) => {
    console.log(`[ws] pty exit code=${exitCode} signal=${signal} session="${session}"`);
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, `PTY exited with code ${exitCode}`);
    }
  });

  // Keepalive ping every 30s to prevent proxy timeouts
  const pingInterval = setInterval(() => {
    if (ws.readyState === ws.OPEN) {
      ws.ping();
    }
  }, 30000);

  ws.on("message", (msg, isBinary) => {
    if (isBinary) {
      // Binary messages (e.g. mouse wheel sequences) - write raw bytes
      ptyProcess.write(Buffer.from(msg));
      return;
    }
    const str = msg.toString("utf8");
    // Resize messages are JSON
    if (str.startsWith("{")) {
      try {
        const parsed = JSON.parse(str);
        if (parsed.type === "resize") {
          ptyProcess.resize(parsed.cols, parsed.rows);
          return;
        }
      } catch {
        // not JSON, treat as input
      }
    }
    ptyProcess.write(str);
  });

  ws.on("close", (code, reason) => {
    console.log(`[ws] close code=${code} reason="${reason}" session="${session}"`);
    clearInterval(pingInterval);
    ptyProcess.kill();
  });

  ws.on("error", (err) => {
    console.error(`[ws] error session="${session}":`, err.message);
  });
});

// Wire up WebSocket upgrade on the raw Node server
app.server.on("upgrade", (req, socket, head) => {
  if (req.url?.startsWith("/ws")) {
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  } else {
    socket.destroy();
  }
});

// --- Start ---
await app.listen({ port: PORT, host: HOST });
console.log(`Vaibhav server on ${HOST}:${PORT}`);
console.log(`  Terminal: /terminal`);
console.log(`  Upload:   /upload`);
console.log(`  Files:    /files/`);
console.log(`  API:      /api/status`);
