import { boot } from './app';
import { bootRing } from './observe/boot';
import type { Occurrence } from './world/globe';
import { WorldGlobe } from './world/globe';
import { WorldPanel } from './world/panel';
import type { SwarmKind } from './world/books';
import { PLAYABLE, TILES } from './world/tiles';

export async function start(root: HTMLElement): Promise<void> {
  const world = document.createElement('div');
  world.id = 'world';
  const cesiumHost = document.createElement('div');
  cesiumHost.id = 'cesium';
  const credit = document.createElement('div');
  credit.id = 'cesium-credit';
  world.append(cesiumHost, credit);
  const tile = document.createElement('div');
  tile.id = 'tile';
  tile.hidden = true;
  root.append(world, tile);

  const base = import.meta.env.BASE_URL || './';
  const occurrences = await fetch(`${base}data/occurrences.json`)
    .then((response) => response.json())
    .catch(() => ({ records: [] as Occurrence[] }));
  const records = (occurrences.records ?? []) as Occurrence[];

  let status = 'Pick a square. Polar Desert Basin is where crews move the ground. Île René-Levasseur is for observation.';
  let intent: SwarmKind | null = null;
  let intentTile: string | null = null;
  let tileApi: Record<string, unknown> | null = null;
  let tileStop: (() => void) | null = null;
  let mode: 'world' | 'tile' = 'world';

  const panel = new WorldPanel(world);
  const globe = new WorldGlobe(cesiumHost, credit, () => render());

  const render = () => {
    const tileNow = globe.tile();
    panel.showRegion(tileNow.regionId, tileNow.id);
    const armed = tileNow.id === intentTile ? intent : null;
    panel.showTile(tileNow, globe.book(), inside(records, tileNow), status, armed);
  };

  panel.onHome = () => globe.frameNorth(1.2);
  panel.onRegion = (regionId) => {
    globe.frameRegion(regionId);
    const first = TILES.find((item) => item.regionId === regionId);
    if (first) globe.select(first.id, false);
  };
  panel.onTile = (id) => globe.select(id, true);
  const order = (kind: SwarmKind) => {
    const result = globe.command(kind);
    const chosen = globe.tile();
    if (result.ok && kind !== 'survey' && chosen.mode === 'terraform') {
      intent = kind;
      intentTile = chosen.id;
    }
    if (!result.ok) status = result.reason || 'The swarm holds.';
    else if (kind === 'survey') status = 'Monitoring crew are crossing the square. No ground is moved.';
    else if (chosen.playable && chosen.mode === 'terraform') {
      status = 'That crew is booked. Open the basin to cut, drain, grade, or build. The giant tally does not rewrite the surface by itself.';
    } else status = 'That crew is on the giant view only. This square has no measured surface yet.';
    render();
    return result;
  };
  panel.onCommand = (kind) => {
    order(kind);
  };
  panel.onEnter = () => {
    void enterBasin();
  };
  globe.showOccurrences(records);
  globe.select(PLAYABLE.id, false);
  globe.frameNorth(0);
  render();

  async function enterBasin(): Promise<void> {
    const chosen = globe.tile();
    if (!chosen.playable) {
      status = 'This square has no measured surface yet.';
      render();
      return;
    }
    globe.pause();
    world.hidden = true;
    tile.hidden = false;
    mode = 'tile';
    tileStop?.();
    tile.replaceChildren();
    const armed = chosen.id === intentTile ? intent : null;
    const hooks = { onWorld: () => leaveTile(), intent: armed === 'survey' ? null : armed };
    const started = chosen.mode === 'observe' ? await bootRing(tile, hooks) : await boot(tile, hooks);
    tileApi = started;
    tileStop = typeof started.stop === 'function' ? (started.stop as () => void) : null;
    publish();
  }

  function leaveTile(): void {
    tileStop?.();
    tileStop = null;
    tileApi = null;
    tile.hidden = true;
    world.hidden = false;
    mode = 'world';
    globe.resume();
    publish();
  }

  function publish(): void {
    const tileMethods = tileApi ?? {};
    window.__roleplay = {
      ...tileMethods,
      ready: true,
      tileReady: Boolean(tileApi),
      mode: () => mode,
      playableId: PLAYABLE.id,
      selectTile: (id: string) => globe.select(id, true),
      command: (kind: SwarmKind) => order(kind),
      book: () => ({ ...globe.book() }),
      enterBasin,
      showWorld: () => leaveTile(),
    };
  }

  publish();
}

function inside(records: Occurrence[], tile: { west: number; south: number; east: number; north: number }): Occurrence[] {
  return records.filter(
    (record) => record.lon >= tile.west && record.lon < tile.east && record.lat >= tile.south && record.lat < tile.north,
  );
}
