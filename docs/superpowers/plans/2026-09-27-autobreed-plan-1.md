# autoBreed Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working `autoBreed` program. It plants the best seed bags from a seed chest, grinds crossbreeding, swaps in better parents, and captures a chosen target crop (first target: Bauxia).

**Architecture:** A Python generator in the advisor project turns the GTNH wiki crop list into `crops.lua`. On the robot:

- `breeding.lua`: pure Lua; IC2's weight formula, ranking, and name lookup.
- `breedpolicy.lua`: pure Lua; per-slot decision rules.
- `autoBreed.lua`: the program; wires the two together through `action.lua`, which gains seed-chest, planting and storage-safe helpers.

The pure modules are unit-tested on the PC through `lupa`. The robot-movement code is covered by tests against small OpenComputers stand-ins, plus an in-game checklist.

**Tech Stack:** Lua 5.3 (OpenComputers/OpenOS), Python 3.14 + `unittest`, `lupa` (Lua inside Python tests), GTNH wiki MediaWiki API.

**Spec:** `docs/superpowers/specs/2026-09-27-autobreed-design.md`

**Revision 2026-09-29:** the first execution also changed the Resistance caps and autoStat/autoSpread thresholds (Re 6 / 46 / 44), carried over from an earlier, unrelated discussion. The user asked for them removed. `config.lua` keeps the upstream defaults, and this plan now reflects that.

**Plan 2 (separate, later):** read IC2's five hidden crop properties from the pack's jars with a small `javap`-based interpreter, run the per-crop `canGrow` check (spec §5.1), and verify the names, tiers and attributes against the wiki. Then regenerate `crops.lua`. No robot code changes are needed; this plan writes a table with no properties (`s=` absent), which the spec allows, and the robot reports that the odds are estimates.

---

## Paths

- **ADV** = `C:\Users\loope\Desktop\GTNH 2.8.4 Agent` — the advisor project. Not a git repo, so nothing is committed there.
- **BOT** = `C:\Users\loope\Desktop\GTNH 2.8.4 Agent\CropBot\GTNH-CropAutomation` — the bot clone on branch `autobreed`. Commit here.
- Fork: `https://github.com/Keegater/GTNH-CropAutomation`

Commit messages end with the trailer:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

## Deviations from the spec (all small, all intentional)

1. `isWeedLike` lives in `breedpolicy.lua` (pure, testable), not `scanner.lua` (which needs OC components at load).
2. The bad-parent rule is a module setting: `action.setBadParentRule(fn)`, reset by `initWork()`. It is not a `cleanUp` argument, because `charge()` also triggers `cleanUp()` when you press C.
3. `breeding.lua` API: `load([data])`, `unload()`, `propertiesKnown()`, `ratio(x, p)`, `resolve(text)`, `prepare(target)`, `labelToKey(label)`, `chance(keys)`, `top(count)`. `prepare()` builds a compact info map that survives `unload()`, so the full table can be freed.
4. The child table gains a row for an empty cross stick → `'none'` (the existing programs also leave those alone).
5. `action.readSeedChest()` returns labels only. `autoBreed` maps labels to crops.
6. Seed bags of the target itself are ignored, not planted.
7. `crops.lua` stores attributes and properties as comma-joined strings (`a='Metal,Reed'`, `s='5,0,2,3,3'`), not nested tables, to save robot memory.

## File map

| File | Responsibility |
|---|---|
| ADV `scripts/build_crop_table.py` | wiki → crop records → `crops.lua` (weight formula + total weights) |
| ADV `tests/test_build_crop_table.py` | generator unit tests |
| BOT `crops.lua` | generated crop table (commit it) |
| BOT `breeding.lua` | crop math, ranking, name/label lookup (pure Lua) |
| BOT `breedpolicy.lua` | `isWeedLike`, `parentAction`, `childAction` (pure Lua) |
| BOT `autoBreed.lua` | the program |
| BOT `action.lua` | + dumpInventory fix, storage-safe moves, seed chest, planting, bad-parent rule |
| BOT `autoTier.lua`, `autoStat.lua`, `autoSpread.lua` | storage moves use `transplantToStorage` |
| BOT `config.lua` | + `breedTarget`, `seedContainerPos` |
| BOT `setup.lua`, `uninstall.lua`, `README.md` | install list, fork URL, docs |
| BOT `tests/lua_env.py`, `tests/oc_stubs.lua` | Lua runtime + OpenComputers stand-ins for tests |
| BOT `tests/test_*.py` | Lua module tests |

---

### Task 1: Test tooling (`lupa`)

**Files:**
- Create: BOT `tests/lua_env.py`
- Create: BOT `tests/oc_stubs.lua`

- [ ] **Step 1: Ask the user before installing.** Installing `lupa` downloads a package from PyPI. Ask in chat: "OK to run `python -m pip install lupa`?" Wait for a yes.

- [ ] **Step 2: Install and verify**

Run: `python -m pip install lupa`

Then run: `python -c "import lupa.lua53 as l; print(l.LuaRuntime().eval('_VERSION'))"`

Expected: `Lua 5.3`. If only `lupa.lua54` imports, that is acceptable (the helper falls back to it). If pip cannot find a wheel for Python 3.14 and tries to compile, stop and tell the user.

- [ ] **Step 3: Create `tests/lua_env.py`**

```python
"""Run the bot's Lua files inside Python tests (lupa; Lua 5.3 like OpenComputers)."""
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def runtime(stubs=False):
    """A fresh Lua runtime that can require() the bot's files.

    stubs=True also loads tests/oc_stubs.lua, so files that need OpenComputers
    components (action.lua, autoBreed.lua) can load.
    """
    impl = None
    for name in ("lua53", "lua54"):
        try:
            impl = __import__("lupa." + name, fromlist=["LuaRuntime"])
            break
        except ImportError:
            continue
    if impl is None:
        raise RuntimeError("lupa with Lua 5.3 or 5.4 is required: python -m pip install lupa")
    lua = impl.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = '%s/?.lua;' .. package.path" % REPO.as_posix())
    if stubs:
        lua.execute((REPO / "tests" / "oc_stubs.lua").read_text(encoding="utf-8"))
    return lua
```

- [ ] **Step 4: Create `tests/oc_stubs.lua`**

```lua
-- Minimal OpenComputers stand-ins so action.lua and autoBreed.lua can run in
-- tests. The global `stub` lets a test set the seed chest and scan results.
stub = {
    chest = {},       -- chest slot -> {label=, size=}
    chestSize = 27,   -- getInventorySize() result; nil means "no inventory"
    scans = {},       -- queue of geolyzer.analyze() results; empty queue = air
    inventory = {},   -- robot slot -> item count
}

os.sleep = function() end

package.preload['sides'] = function()
    return {bottom=0, top=1, back=2, front=3, right=4, left=5, down=0, up=1}
end

package.preload['computer'] = function()
    return {
        energy = function() return 1000 end,
        maxEnergy = function() return 1000 end,
        freeMemory = function() return 200 * 1024 end,
        beep = function() end,
    }
end

package.preload['event'] = function()
    return {listen = function() end, ignore = function() end}
end

package.preload['robot'] = function()
    local selected = 1
    return {
        forward = function() return true end,
        turnLeft = function() return true end,
        turnRight = function() return true end,
        up = function() return true end,
        down = function() return true end,
        select = function(slot)
            if slot then
                selected = slot
            end
            return selected
        end,
        count = function(slot) return stub.inventory[slot or selected] or 0 end,
        inventorySize = function() return 16 end,
        useDown = function() return true end,
        swingDown = function() return true end,
        suckDown = function() return true end,
        dropDown = function() return true end,
    }
end

package.preload['component'] = function()
    return {
        inventory_controller = {
            getInventorySize = function() return stub.chestSize end,
            getStackInSlot = function(_, slot) return stub.chest[slot] end,
            suckFromSlot = function() return true end,
            dropIntoSlot = function() return true end,
            equip = function() return true end,
        },
        redstone = {setOutput = function() end},
        geolyzer = {
            analyze = function()
                return table.remove(stub.scans, 1) or {name = 'minecraft:air'}
            end,
        },
        computer = {beep = function() end},
    }
end
```

- [ ] **Step 5: Smoke-check the helper**

Run: `python -c "import sys; sys.path.insert(0, r'C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests'); from lua_env import runtime; print(runtime(stubs=True).eval(\"require('config').workingFarmSize\"))"`

Expected: `6`

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add tests/lua_env.py tests/oc_stubs.lua
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "test: add lupa runtime helper and OpenComputers stubs" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Generator — weight formula

**Files:**
- Create: ADV `scripts/build_crop_table.py`
- Create: ADV `tests/test_build_crop_table.py`

- [ ] **Step 1: Write the failing tests** in ADV `tests/test_build_crop_table.py`

```python
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_crop_table as bct  # noqa: E402


def crop(n, t, a, s=None):
    return {"n": n, "d": n, "t": t, "a": a, "s": s}


class RatioTest(unittest.TestCase):
    def test_same_species_is_500(self):
        c = crop("Bauxia", 6, ["Metal"])
        self.assertEqual(bct.ratio(c, c), 500)

    def test_shared_attributes_count_every_pair_ignoring_case(self):
        bauxia = crop("Bauxia", 6, ["Metal", "Aluminium", "Reed", "Aluminium"])
        parent = crop("P", 6, ["aluminium"])
        self.assertEqual(bct.ratio(bauxia, parent), 10)

    def test_tier_gap_penalties(self):
        p = crop("P", 6, ["Metal"])
        for tier, expected in [(7, 5), (8, 1), (3, 5), (2, 1), (12, 0)]:
            with self.subTest(tier=tier):
                self.assertEqual(bct.ratio(crop("X", tier, ["metal"]), p), expected)

    def test_properties_term_when_both_known(self):
        bauxia = crop("Bauxia", 6, ["Metal", "Aluminium", "Reed", "Aluminium"], [5, 0, 2, 3, 3])
        stagnium = crop("stagnium", 6, ["Shiny", "Leaves", "Metal"], [2, 0, 0, 1, 0])
        twin = crop("Twin", 6, ["Metal"], [5, 0, 2, 3, 3])
        self.assertEqual(bct.ratio(bauxia, stagnium), 5)   # properties sum to 0, Metal +5
        self.assertEqual(bct.ratio(bauxia, twin), 15)      # 5 x (+2), Metal +5

    def test_properties_term_skipped_when_unknown(self):
        known = crop("A", 6, ["Metal"], [0, 0, 0, 0, 0])
        unknown = crop("B", 6, ["Metal"])
        self.assertEqual(bct.ratio(known, unknown), 5)


class TotalWeightTest(unittest.TestCase):
    def test_total_weight_includes_own_500(self):
        crops = [crop("A", 6, ["Metal"]), crop("B", 6, ["Metal"]), crop("C", 6, ["Food"])]
        bct.add_total_weights(crops)
        self.assertEqual([c["w"] for c in crops], [505, 505, 500])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'build_crop_table'`

- [ ] **Step 3: Create ADV `scripts/build_crop_table.py`**

```python
"""Build crops.lua - the crop table the robot's autoBreed program uses.

Source: the GTNH wiki page "IC2 Crops List" (display name, internal name, tier,
attributes for every crop). IC2's five hidden crop properties are not on the
wiki; this version writes them as unknown (no s= field) and says so.

ratio() mirrors IC2's TileEntityCrop.calculateRatioFor, read from
industrialcraft-2-2.2.828-experimental.jar (GTNH 2.8.4).

Usage (from the project root):
    python scripts/build_crop_table.py
    python scripts/build_crop_table.py --out path/to/crops.lua
"""
import argparse
import datetime
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_wiki import api_get, strip_wikimarkup  # noqa: E402

PAGE = "IC2 Crops List"
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "CropBot" / "GTNH-CropAutomation" / "crops.lua"


def ratio(x, p):
    """Weight of species x in a cross that parent p joined (IC2 calculateRatioFor)."""
    if x["n"] == p["n"]:
        return 500
    v = 0
    if x["s"] is not None and p["s"] is not None:
        for a, b in zip(x["s"], p["s"]):
            v += 2 - abs(a - b)
    for a in x["a"]:
        for b in p["a"]:
            if a.lower() == b.lower():
                v += 5
    d = x["t"] - p["t"]
    if d > 1:
        v -= 2 * d
    if d < -3:
        v -= -d
    return max(v, 0)


def add_total_weights(crops):
    """Set each record's "w": the sum of ratio(x, p) over every crop x (500 for itself)."""
    for p in crops:
        p["w"] = sum(ratio(x, p) for x in crops)
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: `Ran 6 tests` … `OK`

(ADV is not a git repo, so there is nothing to commit.)

---

### Task 3: Generator — wiki tables to crop records

**Files:**
- Modify: ADV `scripts/build_crop_table.py`
- Modify: ADV `tests/test_build_crop_table.py`

- [ ] **Step 1: Add the failing tests** to ADV `tests/test_build_crop_table.py`, above the `if __name__ == "__main__":` line.

```python
WIKITEXT = """== Crops added by IC2 ==
{| class="wikitable"
! style="x" | Name
! style="x" | Discovered By
! style="x" | Seed
! style="x" | Drops
! style="x" | Tier
! style="x" | Attributes
! style="x" | Growth Stages
! style="x" | GS After Harvest
! style="x" | Relative Speed
! style="x" | Internal Name
! style="x" | Notes
|-
!Stagnium
|IC2 Team
|
|Stagnium Leaves
|6
|Shiny, Leaves, Metal
|4
|2
|Stages 1-3: 750
Stage 4: 2200
|stagnium
|Needs tin underneath.
|-
!Brown Mushrooms
|IC2 Team
|
|Brown Mushroom
|2
|Brown, Food, Mushroom
|3
|1
|Stages 1-2: 200
|Brown Mushrooms
|
|}
== Crops added by Crops++ ==
{| class="wikitable"
! style="x" | Name
! style="x" | Discovered By
! style="x" | Seed
! style="x" | Drops
! style="x" | Premature Drop<ref>Harvestable one stage early.</ref>
! style="x" | Tier
! style="x" | Attributes
! style="x" | Growth Stages
! style="x" | GS After Harvest
! style="x" | Relative Speed
! style="x" | Internal Name
! style="x" | Notes
|-
|'''Salty Root'''
|shawnbyday
|
|Salty Root
|
|4
|Salt, Gray, Root, Hydrophobic
|3
|1
|Stages 1-2: 800
|saltroot
|
|}
"""


class ParseTablesTest(unittest.TestCase):
    def test_columns_are_mapped_per_table(self):
        rows = bct.parse_tables(WIKITEXT)
        self.assertEqual([r["Name"] for r in rows], ["Stagnium", "Brown Mushrooms", "Salty Root"])
        self.assertEqual(rows[0]["Tier"], "6")
        self.assertEqual(rows[0]["Relative Speed"], "Stages 1-3: 750\nStage 4: 2200")
        self.assertEqual(rows[2]["Tier"], "4")
        self.assertEqual(rows[2]["Internal Name"], "saltroot")


class CropsFromRowsTest(unittest.TestCase):
    def test_records_fixes_duplicates_and_bad_rows(self):
        rows = bct.parse_tables(WIKITEXT) + [
            {"Name": "Brown Mushrooms", "Tier": "2", "Internal Name": "Brown Mushrooms", "Attributes": "Brown"},
            {"Name": "Broken", "Tier": "", "Internal Name": "broken", "Attributes": "X"},
        ]
        crops, warnings = bct.crops_from_rows(rows)
        self.assertEqual([c["n"] for c in crops], ["stagnium", "brownMushroom", "saltroot"])
        self.assertEqual(crops[0], {"n": "stagnium", "d": "Stagnium", "t": 6,
                                    "a": ["Shiny", "Leaves", "Metal"], "s": None})
        self.assertEqual(crops[2]["d"], "Salty Root")
        self.assertEqual(len(warnings), 2)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: FAIL with `AttributeError: module 'build_crop_table' has no attribute 'parse_tables'`

- [ ] **Step 3: Add the parser.** In ADV `scripts/build_crop_table.py`, insert after the `DEFAULT_OUT = …` line:

```python

# The wiki's "Internal Name" is wrong for these IC2 crops; the real names are
# returned by CropBrownMushroom.name() / CropRedMushroom.name() in the IC2 jar.
INTERNAL_NAME_FIXES = {"brown mushrooms": "brownMushroom", "red mushrooms": "redMushroom"}


def parse_tables(wikitext):
    """Return every data row of every wiki table as a {column header: text} dict.

    Columns are mapped by each table's own header row, because the Crops++
    table has an extra "Premature Drop" column.
    """
    rows = []
    for table in re.findall(r"\{\|(.*?)\n\|\}", wikitext, re.S):
        chunks = re.split(r"\n\|-", table)
        headers = []
        for line in chunks[0].split("\n"):
            if line.startswith("!"):
                headers.append(strip_wikimarkup(line[1:].split("|")[-1]))
        for chunk in chunks[1:]:
            cells = []
            for line in chunk.split("\n"):
                if line.startswith(("!", "|")):
                    cells.extend(re.split(r"\|\||!!", line[1:]))
                elif cells and line.strip():
                    cells[-1] += "\n" + line
            if cells:
                rows.append({h: strip_wikimarkup(c) for h, c in zip(headers, cells)})
    return rows


def crops_from_rows(rows):
    """Turn wiki rows into crop records; return (crops, warnings).

    A record is {"n": internal name, "d": display name, "t": tier,
    "a": [attributes], "s": None (hidden properties unknown here)}.
    """
    crops, warnings, seen = [], [], set()
    for row in rows:
        name = row.get("Name", "").strip()
        internal = row.get("Internal Name", "").strip()
        tier_text = row.get("Tier", "").strip()
        if not name or not internal or not tier_text.isdigit():
            warnings.append(f"skipped row {name or '?'}: missing name, internal name or tier")
            continue
        internal = INTERNAL_NAME_FIXES.get(internal.lower(), internal)
        if internal.lower() in seen:
            warnings.append(f"skipped duplicate internal name {internal}")
            continue
        seen.add(internal.lower())
        attrs = [a.strip() for a in row.get("Attributes", "").split(",") if a.strip()]
        crops.append({"n": internal, "d": name, "t": int(tier_text), "a": attrs, "s": None})
    return crops, warnings
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: `Ran 8 tests` … `OK`

---

### Task 4: Generator — write `crops.lua`

**Files:**
- Modify: ADV `scripts/build_crop_table.py`
- Modify: ADV `tests/test_build_crop_table.py`
- Create (generated): BOT `crops.lua`

- [ ] **Step 1: Add the failing test** to ADV `tests/test_build_crop_table.py`, above `if __name__ == "__main__":`

```python
class ToLuaTest(unittest.TestCase):
    def test_format(self):
        crops = [crop("Bob's", 3, ["A", "B"]), crop("K", 1, ["C"], [1, 2, 3, 4, 5])]
        crops[0]["w"], crops[1]["w"] = 500, 501
        text = bct.to_lua(crops, 20707, "2026-09-27")
        lines = text.splitlines()
        self.assertTrue(lines[0].startswith("-- Generated by build_crop_table.py on 2026-09-27"))
        self.assertIn("rev 20707", lines[0])
        self.assertIn("known for 1 of 2 crops", lines[1])
        self.assertIn("  {n='Bob\\'s', d='Bob\\'s', t=3, a='A,B', w=500},", lines)
        self.assertIn("  {n='K', d='K', t=1, a='C', s='1,2,3,4,5', w=501},", lines)
        self.assertEqual(lines[-1], "}")
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: FAIL with `AttributeError: module 'build_crop_table' has no attribute 'to_lua'`

- [ ] **Step 3: Add the writer and command line** at the end of ADV `scripts/build_crop_table.py`

```python


def lua_string(text):
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"


def to_lua(crops, revid, today):
    known = sum(1 for c in crops if c["s"] is not None)
    lines = [
        f'-- Generated by build_crop_table.py on {today} from wiki "{PAGE}" rev {revid}. Do not edit.',
        f"-- Hidden crop properties known for {known} of {len(crops)} crops (entries without s= are unknown).",
        "return {",
    ]
    for c in crops:
        fields = [f"n={lua_string(c['n'])}", f"d={lua_string(c['d'])}", f"t={c['t']}",
                  f"a={lua_string(','.join(c['a']))}"]
        if c["s"] is not None:
            fields.append(f"s={lua_string(','.join(str(v) for v in c['s']))}")
        fields.append(f"w={c['w']}")
        lines.append("  {" + ", ".join(fields) + "},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build crops.lua for the crop bot's autoBreed.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)

    data = api_get({"action": "parse", "page": PAGE, "prop": "wikitext|revid"})["parse"]
    crops, warnings = crops_from_rows(parse_tables(data["wikitext"]))
    add_total_weights(crops)
    today = datetime.date.today().isoformat()
    args.out.write_text(to_lua(crops, data.get("revid"), today), encoding="utf-8", newline="\n")

    known = sum(1 for c in crops if c["s"] is not None)
    print(f"wrote {len(crops)} crops to {args.out}")
    print(f"hidden properties known for {known} of {len(crops)} crops")
    for warning in warnings:
        print("warning:", warning)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: `Ran 9 tests` … `OK`

- [ ] **Step 5: Generate the real table**

Run: `python "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/scripts/build_crop_table.py"`

Expected (as of wiki rev 20707):

```
wrote 159 crops to C:\Users\loope\Desktop\GTNH 2.8.4 Agent\CropBot\GTNH-CropAutomation\crops.lua
hidden properties known for 0 of 159 crops
warning: skipped duplicate internal name brownMushroom
warning: skipped duplicate internal name redMushroom
```

- [ ] **Step 6: Spot-check the output**

Run: `python -c "t=open(r'C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/crops.lua',encoding='utf-8').read(); print([l for l in t.splitlines() if \"n='Bauxia'\" in l or \"n='stagnium'\" in l])"`

Expected: two lines. The Bauxia line starts `  {n='Bauxia', d='Bauxia', t=6, a='Metal,Aluminium,Reed,Aluminium', w=`, and the stagnium line starts `  {n='stagnium', d='Stagnium', t=6, a='Shiny,Leaves,Metal', w=`.

- [ ] **Step 7: Commit the table**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add crops.lua
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: add generated crop table for autoBreed" -m "159 crops from the GTNH wiki IC2 Crops List (rev 20707); hidden properties not yet included." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `breeding.lua`

**Files:**
- Create: BOT `breeding.lua`
- Create: BOT `tests/test_breeding.py`

Hand-worked numbers used below (no properties; 5 × shared attributes, minus tier penalties):

| p | W(p) | ratio(Bauxia, p) | e(p) |
|---|---|---|---|
| Argentia (t7) | 525 | 10 | 10/525 |
| Nickelback (t5) | 511 | 5 | 5/511 |
| Stagnium (t6) | 520 | 5 | 5/520 |
| Salty Root (t4) | 500 | 0 | 0 |

- [ ] **Step 1: Write the failing tests** in BOT `tests/test_breeding.py`

```python
import unittest

from lua_env import runtime

FIXTURE = """{
  {n='Bauxia', d='Bauxia', t=6, a='Metal,Aluminium,Reed,Aluminium', w=0},
  {n='stagnium', d='Stagnium', t=6, a='Shiny,Leaves,Metal', w=0},
  {n='Nickelback', d='Nickelback', t=5, a='Metal,Fire,Alloy', w=0},
  {n='Argentia', d='Argentia', t=7, a='Shiny,Metal,Silver,Reed', w=0},
  {n='saltroot', d='Salty Root', t=4, a='Salt,Gray,Root,Hydrophobic', w=0},
}"""


class BreedingTest(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.b = self.lua.eval("require('breeding')")
        self.lua.execute("""
            local b = require('breeding')
            local data = """ + FIXTURE + """
            for _, p in ipairs(data) do
                local w = 0
                for _, x in ipairs(data) do w = w + b.ratio(x, p) end
                p.w = w
            end
            b.load(data)
        """)

    def test_ratio_hand_worked_values(self):
        get = self.b.resolve
        self.assertEqual(self.b.ratio(get('Bauxia'), get('Bauxia')), 500)
        self.assertEqual(self.b.ratio(get('Bauxia'), get('Argentia')), 10)
        self.assertEqual(self.b.ratio(get('Argentia'), get('Nickelback')), 1)
        self.assertEqual(self.b.ratio(get('Bauxia'), get('Salty Root')), 0)

    def test_ratio_tier_gap_penalties(self):
        p = self.lua.eval("{n='P', t=6, a='Metal'}")
        for tier, expected in [(7, 5), (8, 1), (3, 5), (2, 1), (12, 0)]:
            with self.subTest(tier=tier):
                x = self.lua.eval("{n='X', t=%d, a='metal'}" % tier)
                self.assertEqual(self.b.ratio(x, p), expected)

    def test_ratio_uses_properties_only_when_both_known(self):
        ev = self.lua.eval
        a = ev("{n='A', t=6, a='Metal', s='5,0,2,3,3'}")
        twin = ev("{n='B', t=6, a='Metal', s='5,0,2,3,3'}")
        far = ev("{n='C', t=6, a='Metal', s='9,9,9,9,9'}")
        unknown = ev("{n='D', t=6, a='Metal'}")
        self.assertEqual(self.b.ratio(a, twin), 15)
        self.assertEqual(self.b.ratio(a, unknown), 5)
        self.assertEqual(self.b.ratio(a, far), 0)

    def test_resolve_by_internal_or_display_name(self):
        self.assertEqual(self.b.resolve('STAGNIUM')['n'], 'stagnium')
        self.assertEqual(self.b.resolve('salty root')['n'], 'saltroot')
        missing, suggestions = self.b.resolve('ent')
        self.assertIsNone(missing)
        self.assertEqual(list(suggestions.values()), ['Argentia'])

    def test_prepare_ranks_parents(self):
        info = self.b.prepare(self.b.resolve('Bauxia'))
        self.assertAlmostEqual(info['argentia']['e'], 10 / 525)
        self.assertAlmostEqual(info['nickelback']['e'], 5 / 511)
        self.assertAlmostEqual(info['stagnium']['e'], 5 / 520)
        self.assertEqual(info['saltroot']['e'], 0)
        self.assertEqual(info['bauxia']['t'], 6)
        top = [entry['d'] for entry in self.b.top(5).values()]
        self.assertEqual(top, ['Argentia', 'Nickelback', 'Stagnium'])

    def test_seed_bag_labels(self):
        self.b.prepare(self.b.resolve('Bauxia'))
        self.assertEqual(self.b.labelToKey('Stagnium Seeds'), 'stagnium')
        self.assertEqual(self.b.labelToKey('Salty Root Seeds'), 'saltroot')
        self.assertEqual(self.b.labelToKey('saltroot Seeds'), 'saltroot')
        self.assertIsNone(self.b.labelToKey('Unknown Seeds'))
        self.assertIsNone(self.b.labelToKey('Mystery Seeds'))
        self.assertIsNone(self.b.labelToKey('Crop Sticks'))

    def test_chance_over_parent_keys(self):
        self.b.prepare(self.b.resolve('Bauxia'))
        keys = self.lua.eval("{'stagnium', 'nickelback', 'unknownCrop'}")
        self.assertAlmostEqual(self.b.chance(keys), 10 / 1031)
        self.assertEqual(self.b.chance(self.lua.eval("{}")), 0)

    def test_prepared_info_survives_unload(self):
        self.b.prepare(self.b.resolve('Bauxia'))
        self.b.unload()
        self.assertEqual(self.b.labelToKey('Stagnium Seeds'), 'stagnium')
        self.assertIsNone(self.lua.eval("package.loaded.crops"))

    def test_properties_known_counts(self):
        self.assertEqual(tuple(self.b.propertiesKnown()), (0, 5))


class RealTableTest(unittest.TestCase):
    def test_lua_weights_match_the_generator(self):
        lua = runtime()
        mismatches = lua.execute("""
            local b = require('breeding')
            local data = require('crops')
            b.load(data)
            local bad = 0
            for _, p in ipairs(data) do
                local w = 0
                for _, x in ipairs(data) do w = w + b.ratio(x, p) end
                if w ~= p.w then bad = bad + 1 end
            end
            return bad
        """)
        self.assertEqual(mismatches, 0)

    def test_bauxia_is_in_the_table(self):
        lua = runtime()
        b = lua.eval("require('breeding')")
        b.load()
        rec = b.resolve('bauxia')
        self.assertEqual((rec['n'], rec['t'], rec['a']), ('Bauxia', 6, 'Metal,Aluminium,Reed,Aluminium'))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_breeding.py" -v`

Expected: FAIL with a Lua error containing `module 'breeding' not found`

- [ ] **Step 3: Create BOT `breeding.lua`**

```lua
-- Crop math for autoBreed. Pure Lua with no OpenComputers calls, so it can be
-- unit-tested off the robot. ratio() mirrors IC2's
-- TileEntityCrop.calculateRatioFor (industrialcraft-2-2.2.828-experimental).
local crops, byName, byDisplay
local info, infoByDisplay, targetKey


local function load(data)
    crops = data or require('crops')
    byName, byDisplay = {}, {}
    for _, c in ipairs(crops) do
        byName[c.n:lower()] = c
        byDisplay[c.d:lower()] = c
    end
    return #crops
end


-- Frees the full table; anything built by prepare() keeps working.
local function unload()
    crops, byName, byDisplay = nil, nil, nil
    package.loaded.crops = nil
end


local function propertiesKnown()
    local known = 0
    for _, c in ipairs(crops) do
        if c.s then
            known = known + 1
        end
    end
    return known, #crops
end


local function numbers(text)
    local out = {}
    for value in text:gmatch('[^,]+') do
        out[#out+1] = tonumber(value)
    end
    return out
end


-- Weight of species x in a cross that parent p joined.
local function ratio(x, p)
    if x.n == p.n then
        return 500
    end

    local v = 0
    if x.s and p.s then
        local xs, ps = numbers(x.s), numbers(p.s)
        for i=1, 5 do
            v = v + 2 - math.abs(xs[i] - ps[i])
        end
    end

    for a in x.a:gmatch('[^,]+') do
        for b in p.a:gmatch('[^,]+') do
            if a:lower() == b:lower() then
                v = v + 5
            end
        end
    end

    local d = x.t - p.t
    if d > 1 then
        v = v - 2 * d
    end
    if d < -3 then
        v = v + d
    end
    return math.max(v, 0)
end


-- Finds a crop by internal or display name (any case). Returns the record, or
-- nil plus up to 5 display names containing the text.
local function resolve(text)
    local key = text:lower()
    local hit = byName[key] or byDisplay[key]
    if hit then
        return hit
    end

    local suggestions = {}
    for _, c in ipairs(crops) do
        if #suggestions < 5 and (c.n:lower():find(key, 1, true) or c.d:lower():find(key, 1, true)) then
            suggestions[#suggestions+1] = c.d
        end
    end
    return nil, suggestions
end


-- Builds the per-crop info map for a target, keyed by lowercase internal name:
-- {n, d, t, r = ratio(target, crop), w, e = r / w}.
local function prepare(target)
    info, infoByDisplay, targetKey = {}, {}, target.n:lower()
    for _, c in ipairs(crops) do
        local r = ratio(target, c)
        local key = c.n:lower()
        info[key] = {n=c.n, d=c.d, t=c.t, r=r, w=c.w, e=r / c.w}
        infoByDisplay[c.d:lower()] = key
    end
    return info
end


-- "Stagnium Seeds" -> "stagnium"; nil for unscanned, invalid or unknown bags.
local function labelToKey(label)
    local name = label:match('^(.-) Seeds$')
    if not name then
        return nil
    end
    name = name:lower()
    if info[name] then
        return name
    end
    return infoByDisplay[name]
end


-- Chance that a cross among these parents yields the target. Unknown keys are ignored.
local function chance(keys)
    local num, den = 0, 0
    for _, key in ipairs(keys) do
        local entry = info[key]
        if entry then
            num = num + entry.r
            den = den + entry.w
        end
    end
    if den == 0 then
        return 0
    end
    return num / den
end


-- The best parents for the target (e > 0), best first.
local function top(count)
    local list = {}
    for key, entry in pairs(info) do
        if key ~= targetKey and entry.e > 0 then
            list[#list+1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.e ~= b.e then
            return a.e > b.e
        end
        return a.d < b.d
    end)
    while #list > count do
        table.remove(list)
    end
    return list
end


return {
    load = load,
    unload = unload,
    propertiesKnown = propertiesKnown,
    ratio = ratio,
    resolve = resolve,
    prepare = prepare,
    labelToKey = labelToKey,
    chance = chance,
    top = top
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_breeding.py" -v`

Expected: `Ran 11 tests` … `OK`

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add breeding.lua tests/test_breeding.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: add breeding module (IC2 crossbreeding weights and ranking)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `breedpolicy.lua`

**Files:**
- Create: BOT `breedpolicy.lua`
- Create: BOT `tests/test_breedpolicy.py`

- [ ] **Step 1: Write the failing tests** in BOT `tests/test_breedpolicy.py`

```python
import unittest

from lua_env import runtime

CTX = """{
    info = {bauxia = {e = 0.5}, stagnium = {e = 0.01}, nickelback = {e = 0.009}},
    targetKey = 'bauxia',
    caps = {workingMaxGrowth = 21, workingMaxResistance = 2},
    worstParent = {slot = 3, e = %(worst)s},
    bestChestE = %(chest)s,
    keepMutations = %(keep)s,
    seenInStorage = function(name) return name == 'Ferru' end
}"""


class PolicyTest(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.policy = self.lua.eval("require('breedpolicy')")

    def ctx(self, worst=0.009, chest=0, keep='false'):
        return self.lua.eval(CTX % {'worst': worst, 'chest': chest, 'keep': keep})

    def crop(self, name, gr=1, re=1):
        return self.lua.eval("{isCrop=true, name='%s', gr=%d, ga=1, re=%d}" % (name, gr, re))

    def empty(self, name):
        return self.lua.eval("{isCrop=true, name='%s'}" % name)

    def test_parent_actions(self):
        act = self.policy.parentAction
        self.assertEqual(act(self.empty('air'), self.ctx(chest=0.01)), 'plant')
        self.assertEqual(act(self.empty('emptyCrop'), self.ctx(chest=0)), 'wait')
        self.assertEqual(act(self.crop('weed'), self.ctx()), 'remove')
        self.assertEqual(act(self.crop('stagnium', gr=24), self.ctx()), 'remove')
        self.assertEqual(act(self.crop('Nickelback'), self.ctx(chest=0.01)), 'replaceFromChest')
        self.assertEqual(act(self.crop('stagnium'), self.ctx(chest=0.01)), 'keep')   # tie: no swap
        self.assertEqual(act(self.crop('stagnium'), self.ctx(chest=0)), 'keep')

    def test_child_actions(self):
        act = self.policy.childAction
        self.assertEqual(act(self.empty('air'), self.ctx()), 'stick')
        self.assertEqual(act(self.empty('emptyCrop'), self.ctx()), 'none')
        self.assertEqual(act(self.crop('Grass'), self.ctx()), 'weed')
        self.assertEqual(act(self.crop('venomilia', gr=8), self.ctx()), 'weed')
        self.assertEqual(act(self.crop('Bauxia', gr=21, re=2), self.ctx()), 'captureSlot1')
        self.assertEqual(act(self.crop('Bauxia', gr=22, re=1), self.ctx()), 'captureStorage')
        self.assertEqual(act(self.crop('Bauxia', gr=1, re=3), self.ctx()), 'captureStorage')
        self.assertEqual(act(self.crop('Bauxia', gr=24), self.ctx()), 'weed')
        self.assertEqual(act(self.crop('stagnium'), self.ctx(worst=0.009)), 'promote')
        self.assertEqual(act(self.crop('Nickelback'), self.ctx(worst=0.009)), 'destroy')   # tie: no swap
        self.assertEqual(act(self.crop('Ferru'), self.ctx(worst=-1)), 'promote')           # empty slot
        self.assertEqual(act(self.crop('Ferru'), self.ctx(keep='true')), 'destroy')         # already stored
        self.assertEqual(act(self.crop('Cyprium'), self.ctx(keep='true')), 'store')

    def test_is_weed_like(self):
        weedy = self.policy.isWeedLike
        self.assertTrue(weedy(self.crop('weed')))
        self.assertTrue(weedy(self.crop('stagnium', gr=24)))
        self.assertFalse(weedy(self.crop('stagnium', gr=23)))
        self.assertFalse(weedy(self.crop('venomilia', gr=7)))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_breedpolicy.py" -v`

Expected: FAIL with a Lua error containing `module 'breedpolicy' not found`

- [ ] **Step 3: Create BOT `breedpolicy.lua`**

```lua
-- Decision rules for autoBreed. Pure Lua: each function takes plain tables and
-- returns an action code, so every rule is unit-tested off the robot.

-- Crops IC2 treats like weeds: real weeds, Growth 24+ (they spread onto empty
-- crop sticks), and Venomilia above Growth 7 (the existing scanner rule).
local function isWeedLike(crop)
    return crop.name == 'weed'
        or crop.name == 'Grass'
        or (crop.gr or 0) >= 24
        or (crop.name == 'venomilia' and (crop.gr or 0) > 7)
end


local function isEmpty(crop)
    return crop.name == 'air' or crop.name == 'emptyCrop'
end


local function efficiency(ctx, crop)
    local entry = ctx.info[crop.name:lower()]
    return entry and entry.e or 0
end


-- ctx: info, bestChestE
local function parentAction(crop, ctx)
    if isEmpty(crop) then
        if ctx.bestChestE > 0 then
            return 'plant'
        end
        return 'wait'
    end
    if isWeedLike(crop) then
        return 'remove'
    end
    if ctx.bestChestE > efficiency(ctx, crop) then
        return 'replaceFromChest'
    end
    return 'keep'
end


-- ctx: info, targetKey, caps, worstParent, keepMutations, seenInStorage
local function childAction(crop, ctx)
    if crop.name == 'air' then
        return 'stick'
    end
    if crop.name == 'emptyCrop' then
        return 'none'
    end
    if isWeedLike(crop) then
        return 'weed'
    end
    if crop.name:lower() == ctx.targetKey then
        if crop.gr <= ctx.caps.workingMaxGrowth and crop.re <= ctx.caps.workingMaxResistance then
            return 'captureSlot1'
        end
        return 'captureStorage'
    end
    if efficiency(ctx, crop) > ctx.worstParent.e then
        return 'promote'
    end
    if ctx.keepMutations and not ctx.seenInStorage(crop.name) then
        return 'store'
    end
    return 'destroy'
end


return {
    isWeedLike = isWeedLike,
    parentAction = parentAction,
    childAction = childAction
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_breedpolicy.py" -v`

Expected: `Ran 3 tests` … `OK`

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add breedpolicy.lua tests/test_breedpolicy.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: add autoBreed decision rules" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `config.lua` settings

**Files:**
- Modify: BOT `config.lua`
- Create: BOT `tests/test_lua_syntax.py`

- [ ] **Step 1: Add the syntax guard** in BOT `tests/test_lua_syntax.py`

```python
import unittest

from lua_env import REPO, runtime


class LuaSyntaxTest(unittest.TestCase):
    def test_every_lua_file_compiles(self):
        lua = runtime()
        compile_error = lua.eval("function(src, name) local _, err = load(src, '=' .. name) return err end")
        for path in sorted(REPO.glob("*.lua")):
            with self.subTest(file=path.name):
                self.assertIsNone(compile_error(path.read_text(encoding="utf-8"), path.name))

    def test_config_has_autobreed_settings(self):
        config = runtime().eval("require('config')")
        self.assertEqual(list(config['seedContainerPos'].values()), [-3, 0])
        self.assertIsNone(config['breedTarget'])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch the config test fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_lua_syntax.py" -v`

Expected: `test_every_lua_file_compiles` passes. `test_config_has_autobreed_settings` fails because `config['seedContainerPos']` is None.

- [ ] **Step 3: Edit BOT `config.lua`** — add the new settings after `statWhileTiering`

Replace:

```lua
    -- Stat-up crops during autoTier (Very Slow)
    statWhileTiering = false,
```

with:

```lua
    -- Stat-up crops during autoTier (Very Slow)
    statWhileTiering = false,
    -- Default crop for autoBreed when no name is given, e.g. 'Bauxia'
    breedTarget = nil,
    -- Seed chest that autoBreed plants parents from (one past the storage chest)
    seedContainerPos = {-3, 0},
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_lua_syntax.py" -v`

Expected: `Ran 2 tests` … `OK`

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add config.lua tests/test_lua_syntax.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: add autoBreed config settings" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `action.lua` — fix and new helpers

**Files:**
- Modify: BOT `action.lua`
- Create: BOT `tests/test_action.py`

- [ ] **Step 1: Write the failing tests** in BOT `tests/test_action.py`

```python
import unittest

from lua_env import runtime

STAGNIUM = ("{name='IC2:blockCrop', ['crop:name']='stagnium', ['crop:growth']=3, ['crop:gain']=4,"
            " ['crop:resistance']=5, ['crop:tier']=6, ['crop:size']=1, ['crop:maxSize']=4}")


class StorageSlotTest(unittest.TestCase):
    def test_skips_occupied_storage_slots(self):
        lua = runtime(stubs=True)
        result = lua.execute("""
            stub.scans = {%s, {name='minecraft:stone'}, {name='IC2:blockCrop'}}
            local action = require('action')
            local database = require('database')
            database.resetStorage()
            return action.findStorageSlot(), #database.getStorage()
        """ % STAGNIUM)
        self.assertEqual(tuple(result), (3, 2))

    def test_full_storage_returns_nil(self):
        lua = runtime(stubs=True)
        result = lua.execute("""
            for i=1, 81 do stub.scans[i] = {name='minecraft:stone'} end
            local action = require('action')
            local database = require('database')
            database.resetStorage()
            return action.findStorageSlot(), #database.getStorage()
        """)
        self.assertEqual(tuple(result), (None, 81))


class SeedChestTest(unittest.TestCase):
    def test_reads_stacks(self):
        lua = runtime(stubs=True)
        result = lua.execute("""
            stub.chest = {[1]={label='Stagnium Seeds', size=4}, [3]={label='Crop Sticks', size=64}}
            local stacks = require('action').readSeedChest()
            return #stacks, stacks[1].slot, stacks[1].label, stacks[2].slot, stacks[2].size
        """)
        self.assertEqual(tuple(result), (2, 1, 'Stagnium Seeds', 3, 64))

    def test_no_chest_returns_nil(self):
        lua = runtime(stubs=True)
        self.assertIsNone(lua.execute("stub.chestSize = nil return require('action').readSeedChest()"))


class PlantFromChestTest(unittest.TestCase):
    def test_plants_and_returns_the_crop(self):
        lua = runtime(stubs=True)
        result = lua.execute("""
            stub.scans = {{name='minecraft:air'}, %s}
            local crop = require('action').plantFromChest(1, {-1, 1})
            return crop.name, crop.gr
        """ % STAGNIUM)
        self.assertEqual(tuple(result), ('stagnium', 3))

    def test_returns_nil_when_nothing_planted(self):
        lua = runtime(stubs=True)
        result = lua.execute("""
            stub.scans = {{name='IC2:blockCrop'}, {name='IC2:blockCrop'}}
            return require('action').plantFromChest(1, {-1, 1})
        """)
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_action.py" -v`

Expected: FAIL with Lua errors like `attempt to call a nil value (field 'findStorageSlot')`

- [ ] **Step 3: Fix the inventory-full crash** in BOT `action.lua`

Replace `local restockAll, cleanUp  -- Forward declaration` with:

```lua
local restockAll, cleanUp, dumpInventory  -- Forward declaration
```

Replace `local function dumpInventory()` with:

```lua
function dumpInventory()
```

- [ ] **Step 4: Add the helpers and the bad-parent rule** in BOT `action.lua`, directly above `function cleanUp()`

Replace:

```lua
function cleanUp()
    for slot=1, config.workingFarmArea, 1 do
```

with:

```lua
-- Returns the first storage slot that is air or a bare crop stick, recording the
-- occupied slots it passes so nothing already in the storage farm is overwritten.
-- Returns nil when the storage farm is full.
local function findStorageSlot()
    gps.save()
    local found
    while database.nextStorageSlot() <= config.storageFarmArea do
        local slot = database.nextStorageSlot()
        gps.go(gps.storageSlotToPos(slot))
        local crop = scanner.scan()
        if crop.name == 'air' or crop.name == 'emptyCrop' then
            found = slot
            break
        end
        database.addToStorage(crop)
    end
    gps.resume()
    return found
end


-- Moves the crop at src into the next free storage slot. Returns false when full.
local function transplantToStorage(src, crop)
    local slot = findStorageSlot()
    if not slot then
        return false
    end
    transplant(src, gps.storageSlotToPos(slot))
    database.addToStorage(crop)
    return true
end


-- Lists the seed chest as {slot, label, size} stacks, or nil if there is no chest.
local function readSeedChest()
    gps.save()
    gps.go(config.seedContainerPos)
    local stacks
    local size = inventory_controller.getInventorySize(sides.down)
    if size then
        stacks = {}
        for i=1, size do
            os.sleep(0)
            local stack = inventory_controller.getStackInSlot(sides.down, i)
            if stack then
                stacks[#stacks+1] = {slot=i, label=stack.label, size=stack.size}
            end
        end
    end
    gps.resume()
    return stacks
end


local function freeSlot()
    for i=1, robot.inventorySize() + config.storageStopSlot do
        if robot.count(i) == 0 then
            return i
        end
    end
end


-- Carries one seed bag from the seed chest to pos and plants it on a single crop
-- stick. Returns the scanned crop, or nil if nothing was planted (the bag goes
-- back to the seed chest).
local function plantFromChest(chestSlot, pos)
    local selected = robot.select()
    gps.save()

    if freeSlot() == nil then
        dumpInventory()
    end
    local slot = freeSlot()
    if slot == nil then
        gps.resume()
        return nil
    end

    robot.select(slot)
    gps.go(config.seedContainerPos)
    inventory_controller.suckFromSlot(sides.down, chestSlot, 1)

    gps.go(pos)
    if scanner.scan().name == 'air' then
        placeCropStick()
    end
    robot.select(slot)
    inventory_controller.equip()
    robot.useDown()
    inventory_controller.equip()

    local crop = scanner.scan()
    local planted = crop.isCrop and crop.name ~= 'air' and crop.name ~= 'emptyCrop'
    if not planted and robot.count(slot) > 0 then
        gps.go(config.seedContainerPos)
        robot.dropDown()
    end

    gps.resume()
    robot.select(selected)
    if planted then
        return crop
    end
    return nil
end


local function defaultBadParent(crop)
    return scanner.isWeed(crop, 'working')
end
local badParent = defaultBadParent


-- Chooses which parents cleanUp removes; initWork() resets it to the default.
local function setBadParentRule(rule)
    badParent = rule or defaultBadParent
end


function cleanUp()
    for slot=1, config.workingFarmArea, 1 do
```

- [ ] **Step 5: Use the rule in `cleanUp`** in BOT `action.lua`

Replace:

```lua
        elseif crop.isCrop and crop.name ~= 'air' then
            if scanner.isWeed(crop, 'working') then
                robot.swingDown()
            end
        end
```

with:

```lua
        elseif crop.isCrop and crop.name ~= 'air' then
            if badParent(crop) then
                robot.swingDown()
            end
        end
```

- [ ] **Step 6: Reset the rule in `initWork`** in BOT `action.lua`

Replace:

```lua
local function initWork()
    events.initEvents()
```

with:

```lua
local function initWork()
    badParent = defaultBadParent
    events.initEvents()
```

- [ ] **Step 7: Export the new functions** in BOT `action.lua`

Replace:

```lua
    clearDown = clearDown,
    analyzeStorage = analyzeStorage
}
```

with:

```lua
    clearDown = clearDown,
    analyzeStorage = analyzeStorage,
    findStorageSlot = findStorageSlot,
    transplantToStorage = transplantToStorage,
    readSeedChest = readSeedChest,
    plantFromChest = plantFromChest,
    setBadParentRule = setBadParentRule
}
```

- [ ] **Step 8: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: all pass (`Ran 22 tests` … `OK`)

- [ ] **Step 9: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add action.lua tests/test_action.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "fix: dumpInventory nil crash; add storage-safe moves, seed chest and planting helpers" -m "withSelectedSlot called dumpInventory before its local definition, so a full inventory crashed with a nil global call." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Existing programs stop overwriting the storage farm

**Files:**
- Modify: BOT `autoTier.lua:98-103`
- Modify: BOT `autoStat.lua:74-77`
- Modify: BOT `autoSpread.lua:49-52` and `:65-68`

- [ ] **Step 1: Edit BOT `autoTier.lua`**

Replace:

```lua
        -- Not seen before, move to storage
        else
            action.transplant(gps.workingSlotToPos(slot), gps.storageSlotToPos(database.nextStorageSlot()))
            action.placeCropStick(2)
            database.addToStorage(crop)
        end
```

with:

```lua
        -- Not seen before, move to storage
        elseif action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
            action.placeCropStick(2)
        end
```

- [ ] **Step 2: Edit BOT `autoStat.lua`**

Replace:

```lua
        elseif config.keepMutations and (not database.existInStorage(crop)) then
            action.transplant(gps.workingSlotToPos(slot), gps.storageSlotToPos(database.nextStorageSlot()))
            action.placeCropStick(2)
            database.addToStorage(crop)
```

with:

```lua
        elseif config.keepMutations and (not database.existInStorage(crop)) then
            if action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
                action.placeCropStick(2)
            end
```

- [ ] **Step 3: Edit BOT `autoSpread.lua`** — the `useStorageFarm` branch

Replace:

```lua
                if config.useStorageFarm then
                    action.transplant(gps.workingSlotToPos(slot), gps.storageSlotToPos(database.nextStorageSlot()))
                    database.addToStorage(crop)
                    action.placeCropStick(2)
```

with:

```lua
                if config.useStorageFarm then
                    if action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
                        action.placeCropStick(2)
                    end
```

- [ ] **Step 4: Edit BOT `autoSpread.lua`** — the `keepMutations` branch

Replace:

```lua
        elseif config.keepMutations and (not database.existInStorage(crop)) then
            action.transplant(gps.workingSlotToPos(slot), gps.storageSlotToPos(database.nextStorageSlot()))
            action.placeCropStick(2)
            database.addToStorage(crop)
```

with:

```lua
        elseif config.keepMutations and (not database.existInStorage(crop)) then
            if action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
                action.placeCropStick(2)
            end
```

- [ ] **Step 5: Confirm no program transplants into storage directly**

Run: `git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" grep -n "storageSlotToPos(database.nextStorageSlot())" -- autoTier.lua autoStat.lua autoSpread.lua`

Expected: no output. (`action.lua` still has one inside `transplant`'s non-crop fallback; that is expected.)

- [ ] **Step 6: Run all bot tests** (the syntax test covers the three files)

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add autoTier.lua autoStat.lua autoSpread.lua
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "fix: never overwrite crops already in the storage farm" -m "Each program reset its storage count on start, so its first storage move destroyed whatever was in slot 1. Storage moves now skip occupied slots." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `autoBreed.lua`

**Files:**
- Create: BOT `autoBreed.lua`
- Create: BOT `tests/test_autobreed.py`

- [ ] **Step 1: Write the failing smoke tests** in BOT `tests/test_autobreed.py`

```python
import unittest

from lua_env import REPO, runtime


def run_autobreed(*args, chest="", chest_size=27):
    lua = runtime(stubs=True)
    lua.execute("stub.chest = {%s}" % chest)
    if chest_size is None:
        lua.execute("stub.chestSize = nil")
    lines = []
    lua.globals().print = lambda *parts: lines.append(" ".join(str(p) for p in parts))
    source = (REPO / "autoBreed.lua").read_text(encoding="utf-8")
    run = lua.eval("function(src, ...) return assert(load(src, '=autoBreed'))(...) end")
    run(source, *args)
    return "\n".join(lines)


class AutoBreedCheckTest(unittest.TestCase):
    CHEST = ("[1]={label='Stagnium Seeds', size=4}, [2]={label='Nickelback Seeds', size=2},"
             " [5]={label='Unknown Seeds', size=1}")

    def test_check_reports_ranking_and_chest(self):
        out = run_autobreed("Bauxia", "--check", chest=self.CHEST)
        self.assertIn("Target Bauxia (tier 6)", out)
        best = next(line for line in out.splitlines() if "best parents:" in line)
        for name in ("Argentia", "Plumbilia", "Titania"):
            self.assertIn(name, best)
        seeds = next(line for line in out.splitlines() if "seed chest:" in line)
        self.assertIn("Stagnium", seeds)
        self.assertIn("(4)", seeds)
        self.assertIn("Nickelback", seeds)
        self.assertIn("(2)", seeds)
        self.assertIn("ignored:      Unknown Seeds", out)
        self.assertIn("free memory:  200 KB", out)
        self.assertIn("odds are estimates", out)

    def test_multi_word_names(self):
        out = run_autobreed("Salty", "Root", "--check")
        self.assertIn("Target Salty Root (tier 4)", out)

    def test_unknown_target_suggests_names(self):
        out = run_autobreed("bauxi", "--check")
        self.assertIn('Unknown crop "bauxi"', out)
        self.assertIn("Did you mean: Bauxia", out)

    def test_missing_seed_chest(self):
        out = run_autobreed("Bauxia", "--check", chest_size=None)
        self.assertIn("seed chest:   none found at {-3, 0}", out)

    def test_no_target_prints_usage(self):
        out = run_autobreed("--check")
        self.assertIn("Usage: autoBreed <crop name>", out)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_autobreed.py" -v`

Expected: FAIL with `FileNotFoundError` for `autoBreed.lua`

- [ ] **Step 3: Create BOT `autoBreed.lua`**

```lua
local action = require('action')
local breeding = require('breeding')
local computer = require('computer')
local config = require('config')
local database = require('database')
local events = require('events')
local gps = require('gps')
local policy = require('breedpolicy')
local scanner = require('scanner')
local args = {...}
local checkOnly = false
local info
local target
local targetKey
local chest = {}
local breedRound = 0
local captured = false
local lastChance

-- ===================== FUNCTIONS ======================

local function pct(value)
    return string.format('%.2f%%', value * 100)
end


local function isEmpty(crop)
    return crop.name == 'air' or crop.name == 'emptyCrop'
end


local function resolveTarget()
    local words = {}
    for _, word in ipairs(args) do
        if word == '--check' then
            checkOnly = true
        else
            words[#words+1] = word
        end
    end
    local text = table.concat(words, ' ')
    if text == '' then
        text = config.breedTarget or ''
    end
    if text == '' then
        print('Usage: autoBreed <crop name> [--check]  (or set breedTarget in config.lua)')
        return false
    end

    local ok, err = pcall(breeding.load)
    if not ok then
        print('autoBreed: could not load crops.lua (' .. tostring(err) .. '). Run setup again.')
        return false
    end
    local known, total = breeding.propertiesKnown()
    local record, suggestions = breeding.resolve(text)
    if not record then
        print(string.format('autoBreed: Unknown crop "%s"', text))
        if #suggestions > 0 then
            print('  Did you mean: ' .. table.concat(suggestions, ', '))
        end
        breeding.unload()
        return false
    end

    info = breeding.prepare(record)
    targetKey = record.n:lower()
    target = info[targetKey]
    breeding.unload()
    if known < total then
        print(string.format('autoBreed: hidden crop properties known for %d of %d crops, so odds are estimates', known, total))
    end
    return true
end


-- Reads the seed chest into `chest` (usable bags by crop key). Returns the
-- labels it ignored, or nil if there is no seed chest.
local function readChest()
    chest = {}
    local stacks = action.readSeedChest()
    if not stacks then
        return nil
    end
    local ignored, seen = {}, {}
    for _, stack in ipairs(stacks) do
        local key = breeding.labelToKey(stack.label)
        if key and key ~= targetKey and info[key].e > 0 then
            chest[key] = chest[key] or {count=0, stacks={}}
            chest[key].count = chest[key].count + stack.size
            table.insert(chest[key].stacks, {slot=stack.slot, size=stack.size})
        elseif not seen[stack.label] then
            seen[stack.label] = true
            ignored[#ignored+1] = stack.label
        end
    end
    return ignored
end


local function bestInChest()
    local bestKey, bestE = nil, 0
    for key, entry in pairs(chest) do
        if entry.count > 0 and info[key].e > bestE then
            bestKey, bestE = key, info[key].e
        end
    end
    return bestKey, bestE
end


local function report(ignored)
    print(string.format('autoBreed: Target %s (tier %d)', target.d, target.t))

    local best = {}
    for _, entry in ipairs(breeding.top(5)) do
        best[#best+1] = entry.d .. ' ' .. pct(entry.e)
    end
    print('  best parents: ' .. (#best > 0 and table.concat(best, ', ') or 'none share anything with it'))

    if ignored == nil then
        print(string.format('  seed chest:   none found at {%d, %d}', config.seedContainerPos[1], config.seedContainerPos[2]))
    else
        local have = {}
        for key, entry in pairs(chest) do
            have[#have+1] = string.format('%s %s (%d)', info[key].d, pct(info[key].e), entry.count)
        end
        print('  seed chest:   ' .. (#have > 0 and table.concat(have, ', ') or 'no usable seed bags'))
        for _, label in ipairs(ignored) do
            print('  ignored:      ' .. label)
        end
    end
    print(string.format('  free memory:  %d KB', computer.freeMemory() // 1024))
end


local function parentKeys()
    local keys = {}
    local farm = database.getFarm()
    for slot=1, config.workingFarmArea, 2 do
        local crop = farm[slot]
        if crop and crop.isCrop and not isEmpty(crop) then
            keys[#keys+1] = crop.name:lower()
        end
    end
    return keys
end


-- The parent slot with the lowest efficiency (empty = -1; ties: lowest slot).
local function worstParent()
    local farm = database.getFarm()
    local worst = {slot=nil, e=math.huge}
    for slot=1, config.workingFarmArea, 2 do
        local crop = farm[slot]
        if crop and crop.isCrop then
            local e = -1
            if not isEmpty(crop) then
                local entry = info[crop.name:lower()]
                e = entry and entry.e or 0
            end
            if e < worst.e then
                worst = {slot=slot, e=e}
            end
        end
    end
    return worst
end


-- At least two parents and one useful for the target, counting usable chest bags.
local function viable()
    local parents, useful = 0, 0
    for _, key in ipairs(parentKeys()) do
        parents = parents + 1
        if info[key] and info[key].e > 0 then
            useful = useful + 1
        end
    end
    for _, entry in pairs(chest) do
        parents = parents + entry.count
        useful = useful + entry.count
    end
    return parents >= 2 and useful >= 1
end


local function printChance()
    local chance = breeding.chance(parentKeys())
    if chance ~= lastChance then
        lastChance = chance
        print(string.format('autoBreed: %s %s per cross with current parents', target.d, pct(chance)))
    end
end


-- Plants the best seed bag from the chest into a parent slot. Returns true if planted.
local function plantBest(slot)
    local key = bestInChest()
    if not key then
        return false
    end
    local entry = chest[key]
    local stack = entry.stacks[#entry.stacks]
    local crop = action.plantFromChest(stack.slot, gps.workingSlotToPos(slot))
    if crop then
        database.updateFarm(slot, crop)
        stack.size = stack.size - 1
        entry.count = entry.count - 1
        if stack.size == 0 then
            table.remove(entry.stacks)
        end
        return true
    end
    print(string.format('autoBreed: could not plant %s from chest slot %d; skipping it', info[key].d, stack.slot))
    entry.count = entry.count - stack.size
    table.remove(entry.stacks)
    return false
end


local function capture(slot, crop, where)
    local stats = string.format('Gr %d, Ga %d, Re %d', crop.gr, crop.ga, crop.re)
    if where == 'captureSlot1' then
        action.transplant(gps.workingSlotToPos(slot), gps.workingSlotToPos(1))
        action.placeCropStick(2)
        database.updateFarm(1, crop)
        print(string.format('autoBreed: Captured %s (%s) into slot 1', target.d, stats))
    elseif action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
        action.placeCropStick(2)
        print(string.format('autoBreed: Captured %s (%s) into storage slot %d', target.d, stats, #database.getStorage()))
        print('  Its stats are above your working caps, so autoStat would treat it as a weed.')
    else
        print(string.format('autoBreed: Found %s (%s) but the storage farm is full; it is still on the working farm', target.d, stats))
    end
    captured = true
    computer.beep(1000, 1)
end


local function promote(slot, crop, worst)
    action.transplant(gps.workingSlotToPos(slot), gps.workingSlotToPos(worst.slot))
    action.placeCropStick(2)
    database.updateFarm(worst.slot, crop)
end


local function checkParent(slot, crop)
    local _, chestE = bestInChest()
    local todo = policy.parentAction(crop, {info=info, bestChestE=chestE})
    if todo == 'remove' then
        action.deweed()
        database.updateFarm(slot, {isCrop=true, name='emptyCrop'})
    elseif todo == 'plant' then
        plantBest(slot)
    elseif todo == 'replaceFromChest' then
        action.deweed()
        database.updateFarm(slot, {isCrop=true, name='emptyCrop'})
        plantBest(slot)
    end
end


local function checkChild(slot, crop)
    local worst = worstParent()
    local todo = policy.childAction(crop, {
        info = info,
        targetKey = targetKey,
        caps = {workingMaxGrowth=config.workingMaxGrowth, workingMaxResistance=config.workingMaxResistance},
        worstParent = worst,
        keepMutations = config.keepMutations,
        seenInStorage = function(name) return database.existInStorage({name=name}) end
    })

    if todo == 'stick' then
        action.placeCropStick(2)
    elseif todo == 'weed' or todo == 'destroy' then
        action.deweed()
        action.placeCropStick()
    elseif todo == 'captureSlot1' or todo == 'captureStorage' then
        capture(slot, crop, todo)
    elseif todo == 'promote' then
        promote(slot, crop, worst)
    elseif todo == 'store' then
        if action.transplantToStorage(gps.workingSlotToPos(slot), crop) then
            action.placeCropStick(2)
        end
    end
end


-- Plants the best chest bags: empty parent slots first, then worse parents.
local function fillParentsFromChest()
    for _, wantEmpty in ipairs({true, false}) do
        for slot=1, config.workingFarmArea, 2 do
            local crop = database.getFarm()[slot]
            if crop and crop.isCrop and isEmpty(crop) == wantEmpty then
                gps.go(gps.workingSlotToPos(slot))
                checkParent(slot, crop)
                if action.needCharge() then
                    action.charge()
                end
            end
        end
    end
end

-- ====================== THE LOOP ======================

local function breedOnce(firstRun)
    for slot=1, config.workingFarmArea, 1 do

        -- Terminal Conditions
        if captured then
            return false
        end
        if breedRound > config.maxBreedRound then
            print('autoBreed: Max Breeding Round Reached!')
            return false
        end
        if #database.getStorage() >= config.storageFarmArea then
            print('autoBreed: Storage Full!')
            return false
        end
        if events.needExit() then
            print('autoBreed: Received Exit Command!')
            return false
        end

        os.sleep(0)

        -- Scan
        gps.go(gps.workingSlotToPos(slot))
        local crop = scanner.scan()

        if firstRun or slot % 2 == 1 then
            database.updateFarm(slot, crop)
        end
        if not firstRun and crop.isCrop then
            if slot % 2 == 0 then
                checkChild(slot, crop)
            else
                checkParent(slot, crop)
            end
        end

        if action.needCharge() then
            action.charge()
        end
    end
    return true
end

-- ======================== MAIN ========================

local function stop(message)
    print(message)
    action.restockAll()
    events.unhookEvents()
end


local function main()
    if not resolveTarget() then
        return
    end

    if checkOnly then
        report(readChest())
        return
    end

    action.initWork()
    action.setBadParentRule(policy.isWeedLike)
    report(readChest())

    -- First Run
    breedOnce(true)
    for _, key in ipairs(parentKeys()) do
        if key == targetKey then
            stop(string.format('autoBreed: %s is already on the working farm; run autoStat instead', target.d))
            return
        end
    end
    fillParentsFromChest()
    if not viable() then
        stop(string.format('autoBreed: need at least two parents, one useful for %s', target.d))
        return
    end
    printChance()
    action.restockAll()

    -- Loop
    while breedOnce(false) do
        breedRound = breedRound + 1
        printChance()
        if not viable() then
            print(string.format('autoBreed: need at least two parents, one useful for %s', target.d))
            break
        end
        action.restockAll()
    end

    -- Terminated Early
    if events.needExit() then
        action.restockAll()
    end

    -- Finish
    if config.cleanUp then
        action.cleanUp()
    end

    events.unhookEvents()
    print('autoBreed: Complete!')
end

main()
```

- [ ] **Step 4: Run the smoke tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_autobreed.py" -v`

Expected: `Ran 5 tests` … `OK`

- [ ] **Step 5: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add autoBreed.lua tests/test_autobreed.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: add autoBreed program for targeted crop breeding" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Install list, fork URL, README

**Files:**
- Modify: BOT `setup.lua`
- Modify: BOT `uninstall.lua`
- Modify: BOT `README.md`

- [ ] **Step 1: Edit BOT `setup.lua`** — install the new files

Replace:

```lua
    'autoSpread.lua',
    'uninstall.lua'
}
```

with:

```lua
    'autoSpread.lua',
    'autoBreed.lua',
    'breeding.lua',
    'breedpolicy.lua',
    'crops.lua',
    'uninstall.lua'
}
```

- [ ] **Step 2: Edit BOT `setup.lua`** — default to the fork

Replace `    repo = 'https://raw.githubusercontent.com/DylanTaylor1/GTNH-CropAutomation/'` with:

```lua
    repo = 'https://raw.githubusercontent.com/Keegater/GTNH-CropAutomation/'
```

- [ ] **Step 3: Edit BOT `uninstall.lua`**

Replace:

```lua
    'autoSpread.lua',
    'uninstall.lua'
}
```

with:

```lua
    'autoSpread.lua',
    'autoBreed.lua',
    'breeding.lua',
    'breedpolicy.lua',
    'crops.lua',
    'uninstall.lua'
}
```

- [ ] **Step 4: Edit BOT `README.md`** — install line

Replace `        wget https://raw.githubusercontent.com/DylanTaylor1/GTNH-CropAutomation/main/setup.lua && setup` with:

```
        wget https://raw.githubusercontent.com/Keegater/GTNH-CropAutomation/main/setup.lua && setup
```

- [ ] **Step 5: Edit BOT `README.md`** — seed chest in the farm layout

Replace `Optionally, place a crop manager nearby (with harvesting disabled) to hydrate and/or fertilize the crops to help them grow faster.` with:

```
Optionally, place a crop manager nearby (with harvesting disabled) to hydrate and/or fertilize the crops to help them grow faster. autoBreed also needs a seed chest one block past the storage chest (`seedContainerPos` in the config); any chest works.
```

- [ ] **Step 6: Edit BOT `README.md`** — document autoBreed after autoSpread

Replace:

```
    autoSpread

(Optional) Disable useStorageFarm
```

with:

```
    autoSpread

The fourth program **autoBreed** breeds a crop you don't have yet. Put scanned seed bags of possible parents in the seed chest and name the crop you want:

    autoBreed Bauxia

It ranks every crop by how likely it is to produce your target as a parent (IC2's own crossbreeding formula), plants the best bags from the chest into the parent slots, and keeps breeding. Any child that would make a better parent replaces the worst one. When the target appears it is moved into slot 1, or into the storage farm if its stats are above your working caps, and the program stops. Chain it like the others:

    autoBreed Bauxia && autoStat && autoSpread

Add `--check` to print the ranking and what the robot reads in the seed chest without touching the farm. Names are case-insensitive and multi-word names work (`autoBreed Salty Root`). Seed bags must be scanned; "Unknown Seeds" are ignored. Parents removed to make room for better ones go to the storage chest, so make it a real chest if you want them back.

(Optional) Disable useStorageFarm
```

- [ ] **Step 7: Edit BOT `README.md`** — the storage farm is no longer overwritten

Replace `Note that keepMutations in the config should probably be set to false (default) otherwise the storage farm will be overwritten once the second program begins.` with:

```
Crops already on the storage farm are never overwritten: every program skips occupied storage slots, so the storage farm keeps filling across runs until you empty it.
```

- [ ] **Step 8: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`

- [ ] **Step 9: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add setup.lua uninstall.lua README.md
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "docs: document autoBreed; install from the Keegater fork" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Deploy and check in game

- [ ] **Step 1: Add the fork as a remote** (local only)

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" remote add fork https://github.com/Keegater/GTNH-CropAutomation.git
```

- [ ] **Step 2: Push, with the user's OK.** Ask the user before pushing. They may prefer to run it themselves:

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" push -u fork autobreed
```

- [ ] **Step 3: User, in game — place the seed chest** one block past the storage chest in the chest row: charger (0,0) → crop-stick chest (-1,0) → storage chest (-2,0) → **seed chest (-3,0)**. Put the **scanned** Stagnium and Nickelback seed bags in it.

- [ ] **Step 4: User, in game — install on the robot and reboot** (the reboot clears OpenOS's cached copies of the old files):

```
wget -f https://raw.githubusercontent.com/Keegater/GTNH-CropAutomation/autobreed/setup.lua && setup autobreed
reboot
```

- [ ] **Step 5: User, in game — dry run**

```
autoBreed Bauxia --check
```

Expected:
- a "Target Bauxia (tier 6)" line;
- a "best parents" line listing Argentia, Plumbilia and Titania;
- a "seed chest" line listing Stagnium and Nickelback with their counts;
- a free-memory line.

If your bags show up under "ignored:", report the exact label shown.

- [ ] **Step 6: User, in game — planting check.** Leave the working farm with at least two empty parent slots and run `autoBreed Bauxia`. Watch it fly to the seed chest and plant, then press **Q** once both are planted. Check the new crops with WAILA or a Cropnalyzer.

- [ ] **Step 7: User, in game — real run**

```
autoBreed Bauxia && autoStat && autoSpread
```

If anything errors, capture it with `autoBreed Bauxia 2>/errors.log`, then `edit /errors.log`, and paste it back.

- [ ] **Step 8 (after it works): merge into the fork's main**, so the README's plain `setup` works

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" switch main
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" merge autobreed
```

Push `main` to `fork` only with the user's OK.
