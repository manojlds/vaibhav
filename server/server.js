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

const DEVSERVERS_FILE = path.join(
  process.env.XDG_CONFIG_HOME || path.join(homedir(), ".config"),
  "vaibhav",
  "devservers",
);

function tmuxEnv() {
  const pathParts = [
    path.join(homedir(), ".nix-profile", "bin"),
    "/nix/var/nix/profiles/default/bin",
    path.join(homedir(), "bin"),
    path.join(homedir(), ".cargo", "bin"),
    process.env.PATH || "",
  ];

  return {
    ...process.env,
    PATH: pathParts.join(":"),
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

function normalizePort(rawPort) {
  if (rawPort === null || rawPort === undefined) return null;
  const parsed = Number.parseInt(String(rawPort), 10);
  if (!Number.isFinite(parsed) || parsed < 1 || parsed > 65535) return null;
  return parsed;
}

function uniquePorts(ports) {
  return [...new Set(ports.map(normalizePort).filter((p) => p !== null))];
}

async function portIsOpen(port) {
  const normalized = normalizePort(port);
  if (!normalized) return false;

  try {
    await execFileAsync("bash", ["-lc", `echo >/dev/tcp/127.0.0.1/${normalized}`], {
      timeout: 2000,
      env: tmuxEnv(),
    });
    return true;
  } catch {
    return false;
  }
}

function extractPortsFromText(text) {
  const rawPorts = [];

  const hostPortPattern = /(?:127\.0\.0\.1|0\.0\.0\.0|localhost):(\d{2,5})/g;
  const optionPortPattern = /(?:--[a-zA-Z0-9-]*port|port)\s*[:= ]\s*(\d{2,5})/gi;
  const urlPortPattern = /https?:\/\/[^\s]+:(\d{2,5})/g;

  for (const pattern of [hostPortPattern, optionPortPattern, urlPortPattern]) {
    for (const match of text.matchAll(pattern)) {
      if (match[1]) rawPorts.push(match[1]);
    }
  }

  return uniquePorts(rawPorts).sort((a, b) => a - b);
}

function extractUiPortFromText(text) {
  const match = text.match(/--ui-port\s*[:= ]\s*(\d{2,5})/i);
  if (!match?.[1]) return null;
  return normalizePort(match[1]);
}

async function extractPortsFromTaskScript(taskPathOrMeta) {
  if (!taskPathOrMeta) return [];

  const raw = String(taskPathOrMeta);

  try {
    const script = await fs.readFile(raw, "utf8");
    return extractPortsFromText(script);
  } catch {
    return extractPortsFromText(raw);
  }
}

async function extractUiPortFromTaskScript(taskPathOrMeta) {
  if (!taskPathOrMeta) return null;

  const raw = String(taskPathOrMeta);

  try {
    const script = await fs.readFile(raw, "utf8");
    return extractUiPortFromText(script);
  } catch {
    return extractUiPortFromText(raw);
  }
}

function shouldExposeHttp(processName, taskPathOrMeta = "") {
  const hints = `${processName || ""} ${taskPathOrMeta || ""}`.toLowerCase();
  const infraIndicators = [
    "temporal",
    "otel",
    "collector",
    "grpc",
    "postgres",
    "mysql",
    "redis",
    "kafka",
    "rabbit",
    "nats",
    "queue",
    "worker",
    "scheduler",
    "db",
  ];

  if (infraIndicators.some((term) => hints.includes(term))) {
    return false;
  }

  return true;
}

async function checkDevProcessRunning({ projectPath, processName, taskPath, port, candidatePorts = [] }) {
  const portsToCheck = uniquePorts([port, ...candidatePorts]);

  for (const candidate of portsToCheck) {
    if (await portIsOpen(candidate)) {
      return { running: true, port: candidate };
    }
  }

  if (projectPath && processName) {
    try {
      const { stdout } = await execFileAsync("pitchfork", ["status", processName], {
        timeout: 2500,
        cwd: projectPath,
        env: tmuxEnv(),
      });

      if (/^Status:\s*running/im.test(stdout)) {
        return { running: true, port: portsToCheck[0] || null };
      }
    } catch {
      // fall through to process/port heuristics
    }
  }

  if (taskPath) {
    try {
      const stat = await fs.stat(taskPath);
      if (stat.isFile()) {
        await execFileAsync("pgrep", ["-f", taskPath], { timeout: 2000, env: tmuxEnv() });
        return { running: true, port: portsToCheck[0] || null };
      }
    } catch {
      // ignore and fall through
    }
  }

  return { running: false, port: portsToCheck[0] || null };
}

async function getTailscaleServeState() {
  const ports = new Set();
  let dnsName = null;

  try {
    const { stdout } = await execFileAsync("tailscale", ["serve", "status"], {
      timeout: 3000,
      env: tmuxEnv(),
    });

    for (const line of stdout.split("\n")) {
      const portMatch = line.match(/\.ts\.net:(\d{2,5})/);
      if (portMatch) {
        ports.add(parseInt(portMatch[1], 10));
      }

      if (!dnsName) {
        const dnsMatch = line.match(/([a-z0-9.-]+\.ts\.net)/i);
        if (dnsMatch) {
          dnsName = dnsMatch[1];
        }
      }
    }
  } catch {
    // ignore; we still try to infer DNS name from tailscale status
  }

  if (!dnsName) {
    try {
      const { stdout } = await execFileAsync("tailscale", ["status", "--json"], {
        timeout: 3000,
        env: tmuxEnv(),
      });
      const status = JSON.parse(stdout);
      dnsName = status?.Self?.DNSName?.replace(/\.$/, "") || null;
    } catch {
      dnsName = null;
    }
  }

  return { ports, dnsName };
}

async function loadDevServers() {
  try {
    const content = await fs.readFile(DEVSERVERS_FILE, "utf8");
    const projects = await loadProjects();
    const projectPathByName = new Map(projects.map((p) => [p.name, p.path]));
    const hostname = (await execFileAsync("hostname")).stdout.trim();
    const { ports: activeTailscalePorts, dnsName: tailscaleDnsName } =
      await getTailscaleServeState();
    const publicHost = tailscaleDnsName || `${hostname}.tail0b43a9.ts.net`;
    const servers = [];

    for (const rawLine of content.split("\n")) {
      const line = rawLine.trim();
      if (!line) continue;

      const parts = line.split("|");
      let project = "";
      let processName = "server";
      let portRaw = "";
      let tsportRaw = "";
      let taskPath = "";
      let legacyPid = "";

      // New schema: project|process|port|tsport|task_path
      if (parts.length >= 5) {
        [project, processName, portRaw, tsportRaw, taskPath] = parts;
      } else {
        // Legacy schema: project|port|tsport|pid
        [project, portRaw, tsportRaw, legacyPid] = parts;
      }

      const port = normalizePort(portRaw);
      const tsport = normalizePort(tsportRaw);
      const tailscaleActive = tsport ? activeTailscalePorts.has(tsport) : false;
      const candidatePorts = await extractPortsFromTaskScript(taskPath);
      const uiPort = await extractUiPortFromTaskScript(taskPath);
      const preferredPort = uiPort || port;
      const inferredHttpExposed = shouldExposeHttp(processName, taskPath);
      const httpExposed = Boolean(tsport) || inferredHttpExposed || uiPort !== null;

      let running = false;
      let effectivePort = preferredPort;
      const projectPath = projectPathByName.get(project) || null;
      if (taskPath || projectPath) {
        const state = await checkDevProcessRunning({
          projectPath,
          processName,
          taskPath,
          port: preferredPort,
          candidatePorts,
        });
        running = state.running;
        effectivePort = state.port || effectivePort;
      } else if (legacyPid) {
        try {
          process.kill(parseInt(legacyPid, 10), 0);
          running = true;
        } catch {
          running = false;
        }
      }

      const tailscaleUrl =
        running && httpExposed && tailscaleActive && tsport
          ? `https://${publicHost}:${tsport}`
          : null;

      const localUrl = effectivePort
        ? httpExposed
          ? `http://127.0.0.1:${effectivePort}`
          : `127.0.0.1:${effectivePort}`
        : null;

      servers.push({
        project,
        process: processName,
        port: effectivePort,
        tsport,
        taskPath: taskPath || null,
        running,
        httpExposed,
        localUrl,
        tailscaleUrl,
      });
    }

    return servers;
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
  const [projects, sessionDetails, windowDetails, devServers] = await Promise.all([
    loadProjects(),
    (async () => {
      try {
        const out = await tmuxExec([
          "list-sessions",
          "-F",
          "#{session_name}:#{session_windows}:#{session_attached}",
        ]);
        return out
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => {
            const [name, windows, attached] = line.split(":");
            return {
              name,
              windows: parseInt(windows),
              attached: parseInt(attached) > 0,
            };
          });
      } catch {
        return [];
      }
    })(),
    (async () => {
      try {
        const out = await tmuxExec([
          "list-windows",
          "-a",
          "-F",
          "#{session_name}\t#{window_index}\t#{window_name}\t#{window_active}",
        ]);
        return out
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => {
            const [session, index, name, active] = line.split("\t");
            return { session, index: parseInt(index), name, active: active === "1" };
          });
      } catch {
        return [];
      }
    })(),
    loadDevServers(),
  ]);
  const activeSet = new Set(sessionDetails.map((s) => s.name));
  return {
    projects: projects.map((p) => ({
      ...p,
      active: activeSet.has(p.name),
    })),
    sessions: sessionDetails,
    windows: windowDetails,
    devServers,
  };
});

app.post("/api/kill", async (req) => {
  const { session = "", window: winTarget = "" } = req.body || {};
  if (!session) return { ok: false, error: "session name required" };
  try {
    if (winTarget) {
      await tmuxExec(["kill-window", "-t", `${session}:${winTarget}`]);
    } else {
      await tmuxExec(["kill-session", "-t", session]);
    }
    return { ok: true };
  } catch (e) {
    const stderr = typeof e?.stderr === "string" ? e.stderr.trim() : "";
    const stdout = typeof e?.stdout === "string" ? e.stdout.trim() : "";
    const details = stderr || stdout;
    return { ok: false, error: details || e.message };
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
    const stderr = typeof e?.stderr === "string" ? e.stderr.trim() : "";
    const stdout = typeof e?.stdout === "string" ? e.stdout.trim() : "";
    const details = stderr || stdout;
    return { ok: false, error: details || e.message };
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

app.get("/dev", async (req, reply) => {
  return reply.sendFile("dev.html");
});

app.get("/env", async (req, reply) => {
  return reply.sendFile("env.html");
});

// --- Dev server management API ---
app.post("/api/dev", async (req) => {
  const { action = "", project = "", process = "" } = req.body || {};
  if (!action || !project) return { ok: false, error: "action and project required" };

  const projects = await loadProjects();
  const proj = projects.find((p) => p.name === project);
  if (!proj) return { ok: false, error: `project not found: ${project}` };

  const vaibhavBin = path.join(homedir(), "projects", "vaibhav", "bin", "vaibhav");

  try {
    const args = [vaibhavBin, "dev", action, project];
    if (process) args.push(process);

    switch (action) {
      case "stop":
        await execFileAsync("bash", args, { timeout: 30000, env: tmuxEnv() });
        return { ok: true };
      case "start":
        await execFileAsync("bash", args, { timeout: 180000, env: tmuxEnv() });
        return { ok: true };
      case "restart":
        await execFileAsync("bash", args, { timeout: 180000, env: tmuxEnv() });
        return { ok: true };
      default:
        return { ok: false, error: `unknown action: ${action}` };
    }
  } catch (e) {
    const stderr = typeof e?.stderr === "string" ? e.stderr.trim() : "";
    const stdout = typeof e?.stdout === "string" ? e.stdout.trim() : "";
    const details = stderr || stdout;
    return { ok: false, error: details || e.message };
  }
});

// --- Env file management ---
function parseEnv(content) {
  const lines = content.split("\n");
  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const trimmed = raw.trim();
    if (trimmed === "" || trimmed.startsWith("#")) {
      entries.push({ type: "comment", value: raw, line: i });
      continue;
    }
    const eq = trimmed.indexOf("=");
    if (eq === -1) {
      entries.push({ type: "comment", value: raw, line: i });
      continue;
    }
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1);
    // Handle quoted values
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    entries.push({ type: "var", key, value, line: i });
  }
  return entries;
}

function serializeEnv(entries) {
  const lines = [];
  for (const entry of entries) {
    if (entry.type === "comment" || entry.type === "blank") {
      lines.push(entry.value);
    } else if (entry.type === "var") {
      const needsQuotes = entry.value.includes(" ") || entry.value.includes("#");
      const val = needsQuotes ? `"${entry.value.replace(/"/g, '\\"')}"` : entry.value;
      lines.push(`${entry.key}=${val}`);
    }
  }
  return lines.join("\n") + "\n";
}

app.get("/api/env", async (req) => {
  const project = req.query.project || "";
  const file = req.query.file || "";

  if (!project) {
    // List all projects and their env files (show all, even those without)
    const projects = await loadProjects();
    const result = [];
    for (const proj of projects) {
      try {
        const files = await fs.readdir(proj.path);
        const envFiles = files.filter((f) => f.startsWith(".env") || f.endsWith(".env"));
        result.push({ name: proj.name, path: proj.path, envFiles });
      } catch {
        // ignore unreadable dirs
      }
    }
    return { projects: result };
  }

  // Specific project + file
  const projects = await loadProjects();
  const proj = projects.find((p) => p.name === project);
  if (!proj) return { ok: false, error: `project not found: ${project}` };

  if (!file) {
    try {
      const files = await fs.readdir(proj.path);
      const envFiles = files.filter((f) => f.startsWith(".env") || f.endsWith(".env"));
      return { project, envFiles };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  const envPath = path.join(proj.path, file);
  try {
    const content = await fs.readFile(envPath, "utf8");
    return { project, file, entries: parseEnv(content), raw: content };
  } catch (e) {
    // File doesn't exist yet — return empty entries so UI can create it
    if (e.code === "ENOENT") {
      return { project, file, entries: [], raw: "" };
    }
    return { ok: false, error: e.message };
  }
});

app.post("/api/env", async (req) => {
  const { project = "", file = ".env", entries = [] } = req.body || {};
  if (!project) return { ok: false, error: "project required" };

  const projects = await loadProjects();
  const proj = projects.find((p) => p.name === project);
  if (!proj) return { ok: false, error: `project not found: ${project}` };

  const envPath = path.join(proj.path, file);
  try {
    const data = serializeEnv(entries);
    await fs.writeFile(envPath, data, "utf8");
    return { ok: true, project, file };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

app.delete("/api/env", async (req) => {
  const { project = "", file = ".env", key = "" } = req.body || {};
  if (!project || !key) return { ok: false, error: "project and key required" };

  const projects = await loadProjects();
  const proj = projects.find((p) => p.name === project);
  if (!proj) return { ok: false, error: `project not found: ${project}` };

  const envPath = path.join(proj.path, file);
  try {
    let content = "";
    try {
      content = await fs.readFile(envPath, "utf8");
    } catch {
      return { ok: false, error: "env file not found" };
    }
    const entries = parseEnv(content).filter((e) => e.type !== "var" || e.key !== key);
    await fs.writeFile(envPath, serializeEnv(entries), "utf8");
    return { ok: true, project, file, deleted: key };
  } catch (e) {
    return { ok: false, error: e.message };
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
