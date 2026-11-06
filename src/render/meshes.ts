import * as THREE from 'three';
import type { Heightfield } from '../sim/grid';
import type { MachineSpec, Sim, Species } from '../sim/sim';

const lambert = (color: number, opacity = 1) =>
  new THREE.MeshLambertMaterial({
    color,
    transparent: opacity < 1,
    opacity,
    depthWrite: opacity >= 1,
    side: opacity < 1 ? THREE.DoubleSide : THREE.FrontSide,
  });

function box(w: number, h: number, d: number, x: number, y: number, z: number, color: number, opacity = 1): THREE.Mesh {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), lambert(color, opacity));
  mesh.position.set(x, y, z);
  return mesh;
}

export function buildMachine(spec: MachineSpec): THREE.Group {
  const g = new THREE.Group();
  g.name = spec.id;
  const L = spec.length_m;
  const W = spec.width_m;
  const body = spec.class === 'miner' ? 0x4a4038 : spec.class === 'bio-builder' ? 0x3c4c50 : spec.class === 'weather' ? 0x3a4556 : spec.class === 'ark' ? 0x2e3338 : spec.class === 'builder' ? 0x5a5348 : 0x3a4148;
  g.add(box(W * 0.28, 1.05, L * 0.86, -W * 0.34, 0.62, 0, 0x2a2e32));
  g.add(box(W * 0.28, 1.05, L * 0.86, W * 0.34, 0.62, 0, 0x2a2e32));
  g.add(box(W * 0.72, spec.height_m * 0.42, L * 0.62, 0, 1.35, -L * 0.04, body));
  g.add(box(W * 0.42, spec.height_m * 0.28, L * 0.22, 0, 1.35 + spec.height_m * 0.32, -L * 0.16, 0x22262a));
  if (spec.class === 'mass-mover' || spec.class === 'miner') {
    const blade = box(spec.blade_width_m, 1.3, 0.28, 0, 0.9, L * 0.46, 0xc2b292);
    blade.rotation.x = spec.class === 'miner' ? 0.5 : 0.35;
    g.add(blade);
  }
  if (spec.class === 'bio-builder' || spec.class === 'weather') {
    g.add(box(0.16, spec.height_m, 0.16, 0, spec.height_m * 0.7, L * 0.1, 0xd5d8dc));
    g.add(box(1.6, 0.08, 1.6, 0, spec.height_m * 1.15, L * 0.1, 0xd5d8dc));
  }
  if (spec.class === 'ark') {
    g.add(box(W * 0.7, spec.height_m * 0.45, L * 0.34, 0, 1.7, L * 0.12, 0xe4dfd4));
  }
  if (spec.class === 'builder') {
    g.add(box(0.25, spec.height_m, 0.25, -W * 0.28, spec.height_m * 0.7, L * 0.2, 0xd7dbe0));
    g.add(box(0.25, spec.height_m, 0.25, W * 0.28, spec.height_m * 0.7, L * 0.2, 0xd7dbe0));
    g.add(box(W * 0.7, 0.22, 0.22, 0, spec.height_m * 1.15, L * 0.2, 0xd7dbe0));
  }
  g.traverse((obj) => {
    obj.castShadow = false;
    obj.receiveShadow = false;
  });
  return g;
}

export function syncWorks(root: THREE.Group, sim: Sim, field: Heightfield): void {
  root.clear();
  for (const dome of sim.domes) {
    const y = field.sample(dome.x, dome.z);
    const shell = new THREE.Mesh(
      new THREE.SphereGeometry(dome.radius, 28, 14, 0, Math.PI * 2, 0, Math.PI / 2),
      lambert(0xc5dde4, 0.14),
    );
    shell.position.set(dome.x, y, dome.z);
    root.add(shell);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(dome.radius, 0.12, 8, 48), lambert(0xd7dbe0));
    ring.rotation.x = Math.PI / 2;
    ring.position.set(dome.x, y + 0.15, dome.z);
    root.add(ring);
  }
  for (const bed of sim.beds) {
    const y = field.sample(bed.x, bed.z);
    const soil = box(sim.physics.bed_width_m, 0.28, sim.physics.bed_length_m, bed.x, y + 0.14, bed.z, 0x3a332c);
    soil.rotation.y = bed.heading;
    root.add(soil);
  }
  for (const planting of sim.plantings) {
    const spec = sim.speciesById(planting.speciesId);
    if (!spec) continue;
    root.add(plantingMesh(spec, planting.x, field.sample(planting.x, planting.z), planting.z, planting.growth));
  }
  for (const street of sim.streets) root.add(streetMesh(street.samples, street.width));
  for (const structure of sim.structures) {
    const y = field.sample(structure.x, structure.z);
    const group = structureMesh(structure.kind, structure.length, structure.width);
    group.position.set(structure.x, y, structure.z);
    group.rotation.y = structure.heading;
    root.add(group);
  }
}

function plantingMesh(spec: Species, x: number, y: number, z: number, growth: number): THREE.Group {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  const color = new THREE.Color(spec.color).getHex();
  const s = Math.max(0.15, growth);
  if (spec.form === 'film' || spec.form === 'crust') {
    const mesh = new THREE.Mesh(new THREE.CircleGeometry(spec.form === 'film' ? 3.2 * s : 2.4 * s, 16), lambert(color));
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.y = 0.08;
    g.add(mesh);
  } else if (spec.form === 'tuft' || spec.form === 'flower' || spec.form === 'shrub') {
    const n = spec.form === 'shrub' ? 4 : 6;
    const h = spec.form === 'shrub' ? 0.25 + 0.45 * s : 0.12 + 0.28 * s;
    for (let i = 0; i < n; i++) {
      const cone = new THREE.Mesh(new THREE.ConeGeometry(0.28 + 0.2 * s, h, 5), lambert(color));
      const a = (i / n) * Math.PI * 2;
      cone.position.set(Math.cos(a) * 0.7, h / 2, Math.sin(a) * 0.7);
      g.add(cone);
    }
  } else if (spec.form === 'crop') {
    for (let i = 0; i < 8; i++) {
      const h = 0.12 + 0.7 * s;
      const stalk = box(0.08, h, 0.08, (i - 3.5) * 0.45, h / 2, ((i % 2) - 0.5) * 0.7, color);
      g.add(stalk);
    }
  } else if (spec.form === 'conifer') {
    const h = 0.4 + 4.2 * s;
    g.add(box(0.18, h * 0.45, 0.18, 0, h * 0.2, 0, 0x5a4636));
    const cone = new THREE.Mesh(new THREE.ConeGeometry(0.7 + s, h * 0.7, 7), lambert(color));
    cone.position.y = h * 0.55;
    g.add(cone);
  } else if (spec.form === 'fauna-hare' || spec.form === 'fauna-fox') {
    const body = new THREE.Mesh(new THREE.SphereGeometry(spec.form === 'fauna-fox' ? 0.42 : 0.34, 10, 8), lambert(color));
    body.scale.set(1.5, 0.8, 0.7);
    body.position.y = 0.38;
    g.add(body);
  } else if (spec.form === 'fauna-bird') {
    const body = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.28, 4), lambert(color));
    body.position.y = 0.2;
    g.add(body);
  } else {
    const speck = new THREE.Mesh(new THREE.SphereGeometry(0.12, 6, 6), lambert(color));
    speck.position.y = 0.12;
    g.add(speck);
  }
  return g;
}

function streetMesh(samples: { x: number; z: number; y: number; bridge: boolean }[], width: number): THREE.Group {
  const group = new THREE.Group();
  if (samples.length < 2) return group;
  const positions: number[] = [];
  const colors: number[] = [];
  const indices: number[] = [];
  const half = width / 2;
  for (let i = 0; i < samples.length; i++) {
    const prev = samples[Math.max(0, i - 1)];
    const next = samples[Math.min(samples.length - 1, i + 1)];
    let dx = next.x - prev.x;
    let dz = next.z - prev.z;
    const len = Math.hypot(dx, dz) || 1;
    dx /= len;
    dz /= len;
    const s = samples[i];
    positions.push(s.x - dz * half, s.y, s.z + dx * half, s.x + dz * half, s.y, s.z - dx * half);
    const tone = s.bridge ? 0.9 : 0.84;
    colors.push(tone, tone * 0.98, tone * 0.94, tone * 0.86, tone * 0.84, tone * 0.8);
    if (i > 0) {
      const a = (i - 1) * 2;
      indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  group.add(new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true })));
  for (let i = 0; i < samples.length; i += 4) {
    if (!samples[i].bridge) continue;
    const s = samples[i];
    group.add(box(0.18, 0.9, 0.18, s.x - 3.6, s.y + 0.45, s.z, 0xd7dbe0));
    group.add(box(0.18, 0.9, 0.18, s.x + 3.6, s.y + 0.45, s.z, 0xd7dbe0));
  }
  return group;
}

function structureMesh(kind: string, length: number, width: number): THREE.Group {
  const g = new THREE.Group();
  if (kind === 'greenhouse') {
    g.add(box(width, 0.25, length, 0, 0.12, 0, 0x8d877c));
    g.add(box(width, 4.6, length, 0, 2.5, 0, 0xc5dde4, 0.18));
    g.add(box(0.12, 4.6, length, -width / 2, 2.5, 0, 0xd7dbe0));
    g.add(box(0.12, 4.6, length, width / 2, 2.5, 0, 0xd7dbe0));
    g.add(box(width, 0.12, 0.12, 0, 4.8, -length / 2, 0xd7dbe0));
    g.add(box(width, 0.12, 0.12, 0, 4.8, length / 2, 0xd7dbe0));
  } else if (kind === 'waterworks') {
    const tank = new THREE.Mesh(new THREE.CylinderGeometry(3.1, 3.1, 3.4, 18), lambert(0xc5c9ce));
    tank.position.set(-3.2, 1.7, 0);
    g.add(tank);
    const tank2 = new THREE.Mesh(new THREE.CylinderGeometry(2.4, 2.4, 2.6, 16), lambert(0xb7c4c8));
    tank2.position.set(3.4, 1.3, 1.2);
    g.add(tank2);
    g.add(box(width, 0.8, length * 0.45, 0, 0.4, -2, 0x8a8680));
    g.add(box(1.1, 0.5, 6, 0, 0.7, 4, 0x9aa7ab));
  } else {
    g.add(box(width * 0.7, 6.4, length * 0.55, -1, 3.2, 0, 0x8d877c));
    g.add(box(width * 0.42, 4.4, length * 0.7, width * 0.22, 2.2, 1.5, 0x7c776e));
    g.add(box(width * 0.9, 0.28, length * 0.62, -1, 6.5, 0, 0xd5d2cb));
    g.add(box(1.4, 2.2, 0.2, width * 0.05, 1.1, length * 0.28, 0x2c3034));
  }
  return g;
}
