// Reads a FrameScout "Export Project Backup" ZIP in the browser (stored or deflated entries), using
// the built-in DecompressionStream. Only project.json and each scan's plan.json are taken.
import type { FloorPlan, ProjectBundle } from '../model/types';

async function inflate(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as BlobPart]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

export async function readBackupZip(file: Blob): Promise<ProjectBundle> {
  const buf = new Uint8Array(await file.arrayBuffer());
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new Error('Not a ZIP file');
  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const dec = new TextDecoder();
  const files = new Map<string, () => Promise<Uint8Array>>();
  for (let n = 0; n < count; n++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break;
    const method = dv.getUint16(p + 10, true);
    const csize = dv.getUint32(p + 20, true);
    const nameLen = dv.getUint16(p + 28, true), extraLen = dv.getUint16(p + 30, true), commentLen = dv.getUint16(p + 32, true);
    const local = dv.getUint32(p + 42, true);
    const name = dec.decode(buf.subarray(p + 46, p + 46 + nameLen));
    const start = local + 30 + dv.getUint16(local + 26, true) + dv.getUint16(local + 28, true);
    const raw = buf.subarray(start, start + csize);
    files.set(name, () => (method === 0 ? Promise.resolve(raw) : inflate(raw)));
    p += 46 + nameLen + extraLen + commentLen;
  }
  const manifest = [...files.keys()].filter(k => k.endsWith('project.json') && !k.includes('__MACOSX')).sort((a, b) => a.length - b.length)[0];
  if (!manifest) throw new Error('This archive is not a FrameScout project backup (no project.json found).');
  const project = JSON.parse(dec.decode(await files.get(manifest)!()));
  const plans: Record<string, FloorPlan> = {};
  for (const [name, read] of files) {
    const m = name.match(/Scans\/([0-9A-Fa-f-]{36})\/plan\.json$/);
    if (m) plans[m[1].toUpperCase()] = JSON.parse(dec.decode(await read()));
  }
  return { project, plans };
}
