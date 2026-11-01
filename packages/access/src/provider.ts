import { CanDoError } from "@candohr/shared";

/** Capabilities in ref.provider_capability (migrations 0010 and 0012). */
export const PROVIDER_CAPABILITIES = [
  "payroll_prepare",
  "payroll_approve",
  "payroll_files",
  "employee_records_read",
  "employee_records_edit",
  "reports",
  "benefits_plan_costs",
  "benefits_individual_data",
] as const;

export type ProviderCapability = (typeof PROVIDER_CAPABILITIES)[number];

export type GrantStatus = "requested" | "approved" | "revoked" | "expired";

export interface ProviderGrant {
  grantId: string;
  clientTenantId: string;
  providerTenantId: string;
  providerUserId: string;
  capabilities: readonly string[];
  validFrom: string;
  validTo: string;
  status: GrantStatus;
  approvedBy: string | null;
  approvedAt: string | null;
}

export interface DirectoryUser {
  userId: string;
  tenantId: string;
}

function assertKnownCapabilities(capabilities: readonly string[]): void {
  for (const capability of capabilities) {
    if (!PROVIDER_CAPABILITIES.includes(capability as ProviderCapability)) {
      throw new CanDoError("PROVIDER_CAPABILITY_UNKNOWN");
    }
  }
}

export function requestProviderGrant(input: {
  grantId: string;
  clientTenantId: string;
  providerTenantId: string;
  providerUserId: string;
  capabilities: readonly string[];
  validFrom: string;
  validTo: string;
  users: readonly DirectoryUser[];
}): ProviderGrant {
  if (input.providerTenantId === input.clientTenantId) throw new CanDoError("PROVIDER_NOT_SELF");
  assertKnownCapabilities(input.capabilities);
  const providerUser = input.users.find((user) => user.userId === input.providerUserId);
  if (!providerUser || providerUser.tenantId !== input.providerTenantId) {
    throw new CanDoError("PROVIDER_USER_UNKNOWN");
  }
  return {
    grantId: input.grantId,
    clientTenantId: input.clientTenantId,
    providerTenantId: input.providerTenantId,
    providerUserId: input.providerUserId,
    capabilities: [...input.capabilities],
    validFrom: input.validFrom,
    validTo: input.validTo,
    status: "requested",
    approvedBy: null,
    approvedAt: null,
  };
}

/** Only a user of the client organization can approve. The provider cannot approve their own grant. */
export function approveProviderGrant(grant: ProviderGrant, approver: DirectoryUser, approvedAt: string): ProviderGrant {
  if (approver.tenantId !== grant.clientTenantId) throw new CanDoError("PROVIDER_GRANT_NOT_CLIENT");
  if (approver.userId === grant.providerUserId) throw new CanDoError("PROVIDER_GRANT_NOT_CLIENT");
  return { ...grant, status: "approved", approvedBy: approver.userId, approvedAt };
}

/** Same rule as platform.provider_can: approved, in period, and the capability is on the grant. */
export function providerCan(grants: readonly ProviderGrant[], clientTenantId: string, providerUserId: string, capability: string, at: string): boolean {
  return grants.some(
    (grant) =>
      grant.clientTenantId === clientTenantId &&
      grant.providerUserId === providerUserId &&
      grant.status === "approved" &&
      grant.validFrom <= at &&
      at < grant.validTo &&
      grant.capabilities.includes(capability),
  );
}

export interface RequestContext {
  tenantId: string;
  userId: string;
  providerTenantId: string | null;
}

/** A provider request carries exactly one client. Switching clients starts a new context. */
export function assertOneClient(context: RequestContext, clientTenantId: string): void {
  if (context.tenantId !== clientTenantId) throw new CanDoError("PROVIDER_CLIENT_CONTEXT");
}

export interface ProviderAudit {
  tenantId: string;
  actorType: "user";
  actorId: string;
  providerTenantId: string;
  action: string;
  subjectType: string;
  subjectId: string;
}

/** The client's audit row names the provider user and the provider's organization. */
export function providerAudit(input: {
  clientTenantId: string;
  providerUserId: string;
  providerTenantId: string;
  action: string;
  subjectType: string;
  subjectId: string;
}): ProviderAudit {
  return {
    tenantId: input.clientTenantId,
    actorType: "user",
    actorId: input.providerUserId,
    providerTenantId: input.providerTenantId,
    action: input.action,
    subjectType: input.subjectType,
    subjectId: input.subjectId,
  };
}
