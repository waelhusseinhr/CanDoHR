import { layoutChart, type LayoutEdge, type LayoutNode } from "./layout.ts";

interface WorkerScope {
  onmessage: ((event: { data: { nodes: LayoutNode[]; edges: LayoutEdge[] } }) => void) | null;
  postMessage(message: unknown): void;
}

/** Loaded with `new Worker(new URL("./layout-worker.ts", import.meta.url))` in the browser. */
const scope = globalThis as Partial<WorkerScope>;
if (typeof scope.postMessage === "function") {
  scope.onmessage = (event) => {
    scope.postMessage?.(layoutChart(event.data.nodes, event.data.edges));
  };
}
