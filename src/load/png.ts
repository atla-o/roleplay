/** Decode a grayscale PNG (8- or 16-bit) written by the bake. */
export async function decodeGrayPng(buffer: ArrayBuffer): Promise<{
  width: number;
  height: number;
  bitDepth: number;
  samples: Uint16Array;
}> {
  const bytes = new Uint8Array(buffer);
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) {
    if (bytes[i] !== sig[i]) throw new Error('Measured raster is not a PNG.');
  }
  let pos = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idat: Uint8Array[] = [];
  while (pos + 8 <= bytes.length) {
    const length = readU32(bytes, pos);
    const tag = String.fromCharCode(bytes[pos + 4], bytes[pos + 5], bytes[pos + 6], bytes[pos + 7]);
    const data = bytes.subarray(pos + 8, pos + 8 + length);
    pos += 12 + length;
    if (tag === 'IHDR') {
      width = readU32(data, 0);
      height = readU32(data, 4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error('Interlaced rasters are not used.');
    } else if (tag === 'IDAT') {
      idat.push(data);
    } else if (tag === 'IEND') {
      break;
    }
  }
  if (colorType !== 0 || (bitDepth !== 16 && bitDepth !== 8)) {
    throw new Error('Expected a grayscale height raster.');
  }
  const total = idat.reduce((n, chunk) => n + chunk.length, 0);
  const packed = new Uint8Array(total);
  let offset = 0;
  for (const chunk of idat) {
    packed.set(chunk, offset);
    offset += chunk.length;
  }
  const raw = await inflateZlib(packed);
  const bpp = bitDepth === 16 ? 2 : 1;
  const stride = width * bpp;
  const out = new Uint8Array(height * stride);
  let cursor = 0;
  for (let r = 0; r < height; r++) {
    const filter = raw[cursor++];
    const rowStart = r * stride;
    for (let i = 0; i < stride; i++) {
      const x = raw[cursor++];
      const a = i >= bpp ? out[rowStart + i - bpp] : 0;
      const b = r > 0 ? out[rowStart - stride + i] : 0;
      const c = r > 0 && i >= bpp ? out[rowStart - stride + i - bpp] : 0;
      let value = x;
      if (filter === 1) value = (x + a) & 255;
      else if (filter === 2) value = (x + b) & 255;
      else if (filter === 3) value = (x + ((a + b) >> 1)) & 255;
      else if (filter === 4) value = (x + paeth(a, b, c)) & 255;
      else if (filter !== 0) throw new Error('Unknown PNG filter.');
      out[rowStart + i] = value;
    }
  }
  const samples = new Uint16Array(width * height);
  if (bitDepth === 16) {
    for (let i = 0; i < samples.length; i++) samples[i] = (out[i * 2] << 8) | out[i * 2 + 1];
  } else {
    for (let i = 0; i < samples.length; i++) samples[i] = out[i];
  }
  return { width, height, bitDepth, samples };
}

function readU32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
}

function paeth(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

async function inflateZlib(data: Uint8Array): Promise<Uint8Array> {
  const copy = new Uint8Array(data.byteLength);
  copy.set(data);
  const stream = new Blob([copy]).stream().pipeThrough(new DecompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
