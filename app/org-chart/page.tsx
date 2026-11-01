import { OrgChartScreen, type Locale } from "@candohr/org-chart/screens";
import { HrChrome } from "../hr-chrome.tsx";
import { localeFrom, one, readQuery } from "../hr-query.ts";
import { SAMPLE_TODAY, sampleView } from "../sample-chart.ts";

export default async function OrgChartPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const query = await readQuery(searchParams);
  const locale: Locale = localeFrom(one(query.lang));
  const asOf = one(query.asOf) ?? SAMPLE_TODAY;
  const compareAsOf = one(query.compare);
  const chart = sampleView(asOf);
  const compare = compareAsOf ? sampleView(compareAsOf) : null;
  return (
    <HrChrome locale={locale} path="/org-chart">
      <OrgChartScreen locale={locale} chart={chart} compare={compare} sample />
    </HrChrome>
  );
}
