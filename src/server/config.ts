import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { ROOT, HERE } from './paths.js';
import type { BridgeConfig, Model } from '../shared/contract.js';
import { bag, list, get, str, parseJson } from '../shared/guards.js';

function executable(env: string, candidates: string[]): string | null {
  if (process.env[env]) return process.env[env];
  const paths = candidates.flatMap(candidate => candidate.includes('/') ? [candidate] :
    (process.env.PATH || '').split(path.delimiter).map(dir => path.join(dir, candidate)));
  return paths.find(file => { try { fs.accessSync(file, fs.constants.X_OK); return fs.statSync(file).isFile(); } catch { return false; } }) || null;
}
function windowsCodexResources(env: NodeJS.ProcessEnv): string | null {
  if (process.platform !== 'win32') return null;
  try {
    const saved = bag(parseJson(fs.readFileSync(path.join(ROOT, '.frontdesk-runtime', 'windows-codex.json'), 'utf8')));
    const resources = str(get(saved, 'resources'));
    if (resources && fs.existsSync(path.join(resources, 'app.asar')) && fs.existsSync(path.join(resources, 'codex.exe'))) return resources;
  } catch {}
  const root = path.join(env.ProgramFiles || 'C:\\Program Files', 'WindowsApps');
  let names: string[] = [];
  try { names = fs.readdirSync(root).filter(name => /^OpenAI\.Codex_.+_x64__2p2nqsd0c76g0$/i.test(name)).sort().reverse(); } catch {}
  for (const name of names) {
    const resources = path.join(root, name, 'app', 'resources');
    if (fs.existsSync(path.join(resources, 'app.asar')) && fs.existsSync(path.join(resources, 'codex.exe'))) return resources;
  }
  // Store apps may hide the WindowsApps directory from a background task even though the
  // installed package itself is readable. AppX's registered install location is the stable fallback.
  try {
    const install = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', "(Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1 -ExpandProperty InstallLocation)"], { encoding: 'utf8', windowsHide: true, timeout: 5000 }).trim();
    const resources = path.join(install, 'app', 'resources');
    if (install && fs.existsSync(path.join(resources, 'app.asar')) && fs.existsSync(path.join(resources, 'codex.exe'))) return resources;
  } catch {}
  return null;
}
function findClaude(root: string): string[] {
  if (!fs.existsSync(root)) return [];
  const found: string[] = [];
  function walk(dir: string, depth: number) {
    if (depth > 5) return;
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, item.name);
      if (item.isDirectory()) walk(file, depth + 1);
      else if (item.name === 'claude') found.push(file);
    }
  }
  walk(root, 0);
  return found.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
}
// The optional model catalog file: { <engine>: [{ id, name, … }] }; entries without an id are skipped.
function catalogsOf(value: unknown): Record<string, Model[]> {
  const out: Record<string, Model[]> = {};
  for (const [engine, models] of Object.entries(bag(value) || {})) {
    out[engine] = list(models).flatMap(item => { const id = str(get(item, 'id')); return id ? [{ ...bag(item), id, name: str(get(item, 'name')) || id }] : []; });
  }
  return out;
}
function loadConfig(env: NodeJS.ProcessEnv = process.env): BridgeConfig {
  const home = os.homedir();
  const agyHome = env.ANTIGRAVITY_HOME || path.join(home, '.gemini/antigravity');
  const windowsResources = windowsCodexResources(env);
  const codexBin = executable('CODEX_BIN', ['codex.exe', 'codex', '/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex'])
    || (windowsResources ? path.join(windowsResources, 'codex.exe') : null);
  const desktopAsar = env.CHATGPT_APP_ASAR || (windowsResources
    ? path.join(windowsResources, 'app.asar') : '/Applications/ChatGPT.app/Contents/Resources/app.asar');
  let catalogs: Record<string, Model[]> = {};
  if (env.BRIDGE_MODEL_CATALOG) catalogs = catalogsOf(parseJson(fs.readFileSync(env.BRIDGE_MODEL_CATALOG, 'utf8')));
  return {
    host: env.HOST || '127.0.0.1', port: Number(env.PORT || 4100),
    // HTTPS (for the microphone on other devices) is on by default when the console
    // listens beyond loopback; HTTPS_PORT=0 turns it off.
    httpsPort: env.HTTPS_PORT != null ? Number(env.HTTPS_PORT) : ['127.0.0.1', 'localhost', '::1'].includes(env.HOST || '127.0.0.1') ? 0 : Number(env.PORT || 4100) + 1,
    certDir: env.BRIDGE_CERT_DIR || path.join(ROOT, '.certs'),
    uploadsDir: env.BRIDGE_UPLOADS_DIR || path.join(ROOT, 'uploads'),
    pluginDir: env.BRIDGE_PLUGIN_DIR || path.join(HERE, 'plugins'),
    defaultCwd: env.BRIDGE_DEFAULT_CWD || home,
    codexBin,
    claudeBin: executable('CLAUDE_BIN', ['claude', ...findClaude(path.join(home, 'Library/Application Support/Claude/claude-code'))]),
    codexHome: env.CODEX_HOME || path.join(home, '.codex'),
    claudeHome: env.CLAUDE_HOME || path.join(home, '.claude'),
    chatgptAppAsar: desktopAsar,
    claudeDesktopHome: env.CLAUDE_DESKTOP_HOME || path.join(home, 'Library/Application Support/Claude'),
    claudeAppAsar: env.CLAUDE_APP_ASAR || '/Applications/Claude.app/Contents/Resources/app.asar',
    // Speech-to-text used by every engine's mic button; falls back to the engine's own.
    dictationEngine: env.BRIDGE_DICTATION_ENGINE || 'claude',
    // What the person chose in the console (which agents are on). Local to this checkout, not committed.
    settingsFile: env.BRIDGE_SETTINGS_FILE || path.join(ROOT, '.frontdesk.json'),
    agyHome, agentapiBin: executable('AGENTAPI_BIN', [path.join(agyHome, 'bin/agentapi'), 'agentapi']),
    catalogs,
  };
}
export { loadConfig };
