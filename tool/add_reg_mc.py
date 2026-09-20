#!/usr/bin/env python3
"""Regulation Set M-C (2026-09-14): add the 27 new Champions grid entries
(24 Pokemon, forms listed separately the way the game lists them) and the
six new Mega Evolutions to the data pack, with real stats/types/abilities/
learnsets from the PokeAPI dump - same recipe as add_form_species.py /
full_roster.py so the entries are indistinguishable from the rest.

    python3 tool/add_reg_mc.py

Species are inserted in National Dex order (each after its anchor), which
keeps the pack in the same order as `pokemon2Dsprites/manifest.json` - the
atlas builder and the sprite splitter both rely on that. Rillaboom and
Salamence were removed from the July scaffold as "not in Champions"; they
are back now, for real.

Megas: Mega Salamence (classic), Mega Golisopod, Mega Baxcalibur, and the
three "Z" Megas (Mega Absol Z, Mega Garchomp Z, Mega Lucario Z) which sit
next to the classic forms on their species. PokeAPI carries all six with
stats. Mega Stones are added to items.json.

Then: python3 tool/split_photo_sheets.py (sprites, already done) and
python3 tool/build_champions_atlas.py; bump the counts in
test/champions_atlas_test.dart; dart run tool/update_data.dart.
"""
import json, os, sys, io, urllib.request, concurrent.futures as cf
from PIL import Image

RAW = "https://raw.githubusercontent.com/PokeAPI/api-data/master/data/api/v2"
SPR = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = "2026-09-14"

NEW = {  # slug -> (display name, insert after this pack id)   [dex order]
    "wigglytuff": ("Wigglytuff", "ninetales-alola"),
    "persian": ("Persian", "vileplume"),
    "persian-alola": ("Alolan Persian", "persian"),
    "farfetchd": ("Farfetch'd", "slowbro-galar"),
    "mr-mime": ("Mr. Mime", "starmie"),
    "swalot": ("Swalot", "manectric"),
    "salamence": ("Salamence", "glalie"),
    "gogoat": ("Gogoat", "florges"),
    "golisopod": ("Golisopod", "passimian"),
    "rillaboom": ("Rillaboom", "kommo-o"),
    "cinderace": ("Cinderace", "rillaboom"),
    "inteleon": ("Inteleon", "cinderace"),
    "thievul": ("Thievul", "corviknight"),
    "toxtricity-amped": ("Toxtricity (Amped)", "sandaconda"),
    "toxtricity-low-key": ("Toxtricity (Low Key)", "toxtricity-amped"),
    "grapploct": ("Grapploct", "toxtricity-low-key"),
    "perrserker": ("Perrserker", "grimmsnarl"),
    "sirfetchd": ("Sirfetch'd", "perrserker"),
    "pincurchin": ("Pincurchin", "falinks"),
    "indeedee-male": ("Indeedee (Male)", "pincurchin"),
    "indeedee-female": ("Indeedee (Female)", "indeedee-male"),
    "pawmot": ("Pawmot", "quaquaval"),
    "arboliva": ("Arboliva", "maushold-family-of-four"),
    "squawkabilly-green-plumage": ("Squawkabilly (Green Plumage)", "arboliva"),
    "squawkabilly-yellow-plumage": ("Squawkabilly (Yellow Plumage)", "squawkabilly-green-plumage"),
    "mabosstiff": ("Mabosstiff", "bellibolt"),
    "baxcalibur": ("Baxcalibur", "kingambit"),
}
MEGAS = [  # (species id, PokeAPI mega slug, display name, item id, item name)
    ("salamence", "salamence-mega", "Mega Salamence", "salamencite", "Salamencite"),
    ("golisopod", "golisopod-mega", "Mega Golisopod", "golisopodite", "Golisopodite"),
    ("baxcalibur", "baxcalibur-mega", "Mega Baxcalibur", "baxcaliburite", "Baxcaliburite"),
    ("absol", "absol-mega-z", "Mega Absol Z", "absolite-z", "Absolite Z"),
    ("garchomp", "garchomp-mega-z", "Mega Garchomp Z", "garchompite-z", "Garchompite Z"),
    ("lucario", "lucario-mega-z", "Mega Lucario Z", "lucarionite-z", "Lucarionite Z"),
]

def fetch(url, binary=False, tries=3):
    for t in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "psa/2.2"})
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
missing = [s for s in list(NEW) + [m[1] for m in MEGAS] if s not in POKE]
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

print("species + mega data...")
pdata = fetch_many({s: f"{RAW}/pokemon/{POKE[s]}/index.json"
                    for s in list(NEW) + [m[1] for m in MEGAS]}, "pokemon")
if len(pdata) != len(NEW) + len(MEGAS):
    sys.exit("some fetches failed; aborting without writing")

pokedex = load("pokedex.json")
species = pokedex["species"]
by_id = {s["id"]: s for s in species}
dup = [s for s in NEW if s in by_id]
if dup:
    sys.exit(f"already in the pack: {dup} (script is not idempotent; restore assets/data first)")

# ---- build the new species entries
built = {}
for slug, (name, _) in NEW.items():
    p = pdata[slug]
    built[slug] = {
        "id": slug, "name": name,
        "types": build_types(p), "baseStats": build_stats(p),
        "abilities": build_abilities(p), "learnset": learnset(p),
        "megas": [],
    }
    print(f"  {slug:28s} {built[slug]['types']} {built[slug]['baseStats']} "
          f"{built[slug]['abilities']} moves={len(built[slug]['learnset'])}")

# ---- megas onto their species (new or existing)
all_by_id = {**by_id, **built}
for sid, mslug, mname, item_id, item_name in MEGAS:
    p = pdata[mslug]
    entry = {"id": mslug, "name": mname, "types": build_types(p), "baseStats": build_stats(p),
             "ability": build_abilities(p)[0], "item": item_id}
    host = all_by_id[sid]
    if any(m["id"] == mslug for m in host["megas"]):
        continue
    host["megas"].append(entry)
    print(f"  {mname:18s} on {sid}: {entry['types']} {entry['baseStats']} {entry['ability']}")

# ---- insert in place, each after its anchor
order = [s["id"] for s in species]
for slug, (_, after) in NEW.items():
    order.insert(order.index(after) + 1, slug)
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

# ---- abilities.json (species abilities + mega abilities)
abildoc = load("abilities.json")
have_ab = {a["name"] for a in abildoc["abilities"]}
need_ab = sorted(({a for e in built.values() for a in e["abilities"]} |
                  {m["ability"] for s in pokedex["species"] for m in s["megas"]}) - have_ab)
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

# ---- items.json: the six Mega Stones
itemsdoc = load("items.json")
have_items = {i["id"] for i in itemsdoc["items"]}
for sid, mslug, mname, item_id, item_name in MEGAS:
    if item_id in have_items:
        continue
    host = all_by_id[sid]["name"]
    itemsdoc["items"].append({"id": item_id, "name": item_name,
                              "desc": f"Mega Stone: {host} -> {mname} (Pokemon Champions, Reg M-C)"})
itemsdoc["items"].sort(key=lambda i: i["id"])

# ---- HOME sprites for the new ids (UI thumbnails; recognition uses the atlas)
home = f"{APP}/assets/sprites/home"
os.makedirs(home, exist_ok=True)
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

# ---- validate what tool/update_data.dart validates (home sprites: new ids
#      only - this may run in a checkout without the old ones)
usage = load("usage_reg_mb.json")
abil_names = {a["name"] for a in abildoc["abilities"]}
item_ids = {i["id"] for i in itemsdoc["items"]}
errs = []
ids = [s["id"] for s in pokedex["species"]]
if len(ids) != len(set(ids)):
    errs.append("duplicate species ids")
for s in pokedex["species"]:
    if not s["learnset"]: errs.append(f"{s['id']}: empty learnset")
    for a in s["abilities"]:
        if a not in abil_names: errs.append(f"{s['id']}: ability {a} missing")
    for m in s["megas"]:
        if m["ability"] not in abil_names: errs.append(f"{m['id']}: ability {m['ability']} missing")
        if m["item"] not in item_ids: errs.append(f"{m['id']}: item {m['item']} missing")
    if s["id"] in NEW and not os.path.exists(f"{home}/{s['id']}.png"):
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
    " 2026-09-14 (Regulation M-C): +27 grid entries (24 Pokemon; Toxtricity, Indeedee and "
    "Squawkabilly forms listed separately like the game does - the grid shows only Green and "
    "Yellow Squawkabilly) and 6 Megas (Salamence, Golisopod, Baxcalibur, Absol Z, Garchomp Z, "
    "Lucario Z), all real PokeAPI stats.")
movesdoc["generatedAt"] = GEN
abildoc["generatedAt"] = GEN
itemsdoc["generatedAt"] = GEN
save("pokedex.json", pokedex); save("moves.json", movesdoc)
save("abilities.json", abildoc); save("items.json", itemsdoc)
print(f"\nOK: {len(pokedex['species'])} species, "
      f"{sum(len(s['megas']) for s in pokedex['species'])} megas, "
      f"{len(movesdoc['moves'])} moves, {len(abildoc['abilities'])} abilities, "
      f"{len(itemsdoc['items'])} items")
