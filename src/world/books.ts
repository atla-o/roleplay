/** Giant-scale books. Volumes are sim parameters. The measured basin is not edited from here. */

export type SwarmKind = 'mass' | 'bio' | 'structure';

export interface SwarmBook {
  cut_m3: number;
  fill_m3: number;
  stone_m3: number;
  ponded: number;
  bio: boolean;
  built: boolean;
}

export const SWARM_CUT_M3 = 1_800_000;
export const STONE_FRACTION = 0.38;
export const DRAIN_STEP = 0.18;
export const BIO_POND_LIMIT = 0.55;
export const STRUCTURE_STONE_M3 = 420_000;

export function emptyBook(): SwarmBook {
  return { cut_m3: 0, fill_m3: 0, stone_m3: 0, ponded: 0.72, bio: false, built: false };
}

export function commandSwarm(book: SwarmBook, kind: SwarmKind): { ok: boolean; reason?: string } {
  if (kind === 'mass') {
    book.cut_m3 += SWARM_CUT_M3;
    book.fill_m3 += SWARM_CUT_M3;
    book.stone_m3 += SWARM_CUT_M3 * STONE_FRACTION;
    book.ponded = Math.max(0, book.ponded - DRAIN_STEP);
    return { ok: true };
  }
  if (kind === 'bio') {
    if (book.ponded > BIO_POND_LIMIT) {
      return { ok: false, reason: 'Meltwater still covers too much of this square for a living surface.' };
    }
    book.bio = true;
    return { ok: true };
  }
  if (!book.bio) return { ok: false, reason: 'The biological monitor has not opened this square.' };
  if (book.stone_m3 + 1 < STRUCTURE_STONE_M3) {
    return { ok: false, reason: 'The stone bank is short. Run the mass movers again.' };
  }
  book.stone_m3 -= STRUCTURE_STONE_M3;
  book.built = true;
  return { ok: true };
}
