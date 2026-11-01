import { OrgChart, type ChartView } from "@candohr/org-chart";

const TODAY = "2026-11-01";
const KNOWN = "2026-11-01T15:00:00.000Z";

/** Sample boxes for the chart page. The database is not connected. */
export function sampleChart(): OrgChart {
  const chart = new OrgChart({ today: TODAY, knownAt: KNOWN });
  chart.addUnit({ id: "parks", parentId: null, name: "Parks", province: "MB", costCentreId: "cc-parks" });
  chart.addBox({
    positionId: "pos-ben",
    title: "Manager",
    orgUnitId: "parks",
    reportsToPositionId: null,
    holder: { personId: "ben", name: "Ben", assignmentId: "asg-ben" },
  });
  chart.addBox({
    positionId: "pos-chloe",
    title: "Director",
    orgUnitId: "parks",
    reportsToPositionId: null,
    holder: { personId: "chloe", name: "Chloe", assignmentId: "asg-chloe" },
  });
  chart.addBox({
    positionId: "pos-ana",
    title: "Clerk",
    orgUnitId: "parks",
    reportsToPositionId: "pos-ben",
    holder: { personId: "ana", name: "Ana", assignmentId: "asg-ana" },
  });
  return chart;
}

export function sampleView(asOf: string): ChartView {
  return sampleChart().chart({ asOf });
}

export const SAMPLE_TODAY = TODAY;
