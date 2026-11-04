import { spawnSync } from "node:child_process";

export interface PerformanceStatus {
  k6: "NOT_RUN";
  reason: "NO_STAGING_CREDENTIALS";
  canadianClient: false;
  computeSize: null;
  apiP95Ms: null;
  payrollCalculate50k: "NOT_RUN";
}

export interface DisasterStatus {
  status: "NOT_RUN";
  reason: "NO_AWS_BACKUP_CREDENTIALS";
  region: "ca-west-1";
  restoreSeconds: null;
}

export interface SecurityStatus {
  platformGuards: "PASS" | "FAIL";
  codeql: "NOT_CONFIGURED";
  dependabot: "NOT_CONFIGURED";
  secretScanningPushProtection: "NOT_IN_REPO";
  zapBaseline: "NOT_RUN";
  annualPenTest: "NOT_RUN";
}

/** Targets in docs/02 were not measured. No compute size is recorded. */
export function performanceStatus(): PerformanceStatus {
  return {
    k6: "NOT_RUN",
    reason: "NO_STAGING_CREDENTIALS",
    canadianClient: false,
    computeSize: null,
    apiP95Ms: null,
    payrollCalculate50k: "NOT_RUN",
  };
}

/** The AWS backup account is not available to this run. No restore time is recorded. */
export function disasterRecoveryStatus(): DisasterStatus {
  return {
    status: "NOT_RUN",
    reason: "NO_AWS_BACKUP_CREDENTIALS",
    region: "ca-west-1",
    restoreSeconds: null,
  };
}

export function runPlatformGuards(repo: string): { ok: boolean } {
  const result = spawnSync(process.execPath, ["--experimental-strip-types", "scripts/platform-guards.ts"], {
    cwd: repo,
    encoding: "utf8",
  });
  return { ok: result.status === 0 };
}

export function securityStatus(guardsOk: boolean): SecurityStatus {
  return {
    platformGuards: guardsOk ? "PASS" : "FAIL",
    codeql: "NOT_CONFIGURED",
    dependabot: "NOT_CONFIGURED",
    secretScanningPushProtection: "NOT_IN_REPO",
    zapBaseline: "NOT_RUN",
    annualPenTest: "NOT_RUN",
  };
}
