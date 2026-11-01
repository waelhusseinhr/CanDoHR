import { PositionScreen } from "@candohr/core/screens";
import { HrChrome } from "../../hr-chrome.tsx";
import { localeFrom, one, readQuery } from "../../hr-query.ts";
import { SAMPLE_POSITIONS } from "../../sample-hr.ts";

export default async function PositionPage({
  params,
  searchParams,
}: {
  params: Promise<{ positionId: string }> | { positionId: string };
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const [{ positionId }, query] = await Promise.all([params, readQuery(searchParams)]);
  const locale = localeFrom(one(query.lang));
  const position = SAMPLE_POSITIONS.find((row) => row.id === positionId) ?? null;
  return (
    <HrChrome locale={locale} path={`/positions/${positionId}`}>
      <PositionScreen locale={locale} position={position} />
    </HrChrome>
  );
}
