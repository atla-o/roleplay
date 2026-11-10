import { boot } from './app';
import { bootRing } from './observe/boot';
import type { Occurrence } from './world/globe';
import { WorldGlobe } from './world/globe';
import { WorldPanel } from './world/panel';
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

  let status = 'Northern Canada is the first measured basin. Île René-Levasseur is the second square, for observation.';
  let tileApi: Record<string, unknown> | null = null;
  let tileStop: (() => void) | null = null;
  let mode: 'world' | 'tile' = 'world';

  const panel = new WorldPanel(world);
  const globe = new WorldGlobe(cesiumHost, credit, () => render());

  const render = () => {
    const tileNow = globe.tile();
    panel.showRegion(tileNow.regionId, tileNow.id);
    panel.showTile(tileNow, globe.book(), inside(records, tileNow), status);
  };

  panel.onHome = () => globe.frameNorth(1.2);
  panel.onRegion = (regionId) => {
    globe.frameRegion(regionId);
    const first = TILES.find((item) => item.regionId === regionId);
    if (first) globe.select(first.id, false);
  };
  panel.onTile = (id) => globe.select(id, true);
  panel.onCommand = (kind) => {
    const result = globe.command(kind);
    const names = {
      mass: 'Mass ton movers',
      bio: 'Bio builder and weather manipulator',
      structure: 'Structure builders',
      survey: 'Monitoring crew',
    };
    status = result.ok ? `${names[kind]} ${kind === 'survey' ? 'are crossing the square. No ground is moved.' : 'are crossing the square.'}` : result.reason || 'The swarm holds.';
    render();
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
    const hooks = { onWorld: () => leaveTile() };
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
      command: (kind: 'mass' | 'bio' | 'structure') => globe.command(kind),
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
