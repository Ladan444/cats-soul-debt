# -*- coding: utf-8 -*-
"""Собирает игровые тексты в Литература/Тексты/strings_ru.csv (ключ, текст, где используется, контекст). Код не меняет."""
import os, re, csv, glob, sys
PROJ = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
G = os.path.join(PROJ, "Game", "CatsSoulDebt")
OUT = os.path.join(PROJ, "Литература", "Тексты")
os.makedirs(OUT, exist_ok=True)
CYR = re.compile(r"[А-Яа-яЁё]")
rows = []   # key, text, where, context
keys = set()

def add(key, text, where, ctx=""):
    if not CYR.search(text):
        return
    k = key; n = 2
    while k in keys:
        k = "%s~%d" % (key, n); n += 1
    keys.add(k)
    rows.append((k, text, where, ctx))

def strip_comments(src):
    out = []; i = 0; instr = False; esc = False
    while i < len(src):
        c = src[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True; out.append(c)
            elif c == "#":
                while i < len(src) and src[i] != "\n": i += 1
                continue
            else: out.append(c)
        i += 1
    return "".join(out)

class V2:
    def __init__(self, *a): pass

def walk(obj, path, prefix, where, ctx_of=None):
    if isinstance(obj, str):
        add(".".join([prefix] + path), obj, where)
    elif isinstance(obj, dict):
        for k, v in obj.items():
            walk(v, path + [str(k)], prefix, where)
    elif isinstance(obj, (list, tuple)):
        for i, v in enumerate(obj, 1):
            walk(v, path + [str(i)], prefix, where)

def const_block(src, name):
    m = re.search(r"^const %s\s*(?::=|=)\s*" % name, src, re.M)
    if not m: return None
    start = m.end(); depth = 0; instr = False; esc = False; i = start
    while i < len(src):
        c = src[i]
        if instr:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c in "[{(": depth += 1
            elif c in "]})":
                depth -= 1
                if depth == 0: return src[start:i + 1]
            elif c == "\n" and depth == 0: return src[start:i]
        i += 1
    return src[start:]

def gd_eval(block):
    b = strip_comments(block)
    b = re.sub(r'&"', '"', b)
    b = re.sub(r"\btrue\b", "True", b); b = re.sub(r"\bfalse\b", "False", b); b = re.sub(r"\bnull\b", "None", b)
    b = re.sub(r"\bVector2\(", "V2(", b)
    return eval(b, {"V2": V2})

# ---------- 1. village_quests.gd ----------
vq = open(os.path.join(G, "scripts/data/village_quests.gd"), encoding="utf-8").read()
VQ = "scripts/data/village_quests.gd"
for const, prefix in [("VILLAGERS", "npc"), ("SHOPS", "shop"), ("GUIDE", "guide"), ("SPIRIT", "spirit"),
                      ("MIKA", "npc.mika"), ("LIARA_MEMORIES", "liara_house.memory"), ("QUESTS", "quest")]:
    blk = const_block(vq, const)
    if blk is None:
        print("нет", const); continue
    obj = gd_eval(blk)
    walk(obj, [], prefix, "%s (%s)" % (VQ, const))

# ---------- 2. quest_state.gd (сюжетные задания) ----------
qs = open(os.path.join(G, "scripts/core/quest_state.gd"), encoding="utf-8").read()
obj = gd_eval(const_block(qs, "QUESTS"))
walk(obj, [], "quest", "scripts/core/quest_state.gd (QUESTS)")

# ---------- 3. данные .tres ----------
def tres(path):
    return open(path, encoding="utf-8").read()
def unq(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
DIRS = [("items", "item", ["name", "description"]), ("souls", "soul", ["name", "company", "memory"]),
        ("skills", "skill", ["name", "description"]), ("journal", "journal", ["title", "text"])]
for d, pre, fields in DIRS:
    for p in sorted(glob.glob(os.path.join(G, "data", d, "*.tres"))):
        t = tres(p)
        m = re.search(r'^id = &"([^"]+)"', t, re.M)
        if not m: continue
        id_ = m.group(1)
        for f in fields:
            mm = re.search(r'^%s = "((?:[^"\\]|\\.)*)"' % f, t, re.M | re.S)
            if mm:
                add("%s.%s.%s" % (pre, id_, f), unq(mm.group(1)), "data/%s/%s" % (d, os.path.basename(p)))
# карты журнала
for p in sorted(glob.glob(os.path.join(G, "data/maps/*.tres"))):
    t = tres(p)
    m = re.search(r'^id = &"([^"]+)"', t, re.M)
    mid = m.group(1)
    tt = re.search(r'^title = "((?:[^"\\]|\\.)*)"', t, re.M)
    if tt: add("map.%s.title" % mid, unq(tt.group(1)), "data/maps/" + os.path.basename(p))
    cur = None
    for line in t.splitlines():
        mi = re.match(r'^"id": "([^"]+)"', line)
        if mi: cur = mi.group(1)
        mf = re.match(r'^"(name|note|hint_note)": "((?:[^"\\]|\\.)*)"', line)
        if mf and cur:
            add("map.%s.room.%s.%s" % (mid, cur, mf.group(1)), unq(mf.group(2)), "data/maps/" + os.path.basename(p))
# реплики Стража
for p in sorted(glob.glob(os.path.join(G, "data/crossroads/*.tres"))):
    t = tres(p)
    ch = re.search(r"^chapter = (\d+)", t, re.M).group(1)
    arr = re.search(r"conversations = .*?\(\[(.*)\]\)", t, re.S).group(1)
    for ci, grp in enumerate(re.findall(r"PackedStringArray\((.*?)\)(?:,\s*|$)", arr, re.S), 1):
        for li, s in enumerate(re.findall(r'"((?:[^"\\]|\\.)*)"', grp), 1):
            add("guardian.ch%s.c%d.%d" % (ch, ci, li), unq(s), "data/crossroads/" + os.path.basename(p))

# ---------- 4. строки скриптов сюжета (по порядку в файле) ----------
SCRIPTS = [("scripts/levels/velmor_npc.gd", "velmor"), ("scripts/levels/chapter1_finale.gd", "finale"),
           ("scripts/levels/spirit_npc.gd", "spirit_npc"), ("scripts/levels/villager_npc.gd", "villager_npc"),
           ("scripts/levels/story_pickup.gd", "pickup"), ("scripts/levels/quest_prop.gd", "quest_prop"),
           ("scripts/levels/village_quests_runtime.gd", "village_runtime"), ("scripts/levels/liara_house.gd", "liara_house"),
           ("scripts/levels/level_door.gd", "door"), ("scripts/levels/chest.gd", "chest"),
           ("scripts/levels/key_pickup.gd", "key_pickup"), ("scripts/levels/crossroads.gd", "crossroads"),
           ("scripts/levels/npc.gd", "npc_base"), ("scripts/levels/tavern_level.gd", "tavern"),
           ("scripts/combat/soul_lantern.gd", "lantern")]
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
for rel, pre in SCRIPTS:
    path = os.path.join(G, rel)
    if not os.path.exists(path): continue
    n = 0
    for ln, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
        code = strip_comments(line)
        if code.lstrip().startswith("##") or re.search(r"(push_warning|push_error|print|assert|printerr)\(", code): continue
        for s in LIT.findall(code):
            if CYR.search(s) and not s.startswith("res://"):
                n += 1
                add("script.%s.%03d" % (pre, n), unq(s), "%s:%d" % (rel, ln), "строка в коде — перенос в таблицу без правки кода")

with open(os.path.join(OUT, "strings_ru.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["key", "ru", "where", "context"])
    for r in rows: w.writerow(r)
from collections import Counter
c = Counter(r[0].split(".")[0] for r in rows)
print(len(rows), "строк"); print(dict(c))
