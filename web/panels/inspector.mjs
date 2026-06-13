// inspector.mjs — labeled memory inspector backed by web/labels.json (the re_kb-grounded manifest).
// READ-side: resolve an address/offset -> field label + type + class + note + edit-safety, and decode
// the typed value. Edit-safety is advisory here; actual writes go through the gated mod-layer RAM_WRITE
// (control WS), whitelisted to editable:true LOGICAL fields — NEVER the engine pointer cluster.

const TYPE_LEN = { u8:1, s8:1, u16:2, s16:2, flags:2, u32:4, f32:4, ptr:4, enum:1 };
const hx = (s) => (typeof s === 'string' ? parseInt(s, 16) : s) >>> 0;

export class Inspector {
  constructor(manifest) { this.m = manifest; this.roster = manifest._meta?.roster || {}; }
  static async load(url = './labels.json?v=1') { return new Inspector(await (await fetch(url)).json()); }

  fields(kind) { return this.m[kind]?.fields || []; }       // kind: char_struct | globals | pool_node
  typeLen(t) { return TYPE_LEN[t] || 1; }

  // field whose [off, off+len) contains `off` (off relative for struct/pool, absolute for globals)
  fieldAt(kind, off) {
    for (const f of this.fields(kind)) {
      const o = hx(f.off), len = this.typeLen(f.type);
      if (off >= o && off < o + len) return f;
    }
    return null;
  }

  // decode `bytes` (Uint8Array, little-endian, length>=typeLen) for a field -> {value, display}
  decode(f, bytes) {
    if (!bytes || !bytes.length) return { value: null, display: '—' };
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let v;
    switch (f.type) {
      case 'u8': case 'enum': case 'flags': v = bytes[0]; break;
      case 's8': v = (bytes[0] << 24) >> 24; break;
      case 'u16': v = dv.getUint16(0, true); break;
      case 's16': v = dv.getInt16(0, true); break;
      case 'u32': case 'ptr': v = dv.getUint32(0, true); break;
      case 'f32': v = dv.getFloat32(0, true); break;
      default: v = bytes[0];
    }
    return { value: v, display: this.format(f, v) };
  }

  format(f, v) {
    if (v == null) return '—';
    if (f.type === 'f32') return v.toFixed(3);
    if (f.type === 'ptr' || f.type === 'u32') return '0x' + (v >>> 0).toString(16).toUpperCase();
    if (f.type === 'flags') return '0b' + v.toString(2).padStart(8, '0');
    if (f.type === 'enum') {
      const key = '0x' + v.toString(16).toUpperCase().padStart(2, '0');
      const e = f.enum || {};
      if (e.ref === '_meta.roster') return `${v} (${this.roster[key] || this.roster['0x' + v.toString(16).toUpperCase()] || '?'})`;
      return `${v} (${e[String(v)] || e[key] || '?'})`;
    }
    return String(v);
  }

  // one-line hover label for a clicked cell
  describe(kind, off) {
    const f = this.fieldAt(kind, off);
    if (!f) return { name: 'unlabeled', note: 'no re_kb field at this offset — the un-RE\'d frontier', editable: false, cls: 'unknown' };
    return { name: f.name, type: f.type, cls: f.class, editable: !!f.editable, note: f.note, field: f };
  }

  // build a field-list table into `host`; readBytes(absAddr,len)->Uint8Array (optional, for live values)
  renderFieldList(host, kind, slotBase, readBytes) {
    const base = hx(slotBase || 0);
    const rows = this.fields(kind).map((f) => {
      const o = hx(f.off);
      const addr = kind === 'globals' ? o : base + o;
      let val = '—';
      if (readBytes) { const b = readBytes(addr, this.typeLen(f.type)); if (b) val = this.decode(f, b).display; }
      const lock = f.editable ? '' : '🔒';
      const cls = f.class === 'engine' ? 'eng' : f.class === 'object' ? 'obj' : 'log';
      return `<tr class="${cls}" title="${(f.note || '').replace(/"/g, '&quot;')}">
        <td>+0x${o.toString(16).toUpperCase()}</td><td>${f.name}</td>
        <td class="ty">${f.type}</td><td class="val">${val}</td><td>${lock}</td></tr>`;
    }).join('');
    host.innerHTML = `<table class="flds"><thead><tr><th>off</th><th>field</th><th>type</th><th>value</th><th></th></tr></thead><tbody>${rows}</tbody></table>`;
  }
}
