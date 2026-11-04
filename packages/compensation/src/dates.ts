function pad(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function parts(iso: string): { y: number; m: number; d: number } {
  const bits = iso.split("-");
  return { y: Number(bits[0]), m: Number(bits[1]), d: Number(bits[2]) };
}

export function formatDate(y: number, m: number, d: number): string {
  return `${y}-${pad(m)}-${pad(d)}`;
}

export function addDays(iso: string, days: number): string {
  const p = parts(iso);
  const utc = Date.UTC(p.y, p.m - 1, p.d) + days * 24 * 60 * 60 * 1000;
  const dt = new Date(utc);
  return formatDate(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

export function addCalendarMonths(iso: string, months: number): string {
  const p = parts(iso);
  let index = p.y * 12 + (p.m - 1) + months;
  let year = Math.floor(index / 12);
  let monthIndex = index % 12;
  if (monthIndex < 0) {
    monthIndex += 12;
    year -= 1;
  }
  const month = monthIndex + 1;
  const dim = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const day = p.d > dim ? dim : p.d;
  return formatDate(year, month, day);
}

export function compareDates(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}
