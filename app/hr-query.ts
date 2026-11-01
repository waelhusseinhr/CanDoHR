import type { Locale } from "@candohr/core/screens";

type Query = Record<string, string | string[] | undefined>;

export async function readQuery(searchParams: Promise<Query> | Query | undefined): Promise<Query> {
  if (!searchParams) return {};
  return await searchParams;
}

export function one(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export function localeFrom(value: string | undefined): Locale {
  return value === "fr-CA" ? "fr-CA" : "en-CA";
}
