#!/usr/bin/env python3
"""oracle_query.py — consolidate the four /dev/shm Oracle logs into one per-frame view + serve them.

Replaces the scattered _oracle/*.py analyzers. Reuses their parse logic (seltcw block-walk, the
{-prefix jsonl filter); builds fresh the assembly parser, merge-by-frame, CLI query, and WS serve.
Log formats CONFIRMED against core/network/maplecast_oracle_hook.cpp.

  python tools/oracle_query.py query --char 0 --sid 0x100 [--frame N] [--logdir /dev/shm]
  python tools/oracle_query.py serve --port 8787 [--logdir /dev/shm]      # tail + WS to the dashboard
"""
import argparse, json, os, sys, time, glob

# ---------- Format A: mc_assembly.log (ASMTRACE, text) ----------
# header: # frame sid slot cid sel dx dy accX accY screenX screenY pal row flip flags r11 r13 node
_ASM_COLS = ['frame','sid','slot','cid','sel','dx','dy','accX','accY','screenX','screenY','pal','row','flip']
def parse_assembly(path):
    out = {}
    if not os.path.exists(path): return out
    with open(path, 'r', errors='replace') as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln or ln.startswith('#'): continue
            p = ln.split()
            if len(p) < 14: continue
            try:
                r = {'frame':int(p[0]), 'sid':int(p[1]), 'sid_masked':int(p[1]) & 0x7FFF,
                     'slot':int(p[2]), 'cid':int(p[3]), 'sel':int(p[4]), 'dx':int(p[5]), 'dy':int(p[6]),
                     'accX':int(p[7]), 'accY':int(p[8]), 'screenX':float(p[9]), 'screenY':float(p[10]),
                     'pal':int(p[11]), 'row':int(p[12]), 'flip':int(p[13])}
                if len(p) >= 18:
                    r['flags']=int(p[14],16); r['r11']=int(p[15],16); r['r13']=int(p[16],16); r['node']=int(p[17],16)
            except ValueError: continue
            out.setdefault(r['frame'], []).append(r)
    return out

# ---------- Formats B/C: jsonl (CHARQ, Frame Oracle) ----------
def _read_jsonl(path):
    if not os.path.exists(path): return []
    rows = []
    with open(path, 'r', errors='replace') as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln.startswith('{'): continue        # oracle_layers.load_frames filter
            try: rows.append(json.loads(ln))
            except json.JSONDecodeError: continue
    return rows

def parse_charq(path):              # mc_charq_render.jsonl -> frame -> [run-objects]
    out = {}
    for o in _read_jsonl(path):
        sid = o.get('sprite_id', -1)
        o['sprite_id_masked'] = (sid & 0x7FFF) if isinstance(sid, int) and sid >= 0 else sid
        out.setdefault(o.get('frame'), []).append(o)
    return out

def parse_oracle_hook(path):        # mc_oracle_hook.jsonl -> frame -> {objects, unassigned}
    out = {}
    for o in _read_jsonl(path):
        for ob in o.get('objects', []):
            sid = ob.get('sprite_id', -1)
            ob['sprite_id_masked'] = (sid & 0x7FFF) if isinstance(sid, int) and sid >= 0 else sid
        out[o.get('frame')] = o
    return out

# ---------- Format D: mc_probe.log (GENERIC PROBE, block text) — reuse seltcw block-walk ----------
def _le_bytes(hexbytes):            # ['XX','XX',...] little-endian -> int
    return int.from_bytes(bytes(int(b,16) for b in hexbytes), 'little')
def parse_probe(path):
    if not os.path.exists(path): return []
    blocks, cur = [], None
    with open(path, 'r', errors='replace') as fh:
        for ln in fh:
            s = ln.strip()
            if s.startswith('[PROBE'):                  # [PROBE pc=0x.. LABEL vframe=N fire=M]
                if cur: blocks.append(cur)
                cur = {'regs':{}, 'rmem':{}, 'raw':[]}
                for tok in s.strip('[]').split():
                    if '=' in tok:
                        k,v = tok.split('=',1); cur[k] = (int(v,16) if v.startswith('0x') else (int(v) if v.lstrip('-').isdigit() else v))
                    elif tok != 'PROBE': cur.setdefault('label', tok)
                continue
            if cur is None: continue
            cur['raw'].append(s)
            for tok in s.split():                       # rN=hex / pr=hex / gbr=hex ...
                if '=' in tok and len(tok.split('=',1)[1]) == 8:
                    k,v = tok.split('=',1)
                    try: cur['regs'][k] = int(v,16)
                    except ValueError: pass
            if s.startswith('rmem[') and ']:' in s:      # rmem[r11+0x6=0x..+L]:
                cur['_rmem_tag'] = s[5:s.index(']:')].split('=')[0]
            elif cur.get('_rmem_tag') and ':' in s and any(c in '0123456789abcdefABCDEF' for c in s):
                hb = [t for t in s.split()[1:] if len(t) == 2]
                if hb: cur['rmem'].setdefault(cur.pop('_rmem_tag'), _le_bytes(hb[:8]))
    if cur: blocks.append(cur)
    return blocks

def decode_tcw(tcw):                # seltcw_analyze.decode_tcw, verbatim
    return ((tcw & 0x1FFFFF) << 3, (tcw >> 21) & 0x3F, (tcw >> 27) & 7)

# ---------- merge ----------
def merge_by_frame(asm, charq, hook, probe):
    by = {}
    pf = {}
    for b in probe: pf.setdefault(b.get('vframe'), []).append(b)
    for fr in set(asm) | set(charq) | set(hook) | set(pf):
        by[fr] = {'assembly':asm.get(fr,[]), 'charq':charq.get(fr,[]),
                  'oracle':hook.get(fr), 'probe':pf.get(fr,[])}
    return by

def load_all(logdir):
    j = lambda n: os.path.join(logdir, n)
    return merge_by_frame(parse_assembly(j('mc_assembly.log')), parse_charq(j('mc_charq_render.jsonl')),
                          parse_oracle_hook(j('mc_oracle_hook.jsonl')), parse_probe(j('mc_probe.log')))

# ---------- CLI ----------
def cmd_query(a):
    by = load_all(a.logdir)
    frames = [a.frame] if a.frame is not None else sorted(by)
    sid = int(a.sid, 0) if a.sid else None
    hit = 0
    for fr in frames:
        snap = by.get(fr)
        if not snap: continue
        parts = [r for r in snap['assembly'] if (a.char is None or r['cid']==a.char) and (sid is None or r['sid_masked']==(sid&0x7FFF))]
        objs = [o for o in (snap['oracle']['objects'] if snap['oracle'] else []) if (a.char is None or o.get('owner_cid')==a.char) and (sid is None or o.get('sprite_id_masked')==(sid&0x7FFF))]
        if not parts and not objs: continue
        hit += 1
        print(f"=== frame {fr} ===")
        for o in objs: print(f"  obj cid={o.get('owner_cid')} sid=0x{(o.get('sprite_id_masked') or 0):x} kind={o.get('kind')} screen={o.get('screen_xy')} quads={len(o.get('screen_quads',[]))}")
        for r in parts[:24]: print(f"  part sel={r['sel']} dx={r['dx']} dy={r['dy']} pen=({r['accX']},{r['accY']}) screen=({r['screenX']:.1f},{r['screenY']:.1f}) flip={r['flip']}")
        if len(parts) > 24: print(f"  … +{len(parts)-24} more parts")
    print(f"[{hit} frame(s) matched]" if hit else "[no match]")

def cmd_serve(a):
    try:
        import asyncio, websockets
    except ImportError:
        sys.exit("serve needs `pip install websockets`. (CLI `query` works without it.)")
    j = lambda n: os.path.join(a.logdir, n)
    files = {'assembly':j('mc_assembly.log'), 'charq':j('mc_charq_render.jsonl'),
             'oracle':j('mc_oracle_hook.jsonl'), 'probe':j('mc_probe.log')}
    clients = set()
    async def pump():
        last = {k:0 for k in files}
        while True:
            changed = False
            for k,p in files.items():
                try: sz = os.path.getsize(p)
                except OSError: sz = 0
                if sz < last[k]: last[k] = 0          # truncate-and-rewind cap -> reset
                if sz != last[k]: last[k] = sz; changed = True
            if changed and clients:
                by = load_all(a.logdir)
                fr = max(by) if by else None
                if fr is not None:
                    msg = json.dumps({'frame':fr, **by[fr]}, default=str)
                    await asyncio.gather(*[c.send(msg) for c in list(clients)], return_exceptions=True)
            await asyncio.sleep(1/30)
    async def handler(ws):
        clients.add(ws)
        try: await ws.wait_closed()
        finally: clients.discard(ws)
    async def main():
        async with websockets.serve(handler, '127.0.0.1', a.port):
            print(f"oracle_query serving ws://127.0.0.1:{a.port} (tailing {a.logdir})"); await pump()
    asyncio.run(main())

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='cmd', required=True)
    q = sub.add_parser('query'); q.add_argument('--char', type=lambda x:int(x,0)); q.add_argument('--sid'); q.add_argument('--frame', type=int); q.add_argument('--logdir', default='/dev/shm'); q.set_defaults(fn=cmd_query)
    s = sub.add_parser('serve'); s.add_argument('--port', type=int, default=8787); s.add_argument('--logdir', default='/dev/shm'); s.set_defaults(fn=cmd_serve)
    a = ap.parse_args(); a.fn(a)
