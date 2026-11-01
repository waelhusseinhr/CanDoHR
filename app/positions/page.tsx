import { PositionList } from "@candohr/core/screens";
import { HrChrome } from "../hr-chrome.tsx";
import { localeFrom, one, readQuery } from "../hr-query.ts";
import { SAMPLE_POSITIONS } from "../sample-hr.ts";

export default async function PositionsPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const query = await readQuery(searchParams);
  const locale = localeFrom(one(query.lang));
  return (
    <HrChrome locale={locale} path="/positions">
      <PositionList locale={locale} positions={SAMPLE_POSITIONS} sample />
    </HrChrome>
  );
}
