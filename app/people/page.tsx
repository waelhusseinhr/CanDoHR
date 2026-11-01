import { PeopleList } from "@candohr/core/screens";
import { HrChrome } from "../hr-chrome.tsx";
import { localeFrom, one, readQuery } from "../hr-query.ts";
import { SAMPLE_PEOPLE } from "../sample-hr.ts";

export default async function PeoplePage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const query = await readQuery(searchParams);
  const locale = localeFrom(one(query.lang));
  return (
    <HrChrome locale={locale} path="/people">
      <PeopleList locale={locale} people={SAMPLE_PEOPLE} sample />
    </HrChrome>
  );
}
