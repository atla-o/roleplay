import phases from '../../data/phases.json';
import support from '../../data/support.json';
import type { Species } from '../sim/sim';

export type ToolId =
  | 'orbit'
  | 'walk'
  | 'channel'
  | 'drain'
  | 'grade'
  | 'mine'
  | 'survey'
  | 'dome'
  | 'bed'
  | 'ark'
  | 'street'
  | 'greenhouse'
  | 'waterworks'
  | 'township';

const TOOLS: { id: ToolId; label: string; group: string }[] = [
  { group: 'View', id: 'orbit', label: 'Orbit' },
  { group: 'View', id: 'walk', label: 'Walk the land' },
  { group: 'Phase 1', id: 'channel', label: 'Cut channel' },
  { group: 'Phase 1', id: 'drain', label: 'Drain pond' },
  { group: 'Phase 1', id: 'grade', label: 'Grade pad' },
  { group: 'Phase 1', id: 'mine', label: 'Mine stone' },
  { group: 'Phase 2', id: 'survey', label: 'Survey ground' },
  { group: 'Phase 2', id: 'dome', label: 'Set shelter' },
  { group: 'Phase 2', id: 'bed', label: 'Soil bed' },
  { group: 'Phase 3', id: 'ark', label: 'Gene Ark' },
  { group: 'Phase 4', id: 'street', label: 'Lay street' },
  { group: 'Phase 4', id: 'greenhouse', label: 'Greenhouse' },
  { group: 'Phase 4', id: 'waterworks', label: 'Water works' },
  { group: 'Phase 4', id: 'township', label: 'Township module' },
];

export class Hud {
  tool: ToolId = 'orbit';
  speciesId = 'hordeum';
  action = 'clone';
  onTool: (id: ToolId) => void = () => {};
  onDay: (day: number) => void = () => {};
  onOverlay: () => void = () => {};
  onRestore: () => void = () => {};
  onCommit: () => void = () => {};
  readonly slopeBox: HTMLInputElement;
  readonly waterBox: HTMLInputElement;
  readonly hydroBox: HTMLInputElement;
  private readonly status: HTMLElement;
  private readonly reading: HTMLElement;
  private readonly bank: HTMLElement;
  private readonly seasonLabel: HTMLElement;
  private readonly phase: HTMLElement;
  private readonly compass: HTMLElement;
  private readonly scaleBar: HTMLElement;
  private readonly scaleLabel: HTMLElement;
  private readonly crosshair: HTMLElement;
  private readonly ticks: HTMLElement;
  private readonly vision: HTMLDialogElement;
  private readonly about: HTMLDialogElement;

  constructor(root: HTMLElement, species: Species[]) {
    root.insertAdjacentHTML('beforeend', markup(species));
    this.status = root.querySelector('#status')!;
    this.reading = root.querySelector('#reading')!;
    this.bank = root.querySelector('#bank')!;
    this.seasonLabel = root.querySelector('#season-label')!;
    this.phase = root.querySelector('#phase-label')!;
    this.compass = root.querySelector('#compass')!;
    this.scaleBar = root.querySelector('#scale-bar')!;
    this.scaleLabel = root.querySelector('#scale-label')!;
    this.crosshair = root.querySelector('#crosshair')!;
    this.ticks = root.querySelector('#ticks')!;
    this.vision = root.querySelector('#vision')!;
    this.about = root.querySelector('#about')!;
    this.slopeBox = root.querySelector('#ov-slope')!;
    this.waterBox = root.querySelector('#ov-water')!;
    this.hydroBox = root.querySelector('#ov-hydro')!;

    root.querySelectorAll<HTMLButtonElement>('[data-tool]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.tool = btn.dataset.tool as ToolId;
        this.paintTools();
        this.onTool(this.tool);
      });
    });
    root.querySelector('#day')!.addEventListener('input', (ev) => {
      this.onDay(Number((ev.target as HTMLInputElement).value));
    });
    for (const box of [this.slopeBox, this.waterBox, this.hydroBox]) box.addEventListener('change', () => this.onOverlay());
    root.querySelector('#open-vision')!.addEventListener('click', () => this.vision.showModal());
    root.querySelector('#open-about')!.addEventListener('click', () => this.about.showModal());
    root.querySelector('#restore')!.addEventListener('click', () => this.onRestore());
    root.querySelectorAll('[data-close]').forEach((btn) => btn.addEventListener('click', () => (btn.closest('dialog') as HTMLDialogElement).close()));
    root.querySelectorAll<HTMLButtonElement>('[data-species]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.speciesId = btn.dataset.species!;
        this.action = btn.dataset.action || this.action;
        this.paintSpecies();
        this.tool = 'ark';
        this.paintTools();
        this.onTool('ark');
      });
    });
    this.paintTools();
    this.paintSpecies();
    this.renderMilestones(new Set());
  }

  paintTools(): void {
    document.querySelectorAll<HTMLButtonElement>('[data-tool]').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tool === this.tool);
    });
    this.crosshair.classList.toggle('on', this.tool === 'walk');
  }

  private paintSpecies(): void {
    document.querySelectorAll<HTMLElement>('[data-card]').forEach((card) => {
      card.classList.toggle('active', card.dataset.card === this.speciesId);
    });
  }

  setStatus(text: string): void {
    this.status.textContent = text;
  }

  setReading(html: string): void {
    this.reading.innerHTML = html;
  }

  setBank(text: string): void {
    this.bank.textContent = text;
  }

  setSeason(day: number, label: string): void {
    this.seasonLabel.textContent = label;
    const input = document.querySelector<HTMLInputElement>('#day');
    if (input && document.activeElement !== input) input.value = String(day);
  }

  setPhase(text: string): void {
    this.phase.textContent = text;
  }

  setCompass(rad: number): void {
    this.compass.style.transform = `rotate(${rad}rad)`;
  }

  setScale(meters: number, px: number): void {
    this.scaleBar.style.width = `${px}px`;
    this.scaleLabel.textContent = meters >= 1000 ? `${meters / 1000} km` : `${meters} m`;
  }

  renderMilestones(earned: Set<string>): void {
    this.ticks.innerHTML = phases.milestones
      .map((m) => `<li class="${earned.has(m.id) ? 'on' : ''}">${m.name}</li>`)
      .join('');
  }

  requestCommit(): void {
    this.onCommit();
  }
}

function markup(species: Species[]): string {
  let last = '';
  const tools = TOOLS.map((tool) => {
    const head = tool.group !== last ? `<div class="group">${(last = tool.group)}</div>` : '';
    return `${head}<button class="tool" data-tool="${tool.id}" type="button">${tool.label}</button>`;
  }).join('');
  const melt = phases ? '' : '';
  void melt;
  const cards = species
    .map(
      (s) => `<div class="species" data-card="${s.id}">
        <button type="button" data-species="${s.id}" data-action="${s.actions[0]}">
          <div class="name">${s.common}</div>
          <div class="sci">${s.scientific}</div>
        </button>
        <div class="actions">${s.actions
          .map((a) => `<button type="button" data-species="${s.id}" data-action="${a}">${a}</button>`)
          .join('')}</div>
      </div>`,
    )
    .join('');
  const phaseBlocks = phases.phases.map((p) => `<h3>Phase ${p.id} — ${p.name}</h3><p>${p.text}</p>`).join('');
  const peers = `Atla LLC. Six equal divisions. Physics: ${phases.peers.physics.join(', ')}. Biology: ${phases.peers.biology.join(', ')}.`;
  return `
    <header class="top">
      <div class="brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="10.5" fill="none" stroke="#d7dbe0" stroke-width="1.25"/></svg>
        <div><div class="word">ROLEPLAY</div><div class="sub">Creation division</div></div>
      </div>
      <div class="place"><strong>Northern Canada</strong><div class="muted">Polar Desert Basin · 4 × 4 km</div></div>
      <button id="open-vision" class="text-btn" type="button" style="width:auto">Vision</button>
      <div class="phase" id="phase-label">Phase 1</div>
    </header>
    <aside class="rail">${tools}<div class="group">Surface</div><button id="restore" class="text-btn" type="button">Restore measured</button></aside>
    <aside class="inspector">
      <div class="kicker">Under the cursor</div>
      <div id="reading"></div>
      <div class="kicker">Work</div>
      <p class="status" id="status"></p>
      <div class="kicker">Overlay</div>
      <label class="row"><span>Slope</span><input id="ov-slope" type="checkbox" checked /></label>
      <label class="row"><span>Meltwater</span><input id="ov-water" type="checkbox" checked /></label>
      <label class="row"><span>Surveyed hydrography</span><input id="ov-hydro" type="checkbox" checked /></label>
      <div class="kicker">Gene Ark</div>
      ${cards}
    </aside>
    <footer class="dock">
      <div class="season">
        <div class="track">
          <i class="melt" style="left:${(152 / 365) * 100}%;width:${((274 - 152) / 365) * 100}%"></i>
          <i class="window" style="left:${(166 / 365) * 100}%;width:${(90 / 365) * 100}%"></i>
          <input id="day" type="range" min="1" max="365" value="188" />
        </div>
        <div class="season-label" id="season-label">Day 188 · growing window</div>
      </div>
      <div class="bank" id="bank"></div>
      <div class="links">
        <button id="open-about" type="button">Attribution</button>
        <a href="${support.url}" target="_blank" rel="noreferrer">${support.label}</a>
      </div>
    </footer>
    <div class="nav"><div class="compass" id="compass">N</div><div class="scale"><i id="scale-bar"></i><span id="scale-label"></span></div></div>
    <div class="crosshair" id="crosshair"></div>
    <dialog id="vision">
      <button class="close" data-close type="button">Close</button>
      <h2>Vision</h2>
      <p>${phases.intro}</p>
      <p class="peers">${peers}</p>
      ${phaseBlocks}
      <h3>Milestones</h3>
      <ul class="ticks" id="ticks"></ul>
      <p class="peers">${support.note}</p>
    </dialog>
    <dialog id="about">
      <button class="close" data-close type="button">Close</button>
      <h2>Attribution</h2>
      <p>Roleplay is a pure digital simulation built from open elevation data with no land claim or ground impact.</p>
      <p>The basin is framed as Northern Canada, a polar desert, 4 × 4 km. The measured surface is the EPSG:3413 window from −1,116,740 m to −1,112,740 m east and −1,136,011 m to −1,132,011 m north, centre 75.3971°N, 89.509°W.</p>
      <h3>Elevation</h3>
      <p>ArcticDEM v4.1, 2 m mosaic, resampled for this view. © Polar Geospatial Center, University of Minnesota. Porter et al. 2023. <a href="https://doi.org/10.7910/DVN/3VDC4W">https://doi.org/10.7910/DVN/3VDC4W</a>. Licence <a href="https://creativecommons.org/licenses/by/4.0/">CC-BY-4.0</a>.</p>
      <h3>Hydrography</h3>
      <p>Natural Resources Canada, National Hydro Network, work unit 10VE001, flowlines and waterbodies. <a href="https://open.canada.ca/en/open-government-licence-canada">Open Government Licence – Canada</a>.</p>
      <p>Slope, closed depressions, and flow accumulation are derived from the measured DEM. Machine rates, detention, and the ninety-day window are labeled in the inspector as sim parameters.</p>
      <p class="peers">Creation division · published at atlas.rehab. The viewer is Three.js, MIT.</p>
    </dialog>
  `;
}
