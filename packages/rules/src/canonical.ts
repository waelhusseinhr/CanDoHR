/** Canonical JSON: sorted keys, no extra space. Agreement versions are hashed in this form. */
export function canonicalize(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map((item) => canonicalize(item)).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value as Record<string, unknown>).sort(([left], [right]) =>
      left < right ? -1 : left > right ? 1 : 0,
    );
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalize(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
