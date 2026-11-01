/** Live updates (docs/02, PLAT-021). Messages carry identifiers only. */

export interface LiveMessage {
  type: string;
  asOf: string;
  units: string[];
}

interface Session {
  sessionId: string;
  userId: string;
  units: Set<string>;
  canSee: (unitId: string) => boolean;
  inbox: LiveMessage[];
}

export class SessionHub {
  private readonly sessions = new Map<string, Session>();

  subscribe(input: { sessionId: string; userId: string; units: readonly string[]; canSee: (unitId: string) => boolean }): void {
    this.sessions.set(input.sessionId, {
      sessionId: input.sessionId,
      userId: input.userId,
      units: new Set(input.units),
      canSee: input.canSee,
      inbox: [],
    });
  }

  /** Pushes `{ type, asOf, units }` to sessions that asked for that unit and are allowed to see it. */
  publish(message: LiveMessage & Record<string, unknown>): void {
    const safe: LiveMessage = {
      type: message.type,
      asOf: message.asOf,
      units: [...message.units],
    };
    for (const session of this.sessions.values()) {
      const units = safe.units.filter((unit) => session.units.has(unit) && session.canSee(unit));
      if (units.length === 0) continue;
      session.inbox.push({ type: safe.type, asOf: safe.asOf, units });
    }
  }

  inbox(sessionId: string): LiveMessage[] {
    return this.sessions.get(sessionId)?.inbox.map((message) => ({ ...message, units: [...message.units] })) ?? [];
  }
}
