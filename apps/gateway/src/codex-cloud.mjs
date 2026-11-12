import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export function normalizeCodexTasks(data) {
  const items = Array.isArray(data?.tasks) ? data.tasks : null;
  if (!items) throw new Error("Official Codex CLI returned an unexpected task list");
  return items.slice(0, 20).filter(task => task && typeof task.id === "string")
    .map(task => ({
      id: task.id.slice(0, 120),
      title: typeof task.title === "string" ? task.title.slice(0, 180) : task.id.slice(0, 120),
      summary: typeof task.summary === "string" ? task.summary.slice(0, 300) : "",
      status: typeof task.status === "string" ? task.status.slice(0, 40) : "unknown",
      updated_at: typeof task.updated_at === "string" ? task.updated_at : null,
      url: typeof task.url === "string" ? task.url : null,
    }));
}
export async function readCodexCloudTasks(execImpl = execFileAsync) {
  // Windows npm CLI shims can be .cmd files. PowerShell resolves codex.cmd
  // without needing shell=true on arbitrary user-provided arguments.
  const windows = process.platform === "win32";
  const bin = windows ? "powershell.exe" : "codex";
  const args = windows
    ? ["-NoProfile", "-NonInteractive", "-Command", "& codex cloud list --json --limit 20"]
    : ["cloud", "list", "--json", "--limit", "20"];
  // No O-AGENT backend tokens or AI provider keys are passed to the CLI.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    !/^(OAGENT_(API|WORKER)_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|OAGENT_GITHUB_TOKEN)$/i.test(key)
  ));
  const { stdout } = await execImpl(bin, args, {
    timeout: 30000,
    maxBuffer: 1024 * 1024,
    windowsHide: true,
    env,
  });
  return normalizeCodexTasks(JSON.parse(stdout));
}
