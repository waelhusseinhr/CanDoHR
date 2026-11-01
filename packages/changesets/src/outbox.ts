/**
 * Outbox relay (docs/05 §4, PLAT-020).
 * Production runs this alarm inside a Durable Object. It reads unpublished rows
 * through Hyperdrive with caching disabled, using FOR UPDATE SKIP LOCKED, then
 * dispatches to subscribers and the webhook queue.
 * Tests use MemoryOutboxStore. No database binding is added until that Hyperdrive configuration exists.
 */

const SENSITIVE = new Set(["sin", "banking", "bank", "salary", "rate", "payAmount", "health"]);

export interface OutboxMessage {
  eventId: string;
  subjectKey: string;
  type: string;
  payload: Record<string, unknown>;
  createdAt: string;
  publishedAt: string | null;
  failures: number;
  dead: boolean;
}

export interface OutboxStore {
  listUnpublished(): OutboxMessage[];
  markPublished(eventId: string, at: string): void;
  markFailure(eventId: string): void;
  replay(eventId: string): void;
  alreadyProcessed(subscriber: string, eventId: string): boolean;
  recordProcessed(subscriber: string, eventId: string): void;
}

export class MemoryOutboxStore implements OutboxStore {
  readonly rows: OutboxMessage[] = [];
  private readonly processed = new Set<string>();

  add(row: Omit<OutboxMessage, "publishedAt" | "failures" | "dead"> & Partial<Pick<OutboxMessage, "publishedAt" | "failures" | "dead">>): void {
    this.rows.push({
      publishedAt: null,
      failures: 0,
      dead: false,
      ...row,
    });
  }

  listUnpublished(): OutboxMessage[] {
    return this.rows
      .filter((row) => row.publishedAt === null && !row.dead)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt) || a.eventId.localeCompare(b.eventId));
  }

  markPublished(eventId: string, at: string): void {
    const row = this.must(eventId);
    row.publishedAt = at;
    row.dead = false;
  }

  markFailure(eventId: string): void {
    const row = this.must(eventId);
    row.failures += 1;
    if (row.failures >= 10) row.dead = true;
  }

  replay(eventId: string): void {
    const row = this.must(eventId);
    row.dead = false;
    row.failures = 0;
    row.publishedAt = null;
  }

  alreadyProcessed(subscriber: string, eventId: string): boolean {
    return this.processed.has(`${subscriber}:${eventId}`);
  }

  recordProcessed(subscriber: string, eventId: string): void {
    this.processed.add(`${subscriber}:${eventId}`);
  }

  private must(eventId: string): OutboxMessage {
    const row = this.rows.find((item) => item.eventId === eventId);
    if (!row) throw new Error(`missing outbox row ${eventId}`);
    return row;
  }
}

export interface Subscriber {
  name: string;
  handle(message: OutboxMessage): void;
}

export class WebhookQueue {
  readonly messages: Record<string, unknown>[] = [];
  enqueue(payload: Record<string, unknown>): void {
    this.messages.push(payload);
  }
}

export class OutboxRelay {
  /** Test hook: the next successful handle stops before published_at, as if the process restarted. */
  private crashBeforePublish = false;
  private readonly store: OutboxStore;
  private readonly subscribers: readonly Subscriber[];
  private readonly webhooks: WebhookQueue;

  constructor(store: OutboxStore, subscribers: readonly Subscriber[], webhooks: WebhookQueue) {
    this.store = store;
    this.subscribers = subscribers;
    this.webhooks = webhooks;
  }

  failOnceBeforePublish(): void {
    this.crashBeforePublish = true;
  }

  /**
   * One alarm tick. Events for one subject stay in commit order.
   * A subscriber that already recorded the event id is skipped, so a restart cannot apply it twice.
   */
  alarm(now: string): void {
    const blocked = new Set<string>();
    for (const row of this.store.listUnpublished()) {
      if (blocked.has(row.subjectKey)) continue;
      try {
        for (const subscriber of this.subscribers) {
          if (this.store.alreadyProcessed(subscriber.name, row.eventId)) continue;
          subscriber.handle(row);
          this.store.recordProcessed(subscriber.name, row.eventId);
        }
        if (this.crashBeforePublish) {
          this.crashBeforePublish = false;
          throw new Error("RELAY_RESTART");
        }
        this.webhooks.enqueue(redact(row.payload) as Record<string, unknown>);
        this.store.markPublished(row.eventId, now);
      } catch (error) {
        if (error instanceof Error && error.message === "RELAY_RESTART") throw error;
        this.store.markFailure(row.eventId);
        blocked.add(row.subjectKey);
      }
    }
  }
}

export function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map((item) => redact(item));
  if (!value || typeof value !== "object") return value;
  const out: Record<string, unknown> = {};
  for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
    out[key] = SENSITIVE.has(key) ? { changed: true } : redact(inner);
  }
  return out;
}
