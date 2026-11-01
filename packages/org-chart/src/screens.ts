import { createElement as h, type ReactNode } from "react";
import type { ChartView } from "./engine.ts";
import { ct, type Locale } from "./i18n.ts";

export { ct, type Locale } from "./i18n.ts";

const shell = "mx-auto flex max-w-3xl flex-col gap-4 px-6 py-10";

export function OrgChartScreen(props: {
  locale: Locale;
  chart: ChartView;
  sample?: boolean;
  compare?: ChartView | null;
}): ReactNode {
  const { locale, chart, sample, compare } = props;
  return h(
    "main",
    { "data-screen": "org-chart", className: shell },
    h("h1", { className: "text-3xl font-semibold" }, ct(locale, "chart.title")),
    sample ? h("p", { className: "text-slate-600" }, ct(locale, "chart.sample")) : null,
    h("p", null, `${ct(locale, "chart.asOf")} ${chart.asOf}`),
    h(
      "nav",
      { "aria-label": ct(locale, "chart.hierarchy"), className: "flex gap-3 text-sm" },
      h("a", { href: "?hierarchy=management" }, ct(locale, "chart.hierarchy")),
      h("a", { href: "?compare=2026-12-01" }, ct(locale, "chart.compare")),
    ),
    chart.nodes.length === 0
      ? h("p", null, ct(locale, "chart.empty"))
      : h(
          "ul",
          { className: "divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white" },
          chart.nodes.map((node) =>
            h(
              "li",
              { key: node.id, className: "px-4 py-3" },
              h("span", null, node.title),
              h("span", null, ` · ${node.vacant ? ct(locale, "chart.vacant") : node.holders.map((holder) => holder.displayName).join(", ")}`),
              node.badges.length > 0 ? h("span", null, ` · ${node.badges.join(" ")}`) : null,
              h(
                "a",
                { href: `?move=${node.id}`, className: "ml-3 text-orange-700" },
                ct(locale, "chart.move"),
              ),
            ),
          ),
        ),
    compare
      ? h(
          "section",
          { "aria-label": ct(locale, "chart.compare") },
          h("h2", null, `${ct(locale, "chart.compare")} ${compare.asOf}`),
          h(
            "ul",
            null,
            compare.nodes.map((node) => h("li", { key: `compare-${node.id}` }, node.title)),
          ),
        )
      : null,
  );
}
