import * as Cesium from 'cesium';
import {
  commandSwarm,
  emptyBook,
  type SwarmBook,
  type SwarmKind,
} from './books';
import { PLAYABLE, RING_MARK, RING_TILE, TILES, type WorldTile } from './tiles';

const EOX =
  'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/g/{z}/{y}/{x}.jpg';

export interface Occurrence {
  region: string;
  species: string;
  scientificName: string;
  kingdom: string;
  lat: number;
  lon: number;
  year: number | null;
  dataset: string;
  gbif: string;
}

export class WorldGlobe {
  readonly viewer: Cesium.Viewer;
  private selectedId = PLAYABLE.id;
  private readonly books = new Map<string, SwarmBook>();
  private swarm: Cesium.Entity[] = [];
  private swarmKind: SwarmKind | null = null;
  private swarmT = 1;
  readonly onChange: () => void;

  constructor(container: HTMLElement, credit: HTMLElement, onChange: () => void) {
    this.onChange = onChange;
    const base = import.meta.env.BASE_URL || './';
    (window as unknown as { CESIUM_BASE_URL?: string }).CESIUM_BASE_URL = new URL('cesium/', new URL(base, window.location.href)).href;
    this.viewer = new Cesium.Viewer(container, {
      animation: false,
      timeline: false,
      geocoder: false,
      homeButton: false,
      sceneModePicker: false,
      baseLayerPicker: false,
      navigationHelpButton: false,
      fullscreenButton: false,
      infoBox: false,
      selectionIndicator: false,
      baseLayer: Cesium.ImageryLayer.fromProviderAsync(
        Cesium.TileMapServiceImageryProvider.fromUrl(Cesium.buildModuleUrl('Assets/Textures/NaturalEarthII')),
      ),
      terrainProvider: new Cesium.EllipsoidTerrainProvider(),
      creditContainer: credit,
    });
    this.viewer.clock.currentTime = Cesium.JulianDate.fromIso8601('2026-06-21T16:30:00Z');
    this.viewer.clock.shouldAnimate = false;
    this.viewer.scene.globe.enableLighting = true;
    this.viewer.scene.globe.showGroundAtmosphere = true;
    if (this.viewer.scene.skyAtmosphere) this.viewer.scene.skyAtmosphere.show = true;
    this.viewer.cesiumWidget.screenSpaceEventHandler.removeInputAction(Cesium.ScreenSpaceEventType.LEFT_DOUBLE_CLICK);
    this.addSatelliteLayer();
    this.addRingWash();
    this.drawTiles();
    this.bindPick();
    this.viewer.clock.onTick.addEventListener(() => this.tick());
    const hideIonMark = () => {
      credit.querySelectorAll<HTMLElement>('.cesium-credit-logoContainer, .cesium-credit-logo').forEach((node) => {
        node.style.display = 'none';
      });
    };
    hideIonMark();
    window.setTimeout(hideIonMark, 400);
    this.frameNorth(0);
    this.select(PLAYABLE.id, false, false);
  }

  private addSatelliteLayer(): void {
    const satellite = new Cesium.UrlTemplateImageryProvider({
      url: EOX,
      tilingScheme: new Cesium.WebMercatorTilingScheme(),
      maximumLevel: 13,
      credit: 'Sentinel-2 cloudless by EOX (CC BY 4.0), modified Copernicus Sentinel data 2021',
    });
    this.viewer.imageryLayers.addImageryProvider(satellite);
  }

  private addRingWash(): void {
    const base = import.meta.env.BASE_URL || './';
    const url = new URL('data/ile/ring.png', new URL(base, window.location.href)).href;
    void Cesium.SingleTileImageryProvider.fromUrl(url, {
      rectangle: Cesium.Rectangle.fromDegrees(RING_TILE.west, RING_TILE.south, RING_TILE.east, RING_TILE.north),
    }).then((provider) => {
      const layer = this.viewer.imageryLayers.addImageryProvider(provider);
      layer.alpha = 0.95;
    });
  }

  private drawTiles(): void {
    for (const tile of TILES) {
      const color = tile.playable ? Cesium.Color.fromCssColorString('#c5dde4') : Cesium.Color.fromCssColorString('#f4f7f8');
      this.viewer.entities.add({
        id: tile.id,
        polyline: {
          positions: ring(tile, 2500),
          width: tile.playable ? 2.4 : 1.15,
          material: color.withAlpha(tile.playable ? 0.95 : 0.72),
          arcType: Cesium.ArcType.RHUMB,
        },
      });
    }
    this.viewer.entities.add({
      id: 'reservoir-ring',
      polyline: {
        positions: reservoirRing(RING_MARK.lat, RING_MARK.lon, RING_MARK.radiusM),
        width: 2.6,
        material: Cesium.Color.fromCssColorString('#f7f4ea').withAlpha(0.92),
        arcType: Cesium.ArcType.NONE,
      },
    });
    this.viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees(RING_MARK.lon, RING_MARK.lat, 5000),
      label: {
        text: 'Île René-Levasseur',
        font: '600 13px Instrument Sans, sans-serif',
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.fromCssColorString('#121416'),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(0, -18),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
    this.viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees((PLAYABLE.west + PLAYABLE.east) / 2, BASIN_LAT, 4000),
      point: {
        pixelSize: 8,
        color: Cesium.Color.fromCssColorString('#e8f4f7'),
        outlineColor: Cesium.Color.fromCssColorString('#1c2830'),
        outlineWidth: 1,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: 'Polar Desert Basin',
        font: '600 13px Instrument Sans, sans-serif',
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.fromCssColorString('#121416'),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(12, -12),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        horizontalOrigin: Cesium.HorizontalOrigin.LEFT,
      },
    });
  }

  private bindPick(): void {
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas);
    handler.setInputAction((event: { position: Cesium.Cartesian2 }) => {
      const picked = this.viewer.scene.pick(event.position);
      const id = picked && typeof picked.id === 'object' && picked.id && 'id' in picked.id ? String(picked.id.id) : '';
      if (TILES.some((tile) => tile.id === id)) this.select(id, true);
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
  }

  tile(): WorldTile {
    return TILES.find((tile) => tile.id === this.selectedId) ?? PLAYABLE;
  }

  book(): SwarmBook {
    let book = this.books.get(this.selectedId);
    if (!book) {
      book = emptyBook();
      this.books.set(this.selectedId, book);
    }
    return book;
  }

  select(id: string, fly = true, notify = true): void {
    if (!TILES.some((tile) => tile.id === id)) return;
    this.selectedId = id;
    this.paintSelection();
    this.restSwarm();
    if (fly) this.frameTile(this.tile());
    if (notify) this.onChange();
  }

  frameRegion(regionId: string): void {
    const tiles = TILES.filter((tile) => tile.regionId === regionId);
    if (!tiles.length) return;
    const west = Math.min(...tiles.map((tile) => tile.west));
    const south = Math.min(...tiles.map((tile) => tile.south));
    const east = Math.max(...tiles.map((tile) => tile.east));
    const north = Math.max(...tiles.map((tile) => tile.north));
    this.viewer.camera.flyTo({
      destination: Cesium.Rectangle.fromDegrees(west, south, east, north),
      duration: 1.5,
    });
  }

  frameNorth(duration: number): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(-96, 62, 6_800_000),
      orientation: {
        heading: 0,
        pitch: Cesium.Math.toRadians(-58),
        roll: 0,
      },
      duration,
    });
  }

  frameTile(tile: WorldTile): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Rectangle.fromDegrees(tile.west, tile.south, tile.east, tile.north),
      duration: 1.35,
    });
  }

  command(kind: SwarmKind): { ok: boolean; reason?: string } {
    if (this.tile().mode === 'observe' && kind !== 'survey') {
      const reason = 'This square is measured research terrain. The ring is an emblem of the O, not land to reshape. A monitoring crew can cross it.';
      this.onChange();
      return { ok: false, reason };
    }
    const result = commandSwarm(this.book(), kind);
    if (!result.ok) {
      this.onChange();
      return result;
    }
    this.swarmKind = kind;
    this.swarmT = 0;
    this.ensureSwarm();
    this.onChange();
    return result;
  }

  private readonly occurrenceIds: string[] = [];

  showOccurrences(records: Occurrence[]): void {
    for (const id of this.occurrenceIds) this.viewer.entities.removeById(id);
    this.occurrenceIds.length = 0;
    records.forEach((record, index) => {
      const id = `occ-${index}-${record.lon.toFixed(2)}-${record.lat.toFixed(2)}`;
      this.occurrenceIds.push(id);
      this.viewer.entities.add({
        id,
        position: Cesium.Cartesian3.fromDegrees(record.lon, record.lat, 3000),
        point: {
          pixelSize: 5,
          color: Cesium.Color.fromCssColorString(record.kingdom === 'Animalia' ? '#e7d7b1' : '#b7d4b0'),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });
    });
  }

  pause(): void {
    this.viewer.useDefaultRenderLoop = false;
  }

  resume(): void {
    this.viewer.useDefaultRenderLoop = true;
    this.viewer.resize();
  }

  private paintSelection(): void {
    for (const tile of TILES) {
      const entity = this.viewer.entities.getById(tile.id);
      const line = entity?.polyline;
      if (!line) continue;
      const selected = tile.id === this.selectedId;
      const color = selected
        ? Cesium.Color.WHITE
        : tile.playable
          ? Cesium.Color.fromCssColorString('#c5dde4')
          : Cesium.Color.fromCssColorString('#f4f7f8');
      line.width = new Cesium.ConstantProperty(selected ? 3.2 : tile.playable ? 2.4 : 1.15);
      line.material = new Cesium.ColorMaterialProperty(color.withAlpha(selected ? 1 : 0.78));
    }
  }

  private restSwarm(): void {
    this.swarmKind = null;
    this.swarmT = 1;
    if (this.tile().mode === 'observe') {
      this.clearSwarm();
      return;
    }
    this.ensureSwarm();
    this.placeSwarm(0.08);
  }

  private clearSwarm(): void {
    for (const entity of this.swarm) this.viewer.entities.remove(entity);
    this.swarm = [];
  }

  private ensureSwarm(): void {
    if (this.swarm.length) return;
    const tile = this.tile();
    for (let i = 0; i < 42; i++) {
      const entity = this.viewer.entities.add({
        position: Cesium.Cartesian3.fromDegrees(tile.west, tile.south, 6000),
        point: {
          pixelSize: 6,
          color: swarmColor('mass'),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });
      this.swarm.push(entity);
    }
  }

  private tick(): void {
    if (!this.swarm.length) return;
    if (this.swarmT < 1) this.swarmT = Math.min(1, this.swarmT + 0.012);
    this.placeSwarm(this.swarmT);
  }

  private placeSwarm(t: number): void {
    const tile = this.tile();
    const kind = this.swarmKind ?? 'mass';
    this.swarm.forEach((entity, index) => {
      const row = index % 6;
      const col = Math.floor(index / 6);
      const across = (row + 0.5) / 6;
      const along = (col + t * 6) / 10;
      const wrapped = along - Math.floor(along);
      const lat = tile.south + (0.18 + 0.64 * across) * (tile.north - tile.south);
      const lon = tile.west + (0.12 + 0.76 * wrapped) * (tile.east - tile.west);
      entity.position = new Cesium.ConstantPositionProperty(Cesium.Cartesian3.fromDegrees(lon, lat, 9000));
      const point = entity.point;
      if (point) point.color = new Cesium.ConstantProperty(swarmColor(kind));
    });
  }
}

const BASIN_LAT = 75.397104;

function ring(tile: WorldTile, height: number): Cesium.Cartesian3[] {
  return Cesium.Cartesian3.fromDegreesArrayHeights([
    tile.west, tile.south, height,
    tile.east, tile.south, height,
    tile.east, tile.north, height,
    tile.west, tile.north, height,
    tile.west, tile.south, height,
  ]);
}

function swarmColor(kind: SwarmKind): Cesium.Color {
  if (kind === 'bio') return Cesium.Color.fromCssColorString('#d5efe4');
  if (kind === 'structure') return Cesium.Color.fromCssColorString('#e7d3a8');
  if (kind === 'survey') return Cesium.Color.fromCssColorString('#d7e6ee');
  return Cesium.Color.fromCssColorString('#f2f4f6');
}

function reservoirRing(lat: number, lon: number, radiusM: number): Cesium.Cartesian3[] {
  const coords: number[] = [];
  const steps = 96;
  for (let i = 0; i <= steps; i++) {
    const angle = (i / steps) * Math.PI * 2;
    const dLat = (radiusM * Math.cos(angle)) / 111_320;
    const dLon = (radiusM * Math.sin(angle)) / (111_320 * Math.cos((lat * Math.PI) / 180));
    coords.push(lon + dLon, lat + dLat, 1200);
  }
  return Cesium.Cartesian3.fromDegreesArrayHeights(coords);
}
