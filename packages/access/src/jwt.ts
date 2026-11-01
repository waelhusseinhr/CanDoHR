import { CanDoError } from "@candohr/shared";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

export interface VerifiedSubject {
  sub: string;
}

/**
 * Verifies a Supabase access token against the project's published signing keys.
 * The subject (`sub`) is the only claim used to find the user.
 */
export async function verifySupabaseJwt(token: string, jwksUrl: string, issuer: string): Promise<VerifiedSubject> {
  const jwks = createRemoteJWKSet(new URL(jwksUrl));
  const { payload } = await jwtVerify(token, jwks, { issuer, audience: "authenticated" });
  return { sub: subjectFromClaims(payload) };
}

/**
 * Reads `sub` and nothing else. `user_metadata` is user-editable and is never a tenant or a role.
 */
export function subjectFromClaims(payload: JWTPayload & { user_metadata?: unknown }): string {
  if (typeof payload.sub !== "string" || payload.sub.length === 0) throw new CanDoError("JWT_SUBJECT");
  return payload.sub;
}

export interface AppUser {
  userId: string;
  tenantId: string;
  idpSubject: string;
  email: string;
  locale: "en-CA" | "fr-CA";
  status: "active" | "disabled";
  personId: string | null;
  formerEmployeeUntil: string | null;
  roleCodes: readonly string[];
}

/** Loads the user from the directory keyed by the token subject. Disabled users cannot sign in. */
export function loadAppUser(sub: string, users: readonly AppUser[]): AppUser {
  const user = users.find((item) => item.idpSubject === sub);
  if (!user) throw new CanDoError("USER_UNKNOWN");
  if (user.status === "disabled") throw new CanDoError("USER_DISABLED");
  return user;
}
