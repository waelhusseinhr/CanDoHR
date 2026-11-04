import { fail } from "./errors.ts";

export type CompetencyModel = {
  framework_code: string;
  version: string;
  status: string;
  competencies: { code: string; domain: string; indicators_status: string }[];
};

export function publishStarter(model: CompetencyModel): { frameworkCode: string; version: string; status: "published" } {
  for (const competency of model.competencies) {
    if (competency.indicators_status !== "as_provided" && competency.indicators_status !== "reviewed") {
      fail("INDICATORS_STATUS_NOT_ACCEPTED", competency.code);
    }
  }
  return { frameworkCode: model.framework_code, version: model.version, status: "published" };
}

export type Architecture = {
  competency_groups: Record<string, string[]>;
  levels: { code: string; competency_defaults: Record<string, number | null> }[];
  tracks: { code: string }[];
  starter_job_families: { code: string }[];
};

export function proposeCareerTargets(arch: Architecture, levelCode: string): {
  competency: string;
  domain: string;
  level: number;
  status: "proposed";
  active: false;
}[] {
  let level: Architecture["levels"][number] | undefined;
  for (const item of arch.levels) if (item.code === levelCode) level = item;
  if (level === undefined) fail("INPUT_REQUIRED", levelCode);
  const proposed: { competency: string; domain: string; level: number; status: "proposed"; active: false }[] = [];
  for (const domain of Object.keys(level.competency_defaults)) {
    const target = level.competency_defaults[domain];
    if (target === null || target === undefined) continue;
    const codes = arch.competency_groups[domain];
    if (codes === undefined) fail("INPUT_REQUIRED", domain);
    for (const competency of codes) {
      proposed.push({ competency, domain, level: target, status: "proposed", active: false });
    }
  }
  return proposed;
}
