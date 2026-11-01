export interface LayoutNode {
  id: string;
}

export interface LayoutEdge {
  from: string;
  to: string;
}

export interface PlacedNode {
  id: string;
  x: number;
  y: number;
}

/**
 * Places boxes from the reporting lines. A collapsed chart only passes the open
 * subtree, so a large organization does not lay out every box at once.
 * The browser runs this inside layout-worker.ts.
 */
export function layoutChart(nodes: readonly LayoutNode[], edges: readonly LayoutEdge[]): PlacedNode[] {
  const children = new Map<string, string[]>();
  const childIds = new Set<string>();
  for (const edge of edges) {
    const list = children.get(edge.from) ?? [];
    list.push(edge.to);
    children.set(edge.from, list);
    childIds.add(edge.to);
  }
  const roots = nodes.filter((node) => !childIds.has(node.id)).map((node) => node.id);
  const placed: PlacedNode[] = [];
  let cursor = 0;
  const visit = (id: string, depth: number): void => {
    placed.push({ id, x: cursor, y: depth * 120 });
    cursor += 180;
    for (const child of children.get(id) ?? []) visit(child, depth + 1);
  };
  for (const root of roots) visit(root, 0);
  const seen = new Set(placed.map((node) => node.id));
  for (const node of nodes) {
    if (seen.has(node.id)) continue;
    placed.push({ id: node.id, x: cursor, y: 0 });
    cursor += 180;
  }
  return placed;
}
