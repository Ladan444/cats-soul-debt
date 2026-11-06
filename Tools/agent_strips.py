"""Листы агента arena.ai → полосы кадров 4×1: фон, один ряд из сетки, деление по просветам, рост, палитра, обводка.
Лучшие листы партий 1 и 2; голова жителей приведена к чиби (замер доли — глазами, см. HEAD). Дальше — build_art_sheets.py.

  python Tools/agent_strips.py [имя ...]    (Арт/Генерации/agent, agent_v2 → Арт/Генерации/sprites_final)
"""
import glob
import os
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_to_sprite as gen

ROOT = Path(__file__).resolve().parent.parent
a1 = str(ROOT / "Арт" / "Генерации" / "agent" / "sprites")
a2 = str(ROOT / "Арт" / "Генерации" / "agent_v2" / "sprites_v2")
a3 = str(ROOT / "Арт" / "Генерации" / "agent_v3")  # Агата и Ларп
out = str(ROOT / "Арт" / "Генерации" / "sprites_final")

HEIGHT = dict(ray=48, horst=46, marta=40, ilza=46, hans=50, oda=46, klaus=50, mika=26, silvia=50,
              liara=56, guide=44, spirit=40, drowned=50, lake_creature=26, agata=44, larp=46)
THR = 235
THR_BY = dict(drowned=170)
ATTACK_CELL = (128, 80)

def flood_bg(img, THR=THR):
    """Фон — заливкой от краёв листа: белый мех и фартуки внутри контура остаются."""
    img = img.convert('RGBA'); px = img.load(); w, h = img.size
    light = lambda p: p[0] > THR and p[1] > THR and p[2] > THR
    q = deque(); seen = bytearray(w*h)
    for x in range(w):
        for y in (0, h-1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w-1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        i = y*w+x
        if seen[i] or not light(px[x, y]): continue
        seen[i] = 1; px[x, y] = (0, 0, 0, 0)
        if x > 0: q.append((x-1, y))
        if x < w-1: q.append((x+1, y))
        if y > 0: q.append((x, y-1))
        if y < h-1: q.append((x, y+1))
    return img

def spans(profile, gap, minlen):
    res = []; s = last = None
    for i, v in enumerate(profile):
        if v:
            if s is None: s = i
            last = i
        elif s is not None and i-last > gap:
            res.append((s, last)); s = None
    if s is not None: res.append((s, last))
    return [r for r in res if r[1]-r[0] >= minlen]

def pick_row(img):
    a = img.getchannel('A').filter(ImageFilter.MinFilter(3)); w, h = img.size; d = a.load()
    rows = spans([sum(d[x, y] > 0 for x in range(0, w, 2)) > 1 for y in range(h)], 4, 6)
    if len(rows) < 2: return img, len(rows)
    tall = max(r[1]-r[0] for r in rows)
    r = next(r for r in rows if r[1]-r[0] >= tall*0.7)
    return img.crop((0, max(0, r[0]-1), w, min(h, r[1]+2))), len(rows)

def split4(img):
    a = img.getchannel('A').filter(ImageFilter.MinFilter(3)); w, h = img.size; d = a.load()
    cols = spans([sum(d[x, y] > 0 for y in range(h)) > 0 for x in range(w)], 2, 6)
    if len(cols) == 4:
        cuts = [0] + [(cols[i][1]+cols[i+1][0])//2 for i in range(3)] + [w]
        how = 'gaps'
    else:
        cuts = [w*i//4 for i in range(5)]; how = f'equal({len(cols)})'
    views = []
    for i in range(4):
        p = img.crop((cuts[i], 0, cuts[i+1], h))
        views.append(p.crop(p.getchannel('A').getbbox() or (0, 0, 1, 1)))
    return views, how

V2 = set('''horst_walk_front marta_walk_front marta_walk_side klaus_walk_side silvia_walk_back drowned_walk_side drowned_attack_side ray_attack_side
lake_creature_walk_front lake_creature_walk_back lake_creature_walk_side lake_creature_attack_front lake_creature_attack_back lake_creature_attack_side lake_creature_death_side'''.split())
TARGET = 0.38
# доля головы от роста сейчас (замер глазами), без тонких предметов
HEAD = {
 'horst': dict(front=.26, back=.26, side=.25),
 'ilza':  dict(front=.32, back=.32, side=.33),
 'hans':  dict(front=.30, back=.27, side=.30),
 'oda':   dict(front=.27, back=.27, side=.24),
 'klaus': dict(front=.27, back=.30, side=.30),
 'silvia': dict(front=.44, back=.42, side=.45),  # вместе с ушами
}
TARGET_BY = dict(silvia=.50)

def enlarge(v, frac, target):
    h0 = v.height; k = max(3, h0//30) | 1
    a = v.getchannel('A').point(lambda p: 255 if p else 0)
    blob = a.filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))
    bb = blob.getbbox()
    if not bb: return v
    top, bot = bb[1], v.height
    neck = top + int((bot-top)*frac)
    # ширина головы — по верхним 60 % полосы: ниже уже могут быть плечи
    head_rows = blob.crop((0, top, v.width, top+int((neck-top)*.6)))
    hb = head_rows.getbbox()
    x0, x1 = hb[0], hb[2]
    s = target*(1-frac)/((1-target)*frac)
    head = v.crop((x0, top, x1, neck))
    keep = blob.crop((x0, top, x1, neck)).filter(ImageFilter.MaxFilter(3))
    clean = Image.new('RGBA', head.size); clean.paste(head, (0,0), keep)
    nw, nh = round(head.width*s), round(head.height*s)
    big = clean.resize((nw, nh), Image.LANCZOS)
    pad_top = max(0, nh-(neck-top)-top)
    cx = (x0+x1)//2
    pad_l = max(0, nw//2-cx); pad_r = max(0, cx+nw-nw//2-v.width)
    res = Image.new('RGBA', (v.width+pad_l+pad_r, v.height+pad_top))
    res.alpha_composite(v, (pad_l, pad_top))
    res.alpha_composite(big, (pad_l+cx-nw//2, pad_top+neck-nh))
    return res

def strip(views, height, cell, anim, n):
    def body_h(v):
        k = max(3, v.height//30) | 1
        b = v.getchannel('A').point(lambda p: 255 if p else 0).filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k)).getbbox()
        return (v.height-b[1]) if b else v.height
    hs = sorted(body_h(v) for v in views)
    ref = (hs[1]+hs[2])/2 if anim == 'attack' else hs[-1]
    scale = height/ref
    res = Image.new('RGBA', (cell[0]*4, cell[1]))
    for i, v in enumerate(views):
        s = gen.keep_main(gen.to_sprite(v, max(1, round(v.height*scale)), 24))
        if s.width > cell[0] or s.height+4 > cell[1]:
            print('  OVERFLOW', n, i, s.size); s = s.crop((max(0,(s.width-cell[0])//2), max(0,s.height+4-cell[1]), (s.width+cell[0])//2 if s.width>cell[0] else s.width, s.height))
        res.alpha_composite(s, (i*cell[0]+(cell[0]-s.width)//2, cell[1]-4-s.height))
    return res


def main(only: list[str]) -> None:
    for f in sorted(glob.glob(os.path.join(a1,'*.png'))) + sorted(glob.glob(os.path.join(a3,'*.png'))):
        n = os.path.basename(f)[:-4]; who, anim, view = n.rsplit('_',2)
        if only and who not in only: continue
        src = os.path.join(a2, n+'.png') if n in V2 else f
        im = Image.open(src).convert('RGB')
        im = flood_bg(im.resize((im.width//2, im.height//2), Image.LANCZOS), THR_BY.get(who, THR))
        if who == 'spirit': im = gen.mask_bg(im)
        row,_ = pick_row(im); views,_ = split4(row)
        if n == 'agata_walk_side':  # в листе смотрит влево, базовый вид — вправо
            views = [v.transpose(Image.FLIP_LEFT_RIGHT) for v in views]
        if who in HEAD and anim == 'walk':
            views = [enlarge(v, HEAD[who][view], TARGET_BY.get(who, TARGET)) for v in views]
        cell = (64,64) if anim == 'walk' else ATTACK_CELL
        strip(views, HEIGHT[who], cell, anim, n).save(os.path.join(out, n+'.png'))
    print('ok')


if __name__ == "__main__":
    main(sys.argv[1:])
