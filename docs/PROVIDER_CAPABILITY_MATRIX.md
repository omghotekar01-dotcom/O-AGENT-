# Provider capability matrix

**Verification snapshot:** 12 November 2026. Re-check the current official documentation, API version, account eligibility, region, auth method, quotas and terms immediately before each adapter implementation. This matrix is not a claim that these adapters have already been built or connected.

## Product rule

A provider name in the catalogue is not a connection. The adapter is considered connected only after a successful provider authentication and health check. Each session/connection must expose its own capability manifest. Unsupported controls must be hidden or disabled with an exact reason.

| Provider surface | What OMIO can build against | Important boundary | Initial adapter treatment |
|---|---|---|---|
| OpenAI Agents / computer-use APIs | Create/manage supported agent runs, consume streamed activity events, process screenshots, tool results, browser sign-in handoffs and approval requests; recover a session after a client stream disconnect using the documented session/retrieval path. | This does not grant access to a user's private ChatGPT consumer-app history. Computer control requires an execution environment/driver owned or provisioned for the integration. Browser auth flows may not cover every credential method (for example passkeys or QR flows), which must pause for manual completion if unsupported. | Implement the official API/session adapter first if credentials and account access are available. Advertise desktop streaming/remote input only when our own executor and transport are attached. |
| Anthropic Claude Agent SDK | Run an app-owned Claude agent process with supported tools, hooks, permission controls, sessions, subagents and MCP integrations. | This is not the same as a hosted provider-managed session. | Support as an OMIO-managed runtime adapter; keep its process, permissions and workspace under OMIO control. |
| Anthropic Managed Agents | Hosted stateful sessions and provider-managed tools/integrations through the documented managed-agent API. | Documentation currently labels this surface Beta and describes data-retention/eligibility constraints. Verify retention, region and contractual suitability before storing sensitive workloads. | Separate beta adapter mode. Clearly label Beta and expose only documented session controls. |
| GitHub Copilot SDK | Official SDK integrations in supported languages, streaming events, tool/agent configuration and session handling. | SDK-local sessions and GitHub-hosted cloud agent API are distinct products and auth modes. The cloud-agent REST API is preview and documented to require user-to-server authentication; do not assume GitHub App server-to-server credentials work. Paid-plan eligibility and org policy may apply. | Implement local SDK and cloud-agent adapters separately. Show plan/auth restrictions on the selected mode. |
| Google Gemini Computer Use | Model-proposed computer actions, where the application executes the actions, captures the next screenshot and continues the action loop. | Computer Use is a preview surface. The model does not itself operate OMIO's desktop. The OMIO executor must validate actions and honor block/confirmation decisions. | Implement as planner + OMIO-controlled executor. Require supervised confirmation for sensitive actions and label preview status. |
| Cursor | Supported editor APIs, extensions, MCP or explicit local IDE automation through the OMIO Windows worker. | Do not assume a universal public API for reading, steering, pausing or recovering every Cursor session. | Start with a local IDE worker integration only if the interaction method is supported and tested. Never invent cloud-session controls. |

## Capability vocabulary

- `supported`: implemented and contract-tested for this exact adapter mode.
- `unsupported`: provider or adapter mode does not expose the operation.
- `requires_setup`: operation exists but a required account, scope, worker, sandbox or permission is missing.
- `preview`: provider labels the capability preview/beta or OMIO has intentionally enabled it only for opt-in testing.

A capability can be supported at the provider level but unavailable on a particular connection because its scopes, plan, region, workspace or quota do not qualify.

## Adapter implementation checklist

1. Record official API/SDK name, version, documentation URL and last verification date.
2. Implement the provider's actual authentication method without collecting passwords/OTP/MFA outside its supported handoff.
3. Call a real health/account endpoint and persist the result and timestamp.
4. Build the capability manifest from actual adapter support, scopes, plan and runtime configuration.
5. Implement typed operations with timeouts, bounded retries, idempotency and provider request IDs.
6. Stream events and persist them before notifying mobile clients.
7. Preserve provider session identifiers and test resume/disconnect/recovery behavior.
8. Map provider approval, auth-needed, rate-limit and safety-block states into distinct UI states.
9. Contract-test every advertised action and every unsupported action.
10. Publish known limitations, data-retention terms, quotas and beta status in the connection detail screen.

## Official documentation entry points

- OpenAI Agents API: https://platform.openai.com/docs/guides/agents
- OpenAI computer use: https://platform.openai.com/docs/guides/tools-computer-use
- OpenAI Agents SDK: https://openai.github.io/openai-agents-js/
- Anthropic Claude Agent SDK: https://docs.anthropic.com/en/docs/claude-code/sdk
- Anthropic Managed Agents: https://docs.anthropic.com/en/docs/agents/managed-agents
- GitHub Copilot SDK: https://github.com/github/copilot-sdk
- GitHub Copilot cloud agent API: https://docs.github.com/en/rest/copilot
- Gemini Computer Use: https://ai.google.dev/gemini-api/docs/computer-use
- Cursor documentation: https://docs.cursor.com/
