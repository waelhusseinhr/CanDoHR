import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { LOCALES, assertLocalesComplete, messageKeys, t } from "@candohr/access";
import { assertCoreLocales, coreMessageKeys, ct as coreText } from "@candohr/core";
import { assertChartLocales, chartMessageKeys, ct as chartText } from "@candohr/org-chart";

export interface ScreenCheck {
  routes: string[];
  findings: string[];
  axe: "NOT_RUN";
  documentLang: string | null;
}

function listScreens(appDir: string): string[] {
  const routes: string[] = [];
  const walk = (dir: string, route: string): void => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        const segment = name.startsWith("[") && name.endsWith("]") ? `:${name.slice(1, -1)}` : name;
        walk(path, `${route}/${segment}`);
      } else if (name === "page.tsx") {
        routes.push(route === "" ? "/" : route);
      }
    }
  };
  walk(appDir, "");
  routes.sort();
  return routes;
}

function scanMarkup(dir: string, findings: string[]): void {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      if (name === "node_modules") continue;
      scanMarkup(path, findings);
      continue;
    }
    if (!name.endsWith(".tsx")) continue;
    const text = readFileSync(path, "utf8");
    if (/<img\b(?![^>]*\balt=)/.test(text)) findings.push(`IMG_ALT_MISSING:${name}`);
    if (/<button\b[^>]*>\s*<\/button>/.test(text)) findings.push(`BUTTON_NAME_MISSING:${name}`);
  }
}

/** Static check of the sample screens. axe-core is not in this repository, so it is not run. */
export function checkScreens(repo: string): ScreenCheck {
  const appDir = join(repo, "app");
  const findings: string[] = [];
  const layout = readFileSync(join(appDir, "layout.tsx"), "utf8");
  const htmlLang = "<html lang" + '="';
  const lang = layout.match(new RegExp(htmlLang + "([^" + '"]+)'));
  const captured = lang ? lang[1] : "";
  const documentLang = captured.length > 0 ? captured : null;
  if (!documentLang) findings.push("DOCUMENT_LANG_MISSING");
  const chrome = readFileSync(join(appDir, "hr-chrome.tsx"), "utf8");
  const skipHref = "href" + '="#content"';
  const contentId = "id" + '="content"';
  if (!chrome.includes("lang={locale}")) findings.push("CHROME_LANG_MISSING");
  if (!chrome.includes(skipHref)) findings.push("SKIP_LINK_MISSING");
  if (!chrome.includes(contentId)) findings.push("CONTENT_TARGET_MISSING");
  if (!chrome.includes('ct(locale, "nav.skip")')) findings.push("SKIP_TEXT_MISSING");
  scanMarkup(appDir, findings);
  scanMarkup(join(repo, "packages", "core", "src"), findings);
  scanMarkup(join(repo, "packages", "org-chart", "src"), findings);
  return { routes: listScreens(appDir), findings, axe: "NOT_RUN", documentLang };
}

/** English and French screen strings in access, core, and the org chart. */
export function assertScreenLanguages(): void {
  assertLocalesComplete();
  assertCoreLocales();
  assertChartLocales();
  for (const locale of LOCALES) {
    for (const key of messageKeys()) {
      if (t(locale, key).length === 0) throw new Error("TRANSLATION_MISSING");
    }
    for (const key of coreMessageKeys()) {
      if (coreText(locale, key).length === 0) throw new Error("TRANSLATION_MISSING");
    }
    for (const key of chartMessageKeys()) {
      if (chartText(locale, key).length === 0) throw new Error("TRANSLATION_MISSING");
    }
  }
}
