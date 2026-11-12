/**
 * Shared contract for provider-managed sessions and OMIO-owned workspaces.
 *
 * This manifest is descriptive, not an authorization grant. The server still
 * evaluates policy before every operation. An adapter must not advertise a
 * capability until its implementation and contract tests pass.
 */

export type ConnectionState =
  | "not_connected"
  | "authorizing"
  | "connected"
  | "degraded"
  | "expired"
  | "revoked"
  | "error"
  | "unsupported";

export type CapabilityState = "supported" | "unsupported" | "requires_setup" | "preview";

export type CapabilityKey =
  | "create_session"
  | "send_message"
  | "stream_events"
  | "resume_session"
  | "interrupt"
  | "cancel"
  | "pause"
  | "steer"
  | "tool_approval"
  | "screenshots"
  | "desktop_stream"
  | "remote_input"
  | "filesystem"
  | "terminal"
  | "artifacts"
  | "usage"
  | "cost";

export interface CapabilityDescriptor {
  state: CapabilityState;
  /** User-readable explanation for disabled/preview/setup-dependent controls. */
  reason?: string;
  /** Version or API date against which the adapter was verified. */
  verifiedAgainst?: string;
  /** Optional documentation URL for the exact capability. */
  documentationUrl?: string;
}

export interface ProviderCapabilityManifest {
  providerId: string;
  adapterId: string;
  adapterVersion: string;
  connectionState: ConnectionState;
  authenticatedAt?: string;
  lastHealthCheckAt?: string;
  lastHealthCheckError?: string;
  authMethod: "oauth" | "api_key" | "device_code" | "local_sdk" | "managed_session" | "none";
  scopes: string[];
  capabilities: Record<CapabilityKey, CapabilityDescriptor>;
  limits?: {
    maxConcurrentRuns?: number;
    requestsPerMinute?: number;
    dailyBudgetMinorUnits?: number;
    currency?: string;
    notes?: string[];
  };
  lifecycle?: {
    beta: boolean;
    preview: boolean;
    deprecated: boolean;
    sunsetAt?: string;
  };
}

/**
 * UI rule: controls are actionable only if the adapter says supported,
 * connectionState is connected, the user's server-side policy permits the
 * operation, and the current run/session is in a valid state.
 */
export function canRenderAction(
  manifest: ProviderCapabilityManifest,
  capability: CapabilityKey,
): boolean {
  return (
    manifest.connectionState === "connected" &&
    manifest.capabilities[capability]?.state === "supported"
  );
}
