/** Read-only, tenant-RLS-backed usage metering. This deliberately does NOT
 * charge cards, infer tokens from prompts, fabricate invoices or activate a
 * subscription: payment callbacks require a real verified provider later.
 */
export async function tenantUsage(client) {
  const {rows}=await client.query(
    `SELECT count(*) FILTER (WHERE created_at >= date_trunc('month',now()))::int AS requests_this_month,
      count(*) FILTER (WHERE created_at >= now()-interval '24 hours')::int AS requests_last_24_hours,
      count(*) FILTER (WHERE created_at >= date_trunc('month',now()) AND status='completed')::int AS completed_this_month,
      count(*) FILTER (WHERE created_at >= date_trunc('month',now()) AND status='failed')::int AS failed_this_month,
      count(*) FILTER (WHERE status='waiting_for_approval')::int AS pending_approvals
    FROM runs`);
  return {
    billingStatus:"not_configured",
    paidSubscriptionActive:false,
    oAgentChargesRecorded:false,
    providerCostsSeparate:true,
    currency:null,amountDue:null,estimatedProviderTokens:null,
    metering:"actual tenant-scoped run records (not model-token billing)",
    limits:{runsPerRolling24Hours:200,pendingApprovals:30},
    usage:rows[0],
  };
}
