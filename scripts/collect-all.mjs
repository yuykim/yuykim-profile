import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname);
const configPath = path.join(repoRoot, ".dev-env.json");
const config = readJson(configPath) ?? {
  profile: { owner: "yuykim" },
  machine: { id: "", label: "", role: "development machine" },
  workspace: { path: path.resolve(repoRoot, "..") },
};

const machine = getMachineConfig(config);
const workspacePath = path.resolve(config.workspace?.path ?? path.resolve(repoRoot, ".."));
const machineDir = path.join(repoRoot, "data", "machines", machine.id);
const collectedAt = new Date().toISOString();

const system = collectSystem(machine);
const languages = {
  collected_at: collectedAt,
  languages: [
    probe("Python", "python3", ["--version"]),
    probe("Python", "python", ["--version"]),
    probe("pip", "pip3", ["--version"]),
    probe("Node.js", "node", ["--version"]),
    probe("npm", "npm", ["--version"]),
    probe("pnpm", "pnpm", ["--version"]),
    probe("Yarn", "yarn", ["--version"]),
    probe("Java", "java", ["--version"]),
    probe("javac", "javac", ["--version"]),
    probe(".NET", "dotnet", ["--version"]),
    probe("Go", "go", ["version"]),
    probe("Rust", "rustc", ["--version"]),
    probe("Cargo", "cargo", ["--version"]),
    probe("Git", "git", ["--version"]),
  ],
};

const tools = {
  collected_at: collectedAt,
  tools: [
    probe("VS Code", "code", ["--version"]),
    probe("Cursor", "cursor", ["--version"]),
    probe("Unity Hub", "unityhub", ["--version"]),
    probe("Docker", "docker", ["--version"]),
    probe("Docker Compose", "docker", ["compose", "version"]),
    probe("Conda", "conda", ["--version"]),
    probe("Android Debug Bridge", "adb", ["version"]),
    probe("GitHub CLI", "gh", ["--version"]),
    probe("Homebrew", "brew", ["--version"]),
  ],
};

const editors = {
  collected_at: collectedAt,
  editors: [probe("VS Code", "code", ["--version"]), probe("Cursor", "cursor", ["--version"])],
  vscode_extensions: collectExtensions("code"),
  cursor_extensions: collectExtensions("cursor"),
};

const workspace = collectWorkspaceUsage(workspacePath);
const agents = collectAgents(workspacePath, editors);

writeJson(path.join(machineDir, "system.json"), system);
writeJson(path.join(machineDir, "languages.json"), languages);
writeJson(path.join(machineDir, "tools.json"), tools);
writeJson(path.join(machineDir, "editors.json"), editors);
writeJson(path.join(machineDir, "agents.json"), agents);
writeJson(path.join(machineDir, "workspace-usage.json"), workspace);
writeJson(path.join(machineDir, "collected-at.json"), { collected_at: collectedAt });
writeMarkdown(path.join(repoRoot, "dev_env", "machines", `${machine.id}.md`), renderMachine(system, languages, tools, editors, agents, workspace));

const summary = buildSummary();
writeJson(path.join(repoRoot, "data", "summary.json"), summary);
writeMarkdown(path.join(repoRoot, "dev_env", "index.md"), renderIndex(summary));

console.log(`Collected dev environment snapshot for '${machine.id}'.`);

function readJson(file) {
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeMarkdown(file, lines) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${lines.join("\n")}\n`, "utf8");
}

function slug(value) {
  return String(value || "unknown-machine").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "unknown-machine";
}

function getMachineConfig(value) {
  const id = slug(value.machine?.id || os.hostname());
  return {
    id,
    label: value.machine?.label || id,
    role: value.machine?.role || "development machine",
  };
}

function run(command, args = []) {
  try {
    return sanitize(execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim());
  } catch (error) {
    const output = error.stdout || error.stderr;
    if (output) return sanitize(String(output).trim());
    return null;
  }
}

function probe(name, command, args) {
  const output = run(command, args);
  return {
    name,
    command,
    detected: Boolean(output),
    version: output,
    source: output ? "command" : "missing",
    error: output ? null : "command not found",
  };
}

function sanitize(text) {
  if (!text) return text;
  let output = text.replaceAll("\0", "");
  const home = os.homedir();
  if (home) output = output.split(home).join("$HOME");
  return output
    .split("\n")
    .filter((line) => !/serial|uuid|hardware uuid|provisioning|token|secret|password|api[_-]?key/i.test(line))
    .join("\n");
}

function collectSystem(machineConfig) {
  const isMac = process.platform === "darwin";
  const swVersion = isMac ? run("sw_vers", []) : `${os.type()} ${os.release()}`;
  const cpu = isMac ? run("sysctl", ["-n", "machdep.cpu.brand_string"]) : os.cpus()[0]?.model;
  const memGb = Math.round((os.totalmem() / 1024 / 1024 / 1024) * 10) / 10;
  const hardware = isMac ? run("system_profiler", ["SPHardwareDataType"]) : null;
  const displays = isMac ? run("system_profiler", ["SPDisplaysDataType"]) : null;
  const storage = isMac ? run("system_profiler", ["SPStorageDataType"]) : null;

  return {
    machine: machineConfig,
    collected_at: collectedAt,
    os: {
      platform: process.platform,
      release: os.release(),
      summary: swVersion,
      architecture: os.arch(),
    },
    hardware: {
      manufacturer: isMac ? "Apple" : null,
      model: extractMacModel(hardware),
      cpu,
      ram_gb: memGb,
      gpu: extractMacGpus(displays),
      disks: extractMacStorage(storage),
    },
  };
}

function extractMacModel(text) {
  return text?.match(/Model Name:\s*(.+)/)?.[1]?.trim() ?? text?.match(/Model Identifier:\s*(.+)/)?.[1]?.trim() ?? null;
}

function extractMacGpus(text) {
  if (!text) return [];
  return [...text.matchAll(/Chipset Model:\s*(.+)/g)].map((match) => ({ name: match[1].trim() }));
}

function extractMacStorage(text) {
  if (!text) return [];
  return [...text.matchAll(/Capacity:\s*([^\n]+)/g)].slice(0, 6).map((match, index) => ({ drive: `disk${index}`, size: match[1].trim() }));
}

function collectExtensions(command) {
  const output = run(command, ["--list-extensions", "--show-versions"]);
  if (!output) return { detected: false, command, extensions: [], error: "command not found" };
  const extensions = output.split(/\r?\n/).filter(Boolean).map((item) => {
    const [id, version] = item.split("@");
    return { id, version: version ?? null };
  });
  return { detected: true, command, extensions, error: null };
}

function listFiles(root) {
  const excluded = new Set([".git", "node_modules", "Library", "Temp", "Logs", "dist", "build", ".venv", "venv", "__pycache__", ".astro"]);
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!excluded.has(entry.name)) stack.push(full);
      } else {
        out.push(full);
      }
    }
  }
  return out;
}

function collectWorkspaceUsage(root) {
  if (!fs.existsSync(root)) {
    return { collected_at: collectedAt, workspace_path: "WORKSPACE", detected: false, error: "workspace path not found", signals: [] };
  }
  const files = listFiles(root);
  const checks = [
    ["Node/Web", (f) => path.basename(f) === "package.json"],
    ["Python requirements", (f) => path.basename(f) === "requirements.txt"],
    ["Python project", (f) => path.basename(f) === "pyproject.toml"],
    ["Jupyter Notebook", (f) => f.endsWith(".ipynb")],
    ["Unity", (f) => f.endsWith(path.join("ProjectSettings", "ProjectVersion.txt"))],
    [".NET solution", (f) => f.endsWith(".sln")],
    [".NET project", (f) => f.endsWith(".csproj")],
    ["Dockerfile", (f) => path.basename(f) === "Dockerfile"],
    ["Docker Compose", (f) => ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].includes(path.basename(f))],
  ];
  return {
    collected_at: collectedAt,
    workspace_path: "WORKSPACE",
    detected: true,
    scanned_files: files.length,
    signals: checks.map(([name, test]) => {
      const matches = files.filter(test);
      return { name, count: matches.length, examples: matches.slice(0, 12).map((f) => path.relative(root, f)) };
    }),
  };
}

function collectAgents(root, editorSnapshot) {
  const commandAgents = [
    probe("Codex", "codex", ["--version"]),
    probe("Claude Code", "claude", ["--version"]),
    probe("Gemini CLI", "gemini", ["--version"]),
    probe("OpenAI CLI", "openai", ["--version"]),
  ];
  const extensionAgents = [...editorSnapshot.vscode_extensions.extensions, ...editorSnapshot.cursor_extensions.extensions]
    .filter((ext) => /copilot|continue|cline|roo|openai|cursor|claude|gemini/i.test(ext.id))
    .map((ext) => ({ name: ext.id, detected: true, version: ext.version, source: "editor_extension" }));

  const instructionFiles = fs.existsSync(root)
    ? listFiles(root)
        .filter((file) => ["AGENTS.md", "CLAUDE.md", "GEMINI.md", ".cursorrules"].includes(path.basename(file)) || file.includes(`${path.sep}.cursor${path.sep}rules${path.sep}`))
        .slice(0, 80)
        .map((file) => path.relative(root, file))
    : [];

  return { collected_at: collectedAt, agents: [...commandAgents, ...extensionAgents], instruction_files: instructionFiles };
}

function detectedNames(items) {
  return [...new Set(items.filter((item) => item.detected).map((item) => item.name))].sort();
}

function buildSummary() {
  const machinesRoot = path.join(repoRoot, "data", "machines");
  const machineIds = fs.existsSync(machinesRoot) ? fs.readdirSync(machinesRoot).filter((item) => fs.statSync(path.join(machinesRoot, item)).isDirectory()) : [];
  const machines = [];
  const allLanguages = [];
  const allTools = [];
  const allAgents = [];
  const usage = new Map();

  for (const id of machineIds) {
    const dir = path.join(machinesRoot, id);
    const sys = readJson(path.join(dir, "system.json"));
    if (!sys) continue;
    machines.push({ id: sys.machine.id, label: sys.machine.label, role: sys.machine.role, collected_at: sys.collected_at });
    const lang = readJson(path.join(dir, "languages.json"));
    const tool = readJson(path.join(dir, "tools.json"));
    const edit = readJson(path.join(dir, "editors.json"));
    const agent = readJson(path.join(dir, "agents.json"));
    const work = readJson(path.join(dir, "workspace-usage.json"));
    if (lang) allLanguages.push(...detectedNames(lang.languages));
    if (tool) allTools.push(...detectedNames(tool.tools));
    if (edit) allTools.push(...detectedNames(edit.editors));
    if (agent) allAgents.push(...detectedNames(agent.agents));
    for (const signal of work?.signals ?? []) usage.set(signal.name, (usage.get(signal.name) ?? 0) + signal.count);
  }

  return {
    updated_at: new Date().toISOString(),
    machines: machines.sort((a, b) => a.id.localeCompare(b.id)),
    common: {
      languages: [...new Set(allLanguages)].sort(),
      tools: [...new Set(allTools)].sort(),
      agents: [...new Set(allAgents)].sort(),
    },
    workspace_usage: [...usage.entries()].map(([name, count]) => ({ name, count })).sort((a, b) => a.name.localeCompare(b.name)),
  };
}

function renderMachine(sys, lang, tool, edit, agent, work) {
  const lines = [
    `# ${sys.machine.label}`,
    "",
    `- Role: ${sys.machine.role}`,
    `- Machine ID: \`${sys.machine.id}\``,
    `- Last collected: ${sys.collected_at}`,
    "",
    "## System",
    "",
    `- OS: ${sys.os.summary}`,
    `- Manufacturer/Model: ${[sys.hardware.manufacturer, sys.hardware.model].filter(Boolean).join(" ")}`,
    `- CPU: ${sys.hardware.cpu}`,
    `- RAM: ${sys.hardware.ram_gb} GB`,
    `- GPU: ${(sys.hardware.gpu ?? []).map((item) => item.name).join(", ")}`,
    `- Disks: ${(sys.hardware.disks ?? []).map((item) => `${item.drive} ${item.size ?? item.size_gb ?? ""}`).join(", ")}`,
    "",
    "## Languages and Runtimes",
    "",
  ];
  for (const item of lang.languages) lines.push(`- ${item.name}: ${item.detected ? item.version : "not detected"}`);
  lines.push("", "## Tools", "");
  for (const item of tool.tools) lines.push(`- ${item.name}: ${item.detected ? item.version : "not detected"}`);
  lines.push("", "## Editors", "");
  for (const item of edit.editors) lines.push(`- ${item.name}: ${item.detected ? item.version : "not detected"}`);
  lines.push(`- VS Code extensions: ${edit.vscode_extensions.extensions.length}`, `- Cursor extensions: ${edit.cursor_extensions.extensions.length}`, "", "## Agents", "");
  for (const item of agent.agents) lines.push(`- ${item.name}: ${item.detected ? item.version || "detected" : "not detected"}`);
  lines.push("", "## Workspace Usage Signals", "");
  for (const signal of work.signals) if (signal.count > 0) lines.push(`- ${signal.name}: ${signal.count}`);
  return lines;
}

function renderIndex(summary) {
  const lines = [
    "---",
    'title: "Dev Environment"',
    `updated: "${summary.updated_at}"`,
    "---",
    "",
    "# Dev Environment",
    "",
    "This page is generated from `yuykim_Profile`. It records the development machines, tools, runtimes, editors, agents, and workspace usage signals needed to rebuild the environment.",
    "",
    `- Last updated: ${summary.updated_at}`,
    `- Machines: ${summary.machines.length}`,
    "",
    "## Machines",
    "",
    ...summary.machines.map((item) => `- [${item.label}](machines/${item.id}/): ${item.role}`),
    "",
    "## Common Stack",
    "",
    "### Languages and Runtimes",
    ...summary.common.languages.map((item) => `- ${item}`),
    "",
    "### Tools and Editors",
    ...summary.common.tools.map((item) => `- ${item}`),
    "",
    "### Agents",
    ...summary.common.agents.map((item) => `- ${item}`),
    "",
    "## Workspace Usage",
    "",
    ...summary.workspace_usage.filter((item) => item.count > 0).map((item) => `- ${item.name}: ${item.count}`),
  ];
  return lines;
}
