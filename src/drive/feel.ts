import * as Cesium from 'cesium';

/** A small engine tone made in the browser. Muted until Settings turns it on. No sampled recording. */
export class Engine {
  enabled = false;
  private ctx: AudioContext | null = null;
  private gain: GainNode | null = null;
  private osc: OscillatorNode | null = null;
  private clack: OscillatorNode | null = null;

  setEnabled(on: boolean): void {
    this.enabled = on;
    if (on) this.ensure();
    this.gain?.gain.setTargetAtTime(on ? 0.02 : 0, this.ctx?.currentTime ?? 0, 0.05);
  }

  /** Throttle is 0..1. The tone follows it and stays silent when muted. */
  throttle(amount: number): void {
    if (!this.enabled) return;
    this.ensure();
    if (!this.ctx || !this.gain || !this.osc || !this.clack) return;
    const level = Math.max(0, Math.min(1, amount));
    this.gain.gain.setTargetAtTime(0.015 + level * 0.07, this.ctx.currentTime, 0.06);
    this.osc.frequency.setTargetAtTime(42 + level * 70, this.ctx.currentTime, 0.05);
    this.clack.frequency.setTargetAtTime(12 + level * 28, this.ctx.currentTime, 0.08);
  }

  private ensure(): void {
    if (this.ctx) return;
    const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) return;
    this.ctx = new Ctx();
    this.gain = this.ctx.createGain();
    this.gain.gain.value = 0;
    this.osc = this.ctx.createOscillator();
    this.osc.type = 'sawtooth';
    this.osc.frequency.value = 42;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 240;
    this.clack = this.ctx.createOscillator();
    this.clack.type = 'square';
    this.clack.frequency.value = 14;
    const clackGain = this.ctx.createGain();
    clackGain.gain.value = 0.2;
    this.osc.connect(filter);
    this.clack.connect(clackGain);
    filter.connect(this.gain);
    clackGain.connect(this.gain);
    this.gain.connect(this.ctx.destination);
    this.osc.start();
    this.clack.start();
  }
}

interface Puff {
  position: Cesium.Cartesian3;
  life: number;
}

/** A short dust puff at the blade. Points only, no texture file. */
export class Dust {
  private readonly points: Cesium.PointPrimitiveCollection;
  private readonly puffs: Puff[] = [];
  private shown = false;

  constructor(private readonly viewer: Cesium.Viewer) {
    this.points = new Cesium.PointPrimitiveCollection();
    viewer.scene.primitives.add(this.points);
  }

  puff(lon: number, lat: number, height: number): void {
    for (let i = 0; i < 5; i++) {
      const cart = Cesium.Cartesian3.fromDegrees(lon + (Math.random() - 0.5) * 0.00005, lat + (Math.random() - 0.5) * 0.00004, height + Math.random() * 1.4);
      this.puffs.push({ position: cart, life: 0.8 + Math.random() * 0.5 });
    }
  }

  step(dt: number): void {
    if (!this.puffs.length) {
      if (this.shown) {
        this.points.removeAll();
        this.shown = false;
      }
      return;
    }
    this.shown = true;
    this.points.removeAll();
    for (let i = this.puffs.length - 1; i >= 0; i--) {
      const puff = this.puffs[i];
      if (!puff) continue;
      puff.life -= dt;
      if (puff.life <= 0) {
        this.puffs.splice(i, 1);
        continue;
      }
      Cesium.Cartesian3.add(puff.position, new Cesium.Cartesian3(0, 0, dt * 8), puff.position);
      this.points.add({
        position: puff.position,
        pixelSize: 5 + (1 - puff.life) * 6,
        color: Cesium.Color.fromCssColorString('#d9c7a4').withAlpha(Math.max(0, puff.life)),
      });
    }
  }
}

export const COACH: Record<string, string> = {
  orbit: 'Orbit looks around the spot you are on. Drag to turn. The wheel steps back. It is the shot between the two sites.',
  titan: 'Titan walks the measured ground, and the real relief between the sites. WASD moves. The mouse looks. Shift is a longer stride.',
  vehicle: 'You are on the machine. WASD drives. R raises the blade and F lowers it. The cut is one metre across. Hold E to get out.',
  sky: 'Sky sits a few hundred metres up, on the same spot. WASD moves and the mouse looks.',
};
