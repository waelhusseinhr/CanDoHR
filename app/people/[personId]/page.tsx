import { PersonProfile } from "@candohr/core/screens";
import { HrChrome } from "../../hr-chrome.tsx";
import { localeFrom, one, readQuery } from "../../hr-query.ts";
import { SAMPLE_PROFILES, profileTab } from "../../sample-hr.ts";

export default async function PersonPage({
  params,
  searchParams,
}: {
  params: Promise<{ personId: string }> | { personId: string };
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const [{ personId }, query] = await Promise.all([params, readQuery(searchParams)]);
  const locale = localeFrom(one(query.lang));
  const tab = profileTab(one(query.tab));
  return (
    <HrChrome locale={locale} path={`/people/${personId}`} tab={tab}>
      <PersonProfile locale={locale} profile={SAMPLE_PROFILES[personId] ?? null} tab={tab} />
    </HrChrome>
  );
}
