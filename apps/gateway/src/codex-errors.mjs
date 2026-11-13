/**
 * Codex JSON-RPC errors may contain provider output, file paths or private
 * account details. Turn them into actionable, bounded, non-secret UI messages.
 * Do not echo raw provider errors into persistent O-AGENT task history.
 */
export function explainCodexError(error, operation = "resume") {
  const code = Number.isInteger(error?.code) ? error.code : null;
  const message = typeof error?.message === "string"
    ? error.message.toLowerCase() : "";
  if (/another process|already.*(in use|open|loaded|running)|locked|lock held|exclusive|being used/.test(message)) {
    return "CODEX_SESSION_BUSY: This conversation is currently owned by another Codex process. "
      + "You can still load its saved messages. To send a new turn to this exact conversation, "
      + "finish the active turn on the laptop first; do not force-close or overwrite it.";
  }
  if (/modelprovidermismatch|model provider mismatch|provider mismatch/.test(message) ||
      error?.data?.type === "modelProviderMismatch") {
    return "CODEX_MODEL_MISMATCH: This conversation was created with a different model provider. "
      + "Open it with its original provider account; saved messages can still be read.";
  }
  if (code === -32601 || /unsupported|unknown method|method not found|requires experimentalapi/.test(message)) {
    return "CODEX_UPDATE_REQUIRED: The installed Codex CLI does not support this conversation operation. "
      + "Update the official Codex CLI on the laptop, then restart O-AGENT.";
  }
  if (/not found|not exist|unknown thread|cannot find|no such/.test(message)) {
    return "CODEX_HISTORY_NOT_FOUND: This saved conversation no longer exists under the signed-in "
      + "Windows user's Codex account. Refresh your project list and check the laptop login.";
  }
  if (/not authorized|unauthorized|sign.?in|authentication|permission denied|forbidden/.test(message)) {
    return "CODEX_LOGIN_REQUIRED: The laptop Codex CLI account is not authorized. "
      + "Sign into Codex under the same Windows user running O-AGENT, then refresh.";
  }
  if (code === -32602 || /invalid params|invalid request/.test(message)) {
    return "CODEX_PROTOCOL_ERROR: This Codex CLI version rejected the " + operation
      + " request. Check Codex CLI version and app-server compatibility.";
  }
  const codeLabel = code == null ? "" : " (RPC " + code + ")";
  return "CODEX_PROVIDER_ERROR: Codex rejected the " + operation + " request" + codeLabel
    + ". Check the signed-in laptop account, CLI version and current conversation state. "
    + "Use Load conversation to inspect available saved messages.";
}
