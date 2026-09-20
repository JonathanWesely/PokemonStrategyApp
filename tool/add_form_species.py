#!/usr/bin/env python3
"""Promote the 12 Champions form variants the data pack collapsed into full
species entries, with real stats/types/abilities/learnsets from PokeAPI —
same recipe as full_roster.py so the entries are indistinguishable from the
rest of the pack.

  rotom-heat/-wash/-frost/-fan/-mow      (were folded into rotom)
  meowstic-female                        (into meowstic-male)
  gourgeist-small/-large/-super          (into gourgeist-average)
  lycanroc-midnight/-dusk                (into lycanroc, which was Midday's
                                          stats under a generic id and is
                                          renamed lycanroc-midday here)
  basculegion-female                     (into basculegion-male)

Also: HOME sprites for the new ids, moves/abilities docs extended, the
Lycanroc usage placeholder moved onto Dusk (Accelerock + Tough Claws is the
Dusk set, and the fixture photo's exemplar IS a Dusk).
"""
import json, os, re, sys, io, urllib.request, concurrent.futures as cf
from PIL import Image

RAW = "https://raw.githubusercontent.com/PokeAPI/api-data/master/data/api/v2"
SPR = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = "2026-09-06"

NEW = {  # slug -> (display name, insert after this pack id)
    "rotom-heat": ("Heat Rotom", "rotom"),
    "rotom-wash": ("Wash Rotom", "rotom-heat"),
    "rotom-frost": ("Frost Rotom", "rotom-wash"),
    "rotom-fan": ("Fan Rotom", "rotom-frost"),
    "rotom-mow": ("Mow Rotom", "rotom-fan"),
    "meowstic-female": ("Meowstic (Female)", "meowstic-male"),
    "gourgeist-small": ("Gourgeist (Small)", "gourgeist-average"),
    "gourgeist-large": ("Gourgeist (Large)", "gourgeist-small"),
    "gourgeist-super": ("Gourgeist (Super)", "gourgeist-large"),
    "lycanroc-midnight": ("Lycanroc (Midnight)", "lycanroc-midday"),
    "lycanroc-dusk": ("Lycanroc (Dusk)", "lycanroc-midnight"),
    "basculegion-female": ("Basculegion (Female)", "basculegion-male"),
}
RENAME = {"lycanroc": "lycanroc-midday"}
RENAME_DISPLAY = {
    "lycanroc-midday": "Lycanroc (Midday)",
    "meowstic-male": "Meowstic (Male)",
    "gourgeist-average": "Gourgeist (Average)",
    "basculegion-male": "Basculegion (Male)",
}

def fetch(url, binary=False, tries=3):
    for t in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "psa/2.1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            return data if binary else json.loads(data)
        except Exception:
            if t == tries - 1:
                raise
def try_fetch(url, binary=False):
    try:
        return fetch(url, binary)
    except Exception:
        return None
def fetch_many(urls, label=""):
    out = {}
    with cf.ThreadPoolExecutor(8) as ex:
        futs = {ex.submit(fetch, u): k for k, u in urls.items()}
        for f in cf.as_completed(futs):
            k = futs[f]
            try:
                out[k] = f.result()
            except Exception as e:
                print(f"  !! fetch failed {label}:{k}: {e}")
    return out
def load(p): return json.load(open(f"{APP}/assets/data/{p}"))
def save(p, d):
    with open(f"{APP}/assets/data/{p}", "w") as f:
        json.dump(d, f, indent=1)
        f.write("\n")

print("indexes...")
idx = fetch_many({
    "pokemon": f"{RAW}/pokemon/index.json",
    "move": f"{RAW}/move/index.json",
    "ability": f"{RAW}/ability/index.json",
    "vg": f"{RAW}/version-group/index.json",
}, "idx")
def id_map(kind):
    return {r["name"]: int(r["url"].rstrip("/").split("/")[-1])
            for r in idx[kind]["results"]}
POKE, MOVE, ABIL = id_map("pokemon"), id_map("move"), id_map("ability")
VG_RANK = {r["name"]: int(r["url"].rstrip("/").split("/")[-1])
           for r in idx["vg"]["results"]}
missing = [s for s in NEW if s not in POKE]
if missing:
    sys.exit(f"unknown PokeAPI slugs: {missing}")

STAT = {"hp": "hp", "attack": "atk", "defense": "def",
        "special-attack": "spa", "special-defense": "spd", "speed": "spe"}
_MINOR = {"as", "of", "the", "to", "a", "an"}
def title(slug): return " ".join(w.capitalize() for w in slug.split("-"))
def ability_title(slug):
    words = slug.split("-")
    return " ".join(w.capitalize() if i == 0 or w not in _MINOR else w
                    for i, w in enumerate(words))
def build_stats(p): return {STAT[s["stat"]["name"]]: s["base_stat"] for s in p["stats"]}
def build_types(p):
    return [t["type"]["name"].capitalize()
            for t in sorted(p["types"], key=lambda t: t["slot"])]
def build_abilities(p):
    seen, out = set(), []
    for a in sorted(p["abilities"], key=lambda a: a["slot"]):
        nm = ability_title(a["ability"]["name"])
        if nm not in seen:
            out.append(nm); seen.add(nm)
    return out
def learnset(p):
    best = {}
    for mv in p["moves"]:
        for d in mv["version_group_details"]:
            r = VG_RANK.get(d["version_group"]["name"], 0)
            best[mv["move"]["name"]] = max(best.get(mv["move"]["name"], 0), r)
    if not best:
        return []
    newest = max(best.values())
    ls = sorted(m for m, r in best.items() if r == newest)
    return ls if len(ls) >= 8 else sorted(best)

print("species data...")
pdata = fetch_many({s: f"{RAW}/pokemon/{POKE[s]}/index.json" for s in NEW}, "pokemon")
if len(pdata) != len(NEW):
    sys.exit("some species fetches failed; aborting without writing")

pokedex = load("pokedex.json")
species = pokedex["species"]
by_id = {s["id"]: s for s in species}

# ---- rename lycanroc -> lycanroc-midday (it always was Midday's data)
for old, new in RENAME.items():
    e = by_id.pop(old)
    e["id"] = new
    by_id[new] = e
for sid, nm in RENAME_DISPLAY.items():
    by_id[sid]["name"] = nm

# ---- build the new entries
usage = load("usage_reg_mb.json")
built = {}
for slug, (name, _) in NEW.items():
    p = pdata[slug]
    built[slug] = {
        "id": slug, "name": name,
        "types": build_types(p), "baseStats": build_stats(p),
        "abilities": build_abilities(p), "learnset": learnset(p),
        "megas": [],
    }
    print(f"  {slug:20s} {built[slug]['types']} {built[slug]['baseStats']} "
          f"{built[slug]['abilities']} moves={len(built[slug]['learnset'])}")

# ---- usage placeholder: Lycanroc's set is Dusk's (Accelerock / Tough Claws)
for u in usage["pokemon"]:
    if u["speciesId"] == "lycanroc":
        u["speciesId"] = "lycanroc-dusk"
        u["abilities"] = [{"name": "Tough Claws", "pct": 100}]
    for t in u.get("teammates", []):
        if t["speciesId"] == "lycanroc":
            t["speciesId"] = "lycanroc-dusk"
# Champions-confirmed usage moves must be learnable (same rule as the importer)
for u in usage["pokemon"]:
    tgt = built.get(u["speciesId"]) or by_id.get(u["speciesId"])
    if tgt is None:
        continue
    for m in u.get("moves", []):
        if m["id"] not in tgt["learnset"]:
            tgt["learnset"].append(m["id"])

# ---- insert in place, each after its anchor
order = [s["id"] for s in species]
order = [RENAME.get(i, i) for i in order]
for slug, (_, after) in NEW.items():
    order.insert(order.index(after) + 1, slug)
all_by_id = {**by_id, **built}
pokedex["species"] = [all_by_id[i] for i in order]
assert len(pokedex["species"]) == len(species) + len(NEW), "count mismatch"

# ---- moves.json: fetch anything the new learnsets reference that we lack
movesdoc = load("moves.json")
have_moves = {m["id"]: m for m in movesdoc["moves"]}
need = sorted({m for e in built.values() for m in e["learnset"]} - set(have_moves))
need = [m for m in need if m in MOVE]
print(f"new moves to fetch: {len(need)} {need}")
mv = fetch_many({m: f"{RAW}/move/{MOVE[m]}/index.json" for m in need}, "moves")
def move_desc(mj):
    for e in mj.get("effect_entries", []):
        if e["language"]["name"] == "en":
            d = e.get("short_effect") or e.get("effect") or ""
            return d.replace("$effect_chance", str(mj.get("effect_chance") or "")).strip()
    for fl in reversed(mj.get("flavor_text_entries", [])):
        if fl["language"]["name"] == "en":
            return " ".join(fl["flavor_text"].split())
    return ""
for mid in need:
    mj = mv.get(mid)
    if mj is None or mj["damage_class"] is None:
        continue
    movesdoc["moves"].append({
        "id": mid, "name": title(mid), "type": mj["type"]["name"].capitalize(),
        "category": {"physical": "Physical", "special": "Special",
                     "status": "Status"}[mj["damage_class"]["name"]],
        "power": mj["power"], "accuracy": mj["accuracy"],
        "priority": mj["priority"], "note": "", "desc": move_desc(mj),
    })
movesdoc["moves"].sort(key=lambda m: m["id"])
ok_moves = {m["id"] for m in movesdoc["moves"]}
for e in pokedex["species"]:
    e["learnset"] = [m for m in e["learnset"] if m in ok_moves]

# ---- abilities.json
abildoc = load("abilities.json")
have_ab = {a["name"] for a in abildoc["abilities"]}
need_ab = sorted({a for e in built.values() for a in e["abilities"]} - have_ab)
print(f"new abilities: {need_ab}")
slug_of = {a: a.lower().replace(" ", "-").replace("'", "") for a in need_ab}
ad = fetch_many({a: f"{RAW}/ability/{ABIL[s]}/index.json"
                 for a, s in slug_of.items() if s in ABIL}, "abilities")
def abil_desc(aj):
    for e in aj.get("effect_entries", []):
        if e["language"]["name"] == "en":
            return (e.get("short_effect") or e.get("effect") or "").strip()
    for fl in reversed(aj.get("flavor_text_entries", [])):
        if fl["language"]["name"] == "en":
            return " ".join(fl["flavor_text"].split())
    return ""
for a in need_ab:
    abildoc["abilities"].append({"id": slug_of[a], "name": a,
                                 "desc": abil_desc(ad[a]) if a in ad else ""})
abildoc["abilities"].sort(key=lambda x: x["id"])

# ---- HOME sprites for the new ids (UI thumbnails; recognition uses the atlas)
home = f"{APP}/assets/sprites/home"
if not os.path.exists(f"{home}/lycanroc-midday.png"):
    Image.open(f"{home}/lycanroc.png").save(f"{home}/lycanroc-midday.png")
def get_sprite(slug):
    pid = POKE[slug]
    for url in (f"{SPR}/other/home/{pid}.png", f"{SPR}/{pid}.png"):
        data = try_fetch(url, binary=True)
        if data:
            return slug, data
    return slug, None
sprite_missing = []
with cf.ThreadPoolExecutor(6) as ex:
    for slug, data in ex.map(get_sprite, list(NEW)):
        if data is None:
            sprite_missing.append(slug); continue
        im = Image.open(io.BytesIO(data)).convert("RGBA")
        im.thumbnail((96, 96), Image.LANCZOS)
        im.save(f"{home}/{slug}.png")
print("sprites missing:", sprite_missing)

# ---- validate exactly what tool/update_data.dart validates
abil_names = {a["name"] for a in abildoc["abilities"]}
errs = []
ids = [s["id"] for s in pokedex["species"]]
if len(ids) != len(set(ids)):
    errs.append("duplicate species ids")
for s in pokedex["species"]:
    if not s["learnset"]: errs.append(f"{s['id']}: empty learnset")
    for a in s["abilities"]:
        if a not in abil_names: errs.append(f"{s['id']}: ability {a} missing")
    if not os.path.exists(f"{home}/{s['id']}.png"):
        errs.append(f"{s['id']}: home sprite missing")
sids = set(ids)
for u in usage["pokemon"]:
    if u["speciesId"] not in sids:
        errs.append(f"usage: unknown species {u['speciesId']}"); continue
    sp = all_by_id[u["speciesId"]]
    for m in u.get("moves", []):
        if m["id"] not in sp["learnset"]:
            errs.append(f"usage {u['speciesId']}: move {m['id']} not learnable")
    for a in u.get("abilities", []):
        if a["name"] not in sp["abilities"]:
            errs.append(f"usage {u['speciesId']}: ability {a['name']} unknown")
    for t in u.get("teammates", []):
        if t["speciesId"] not in sids:
            errs.append(f"usage {u['speciesId']}: teammate {t['speciesId']} unknown")
if errs:
    print("VALIDATION ERRORS:"); [print("  -", e) for e in errs]
    sys.exit(1)

pokedex["generatedAt"] = GEN
pokedex["note"] = (pokedex.get("note", "") +
    " 2026-09-06: the 12 form variants Champions lists separately (appliance "
    "Rotoms, Gourgeist sizes, Lycanroc forms, Meowstic/Basculegion females) "
    "are full species entries with their own stats and learnsets.")
movesdoc["generatedAt"] = GEN
abildoc["generatedAt"] = GEN
save("pokedex.json", pokedex); save("moves.json", movesdoc)
save("abilities.json", abildoc); save("usage_reg_mb.json", usage)
print(f"\nOK: {len(pokedex['species'])} species, {len(movesdoc['moves'])} moves, "
      f"{len(abildoc['abilities'])} abilities")
