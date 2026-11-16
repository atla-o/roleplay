/** Tier 1 cold regions, split into selectable squares. One square holds the measured basin. */
export const BASIN = { lat: 75.397104, lon: -89.509007 };

export type TileMode = 'abstract' | 'terraform' | 'observe';

export interface WorldTile {
  id: string;
  name: string;
  region: string;
  regionId: string;
  west: number;
  south: number;
  east: number;
  north: number;
  playable: boolean;
  mode: TileMode;
}

interface Band {
  regionId: string;
  region: string;
  west: number;
  south: number;
  east: number;
  north: number;
  dLon: number;
  dLat: number;
}

const BANDS: Band[] = [
  { regionId: 'northern-canada', region: 'Northern Canada', west: -128, south: 60, east: -64, north: 84, dLon: 8, dLat: 4 },
  { regionId: 'north-dakota', region: 'United States', west: -104.5, south: 45.9, east: -96.5, north: 49.1, dLon: 4, dLat: 3.2 },
  { regionId: 'alaska', region: 'United States', west: -166, south: 66, east: -141, north: 71.5, dLon: 12.5, dLat: 5.5 },
  { regionId: 'northern-europe', region: 'Northern Europe', west: 5, south: 60, east: 32, north: 71, dLon: 9, dLat: 5.5 },
  { regionId: 'svalbard', region: 'Northern Europe', west: 10, south: 76, east: 30, north: 81, dLon: 10, dLat: 5 },
  { regionId: 'russia', region: 'Russia', west: 40, south: 66, east: 180, north: 78, dLon: 20, dLat: 6 },
  { regionId: 'antarctica', region: 'Antarctica', west: -180, south: -86, east: 180, north: -70, dLon: 45, dLat: 8 },
];

export const REGION_ORDER = [
  'northern-canada',
  'cote-nord',
  'north-dakota',
  'alaska',
  'northern-europe',
  'svalbard',
  'russia',
  'antarctica',
] as const;

/** Official island centre, Commission de toponymie du Québec. */
export const RING_CENTER = { lat: 51.43995, lon: -68.73717 };

/**
 * Geometric centre of the reservoir on the 2020 land-cover grid.
 * The drawn O uses this so it sits on the water, not on the toponym point.
 */
export const RING_MARK = { lat: 51.39, lon: -68.683, radiusM: 29_500 };

export const RING_TILE: WorldTile = {
  id: 'rene-levasseur',
  name: 'Île René-Levasseur',
  region: 'Quebec',
  regionId: 'cote-nord',
  west: -69.25,
  south: 51.0,
  east: -68.15,
  north: 51.75,
  playable: true,
  mode: 'observe',
};

export const TILES: WorldTile[] = [...BANDS.flatMap((band) => tilesIn(band)), RING_TILE];

export const PLAYABLE = TILES.find((tile) => tile.id === 'polar-desert-basin')!;

function tilesIn(band: Band): WorldTile[] {
  const tiles: WorldTile[] = [];
  let n = 0;
  for (let lon = band.west; lon < band.east - 1e-6; lon += band.dLon) {
    for (let lat = band.south; lat < band.north - 1e-6; lat += band.dLat) {
      const west = round(lon);
      const south = round(lat);
      const east = round(Math.min(band.east, lon + band.dLon));
      const north = round(Math.min(band.north, lat + band.dLat));
      const playable = BASIN.lon >= west && BASIN.lon < east && BASIN.lat >= south && BASIN.lat < north;
      tiles.push({
        id: playable ? 'polar-desert-basin' : `${band.regionId}-${n}`,
        name: playable ? 'Polar Desert Basin' : squareName(south, north, west, east),
        region: band.region,
        regionId: band.regionId,
        west,
        south,
        east,
        north,
        playable,
        mode: playable ? 'terraform' : 'abstract',
      });
      n += 1;
    }
  }
  return tiles;
}

export function regionTiles(regionId: string): WorldTile[] {
  return TILES.filter((tile) => tile.regionId === regionId);
}

const REGION_LABELS: Record<string, string> = {
  'northern-canada': 'Northern Canada',
  'cote-nord': 'Côte-Nord',
  'north-dakota': 'North Dakota',
  alaska: 'Alaska',
  'northern-europe': 'Northern Europe',
  svalbard: 'Svalbard',
  russia: 'Russia',
  antarctica: 'Antarctica',
};

export function regionLabel(regionId: string): string {
  return REGION_LABELS[regionId] ?? regionId;
}

function squareName(south: number, north: number, west: number, east: number): string {
  return `${fmtLat(south)}–${fmtLat(north)} · ${fmtLon(west)}–${fmtLon(east)}`;
}

function fmtLat(value: number): string {
  const abs = Math.abs(Math.round(value));
  return `${abs}°${value < 0 ? 'S' : 'N'}`;
}

function fmtLon(value: number): string {
  const abs = Math.abs(Math.round(value));
  return `${abs}°${value < 0 ? 'W' : 'E'}`;
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}
