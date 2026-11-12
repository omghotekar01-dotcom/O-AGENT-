# O-AGENT Studio — Connect a real AI model

**Status:** This integration runs genuine provider API requests from the Node.js backend. It is not included in a ChatGPT subscription; a separately provisioned API key with available billing or credits is required. The mobile app never receives the provider key.

## One-time requirements

- O-AGENT repository checked out at the latest `main` commit.
- Node.js 22 or later.
- Your existing O-AGENT operator and worker tokens (the same values already working with the browser dashboard and mobile app).
- An API key from **one** of:
  - [OpenAI API keys](https://platform.openai.com/api-keys) — uses the [Responses API tool-calling flow](https://developers.openai.com/api/docs/guides/function-calling).
  - [Anthropic Console](https://console.anthropic.com/) — uses the [Messages API tool-use flow](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview).

Do not paste provider API keys into a chat, GitHub, your Flutter app, PowerShell screenshots, or this document.

## Windows PowerShell — recommended setup

Close the running server in **Terminal 1** with Ctrl+C. Leave **Terminal 2** (the worker) running; it will reconnect automatically.

In Terminal 1, inside the repository:

```powershell
cd "C:\Users\ASUS\OneDrive\Desktop\O Agent\O-AGENT-"
git pull origin main

# Preserve the operator and worker tokens already configured in this same terminal:
Write-Output ("Operator token configured: " + [bool]$env:OAGENT_API_TOKEN)
Write-Output ("Worker token configured: " + [bool]$env:OAGENT_WORKER_TOKEN)

$env:OAGENT_AI_PROVIDER = "openai"
$env:OAGENT_AI_MODEL = "gpt-5.6-terra"

# Prompt without echoing the API key to the screen.
$secureKey = Read-Host "OpenAI API key" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
  $env:OPENAI_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

npm run check
npm test
npm start
```

**Important:** If your operator/worker token environment variables are missing, restore the **same previously generated values** before `npm start`, or the mobile app and worker will stop authenticating. Do not generate new tokens unless you also update all clients.

For **Anthropic**, use `$env:OAGENT_AI_PROVIDER = "anthropic"`, set an available model in `OAGENT_AI_MODEL` (e.g. `claude-sonnet-4-5` if your account supports it), and use `$env:ANTHROPIC_API_KEY` rather than `OPENAI_API_KEY`.

These are temporary process environment variables, not permanent Windows settings. Restarting PowerShell loses them. They are not committed to GitHub.

## Verify from your PC (without exposing secrets)

The backend's `/api/ai/status` needs the *operator* token; the web dashboard still uses `http://127.0.0.1:8787`.

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/ai/status" -Headers @{Authorization="Bearer $env:OAGENT_API_TOKEN"}
```

Expected when configured:

```json
{"configured":true,"provider":"openai","model":"gpt-5.6-terra","agents":[...]}
```

The value `configured:true` means a key is present in the backend environment — **not** proof that the provider accepted it. A real chat message is the end-to-end provider test.

## Test from the Flutter Android app

1. Keep the laptop backend and gateway running.
2. If using USB `adb reverse tcp:8787 tcp:8787`, connect the phone to `http://127.0.0.1:8787` with the **operator token**.
3. Download the latest successful Android APK from [Flutter CI](https://github.com/omghotekar01-dotcom/O-AGENT-/actions/workflows/flutter-mobile.yml) after this update. If needed, uninstall the older debug APK before installing.
4. Open **Agents** → **Navigator**. In **Chat**, ask **"Which machines are online?"**.
5. Expect a genuine model reply using the server's live `list_machines` tool (not seeded demo content).
6. Ask **"Request a system report for my-laptop"**. If the AI queues it, open **Activity** and verify the task's real completion from your running gateway.
7. Ask **"Request workspace inventory for my-laptop"**. It must appear in **Approvals**. Approve on the phone, and inspect the result in **Activity**.
8. Return to **Home** → **Recent conversations** to reopen a saved thread after app restart. Threads persist in the local backend's JSON data file.

If the provider reports HTTP 401/403, the key/model/account needs attention. HTTP 429 normally indicates quota or rate limits. These failures are not simulated successes.

## Development API endpoints

Operator token required for all.

| Method | Endpoint | Behavior |
|---|---|---|
| GET | `/api/ai/status` | Provider configured flag, model and available profiles |
| GET | `/api/ai/threads` | Saved thread summaries |
| GET | `/api/ai/threads/:id` | Saved messages in a conversation |
| POST | `/api/ai/chat` | Send a message and receive full persisted thread |

Example direct POST:

```powershell
$body = @{agentId="navigator"; message="Which machines are connected?"} | ConvertTo-Json
Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/ai/chat" -Method Post -ContentType "application/json" -Headers @{Authorization="Bearer $env:OAGENT_API_TOKEN"} -Body $body
```

A follow-up message includes `threadId` from the result.

## AI agent capabilities: honest boundaries

The server has three scoped prompt profiles — **Navigator**, **Researcher**, **Operator** — sharing one configured provider and real tool registry. Their supported tools are:
- `list_machines` — real registered machine heartbeats and status.
- `list_recent_tasks` — actual backend work.
- `get_task_result` — current task result, never fabricated completion.
- `request_system_health` — enqueue read-only information report.
- `request_workspace_inventory` — create a **human-approval-gated** listing request.

**Not supported:** arbitrary shell commands, editing laptop files, autonomous browser tasks, remote desktop, external service account connections, multi-agent delegation, RAG search, push notifications, or enterprise login. These require further backend and security work.

The backend permits a maximum of three AI tool rounds per response and limits message sizes. Provider calls can be billable. Conversations are persisted locally (plain JSON — not encrypted); never enter passwords, private credentials or sensitive personal information into chat in this development setup. Tool outputs and thread records must be treated as untrusted.

## Security before real internet exposure

Development uses a long-lived operator bearer token and local JSON state. No per-user RBAC, secure pairing, or tenant separation is enforced. Run on localhost with ADB reverse while testing. For remote access, introduce authenticated HTTPS, short-lived sessions, per-device credentials, provider key storage/rotation, rate limiting, strong audit trails, retention policy, durable DB, and security review. **Do not publish the current server openly.**

See [MVP runbook](MVP_RUNBOOK.md), [Security baseline](SECURITY_BASELINE.md) and [Product requirements](PRODUCT_REQUIREMENTS.md).
