import support from '../../data/support.json';
import type { SwarmBook, SwarmKind } from './books';
import type { Occurrence } from './globe';
import { REGION_ORDER, regionLabel, regionTiles, type WorldTile } from './tiles';

export class WorldPanel {
  onRegion: (regionId: string) => void = () => {};
  onTile: (id: string) => void = () => {};
  onCommand: (kind: SwarmKind) => void = () => {};
  onEnter: () => void = () => {};
  onHome: () => void = () => {};

  constructor(root: HTMLElement) {
    root.insertAdjacentHTML('beforeend', markup());
    root.querySelectorAll<HTMLButtonElement>('[data-region]').forEach((button) => {
      button.addEventListener('click', () => this.onRegion(button.dataset.region || ''));
    });
    root.querySelector('#world-home')!.addEventListener('click', () => this.onHome());
    root.querySelector('#swarm-mass')!.addEventListener('click', () => this.onCommand('mass'));
    root.querySelector('#swarm-bio')!.addEventListener('click', () => this.onCommand('bio'));
    root.querySelector('#swarm-structure')!.addEventListener('click', () => this.onCommand('structure'));
    root.querySelector('#enter-basin')!.addEventListener('click', () => this.onEnter());
  }

  showRegion(regionId: string, selectedId: string): void {
    const list = document.querySelector('#tile-list')!;
    list.innerHTML = regionTiles(regionId)
      .map(
        (tile) =>
          `<button type="button" class="tool${tile.id === selectedId ? ' active' : ''}" data-tile="${tile.id}">${tile.playable ? 'Polar Desert Basin' : tile.name}${tile.playable ? ' · measured' : ''}</button>`,
      )
      .join('');
    list.querySelectorAll<HTMLButtonElement>('[data-tile]').forEach((button) => {
      button.addEventListener('click', () => this.onTile(button.dataset.tile || ''));
    });
    document.querySelectorAll<HTMLButtonElement>('[data-region]').forEach((button) => {
      button.classList.toggle('active', button.dataset.region === regionId);
    });
  }

  showTile(tile: WorldTile, book: SwarmBook, records: Occurrence[], status: string): void {
    const box = document.querySelector('#tile-detail')!;
    const pond = Math.round(book.ponded * 100);
    box.innerHTML = `
      <div class="kicker">${tile.region}</div>
      <h2>${tile.name}</h2>
      <p class="status">${tile.playable ? 'This square holds the measured 4 × 4 km basin. Swarm orders are the giant view and do not rewrite that surface.' : 'Swarm orders on this square are a giant view. Cut and fill stay in the square. There is no measured basin here yet.'}</p>
      <div class="row"><span>Standing melt</span><span>${pond}% <i class="tag">SIM</i></span></div>
      <div class="row"><span>Cut and fill</span><span>${fmt(book.cut_m3)} m³ <i class="tag">SIM</i></span></div>
      <div class="row"><span>Stone bank</span><span>${fmt(book.stone_m3)} m³ <i class="tag">SIM</i></span></div>
      <div class="row"><span>Living surface</span><span>${book.bio ? 'opened' : 'waiting'}</span></div>
      <div class="row"><span>Civic ground</span><span>${book.built ? 'started' : 'waiting'}</span></div>
      <p class="status">${status}</p>
    `;
    const enter = document.querySelector<HTMLButtonElement>('#enter-basin')!;
    enter.hidden = !tile.playable;
    const observed = document.querySelector('#world-occurrences')!;
    observed.innerHTML = records.length
      ? records
          .slice(0, 8)
          .map(
            (record) =>
              `<div class="species"><div class="name">${record.species || record.scientificName}</div><div class="sci">${record.scientificName}</div></div>`,
          )
          .join('') + `<p class="peers">GBIF occurrences in this square. <a href="https://www.gbif.org" target="_blank" rel="noreferrer">GBIF.org</a></p>`
      : `<p class="peers">No stored GBIF occurrence falls in this square. The deployment catalog lives in the measured basin.</p>`;
  }
}

function markup(): string {
  const regions = REGION_ORDER.map(
    (id) => `<button type="button" class="tool" data-region="${id}">${regionLabel(id)}</button>`,
  ).join('');
  return `
    <header class="top">
      <div class="brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="10.5" fill="none" stroke="#d7dbe0" stroke-width="1.25"/></svg>
        <div><div class="word">ROLEPLAY</div><div class="sub">Creation division</div></div>
      </div>
      <div class="place"><strong>World map</strong><div class="muted">Tier 1 cold squares · north first</div></div>
      <button id="world-home" class="text-btn" type="button" style="width:auto">North</button>
    </header>
    <aside class="rail">
      <div class="group">Regions</div>
      ${regions}
      <div class="group">Squares</div>
      <div id="tile-list"></div>
    </aside>
    <aside class="inspector">
      <div id="tile-detail"></div>
      <div class="kicker">Swarm</div>
      <button id="swarm-mass" class="tool" type="button">Mass ton movers</button>
      <button id="swarm-bio" class="tool" type="button">Bio builder and weather</button>
      <button id="swarm-structure" class="tool" type="button">Structure builders</button>
      <button id="enter-basin" class="tool active" type="button">Enter the measured basin</button>
      <div class="kicker">Species layer</div>
      <div id="world-occurrences"></div>
      <p class="peers"><a href="${support.url}" target="_blank" rel="noreferrer">${support.label}</a> · ${support.note}</p>
    </aside>
    <div id="cesium-credit"></div>
  `;
}

function fmt(n: number): string {
  return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
}
