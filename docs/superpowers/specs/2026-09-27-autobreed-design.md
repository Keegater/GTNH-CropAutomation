# autoBreed — targeted crop breeding for GTNH-CropAutomation

- **Date:** 2026-09-27
- **Status:** design approved in conversation; this written spec awaits review
- **Pack:** GTNH 2.8.4 — IC2 2.2.828-experimental, GregTech 5.09.51.482, OpenComputers 1.11.20-GTNH
- **Base:** DylanTaylor1/GTNH-CropAutomation @ `a7102b0`, branch `autobreed`

## 1. Goal

Add a fourth program, `autoBreed`, that breeds a chosen **target crop**: it plants the best available parents from a seed chest, grinds crossbreeding on the working farm, swaps in better parents as they appear, and captures the target so `autoStat`/`autoSpread` can continue. Changing target is one argument (`autoBreed Bauxia`) — no code changes. First target: **Bauxia**, with **Stagnium** and **Nickelback** seeds on hand.

## 2. Non-goals

- Planning multi-step chains (automatically breeding intermediate crops to reach a target). Better parents are picked up opportunistically (§6.4) but never planned.
- Obtaining parent species the player has not supplied.
- Reading seed-bag stats before planting. OC exposes no item NBT by default; stats are read by the geolyzer after planting.
- Fixing unrelated existing issues: `checkStorageBefore` + `autoSpread` wiping non-target storage crops, and `autoStat` having no round limit.

## 3. Verified facts

Read from the bytecode of the pack's own jars with `javap`, plus a scan of all 232 mod jars for patches.

### 3.1 Species weight — `TileEntityCrop.calculateRatioFor(X, p)` (IC2)

For candidate species `X` and participating parent `p`:

```
if X == p: return 500
v = Σ_{i=0..4} (2 − |X.stat(i) − p.stat(i)|)          -- the 5 hidden crop properties
v += 5 × #{(a, b) : a ∈ X.attributes, b ∈ p.attributes, a == b ignoring case}
d = X.tier − p.tier
if d > 1:  v −= 2·d
if d < −3: v −= −d
return max(v, 0)
```

Attribute pairs are counted over the raw arrays, so duplicated attributes count again (Bauxia lists Aluminium twice).

### 3.2 Crossing — `attemptCrossing`, `askCropJoinCross` (IC2)

- On a cross stick's crop tick, a cross is attempted with probability 1/3.
- **Participation:** each of the 4 neighbours joins if its crop's `canGrow(crossStick)` and `canCross(neighbour)` are true and `base ≥ random(20)`, where `base = 4`, +1 at Gr ≥ 16, +1 at Gr ≥ 30, and `+ (27 − Re)` when Re ≥ 28. At least 2 participants are required.
- **Species pick:** over every registered crop `X` with `X.canGrow(crossStick)`, IC2 sums `ratio(X, p)` across the participants and picks `X` proportionally to that sum.
- **Child stats:** participants' mean Gr/Ga/Re, each `+ random(1 + 2n) − n`, clamped to 0..31; size 1.
- No other mod patches these methods. The only other reference is the IC2 Crop Plugin's read-only prediction GUI (`GuiBreeding`, `prediction/BreedTask`).

### 3.3 GregTech crops (`gregtech.api.util.GTBaseCrop`)

- `canCross(tile)`: `size + 2 > maxSize` — GT crops cross one stage before maturity.
- `canGrow(tile)`: the block-below check applies only at `size == maxSize − 1`; otherwise `size < maxSize`. A fresh cross stick (size 0) therefore accepts Bauxia as a candidate. Bauxia needs Aluminium Ore or a GT Aluminium Block only to reach its final stage, so it can be bred and spread without one.

### 3.4 OpenComputers and IC2 items

- The geolyzer's `crop:name` is `CropCard.name()` — the **internal name** (the wiki's "Internal Name" column).
- Available keys: `crop:name, tier, growth, gain, resistance, size, maxSize, nutrients, humidity, air, hydration, fertilizer, weedex, roots`. No attributes or properties, so the robot needs its own crop table.
- Seed-bag display name: `"<displayName> Seeds"` when scanned (lang `crop.seeds = %1$s Seeds`), `"Unknown Seeds"` when unscanned, `"Invalid Seeds"` when invalid.

### 3.5 Consequence used throughout

For the set `P` of participating parents:

```
P(target) = Σ_{p∈P} ratio(T, p) / Σ_{p∈P} W(p),   W(p) = Σ_X ratio(X, p)   (includes the 500 for X = p)
```

`W(p)` does not depend on the target, so it can be precomputed. Define the **efficiency** `e(p) = ratio(T, p) / W(p)`. Then `P(target) ≤ max e(p)`: filling every parent slot with the highest-`e` species maximizes the per-cross chance, and where parents sit does not matter.

**Assumption:** every registered crop is a candidate at a fresh cross stick (`canGrow` true at size 0). The generator checks each crop class and flags exceptions (§5.1).

## 4. Architecture

```
PC (advisor project)                          Robot (bot repo, branch autobreed)
scripts/build_crop_table.py  ── writes ──►   crops.lua        generated crop table
  • wiki API: names, tier, attributes          breeding.lua     crop math + name lookup (pure Lua)
  • pack jars (javap): properties              breedpolicy.lua  decision rules (pure Lua)
  • computes W(p)                              autoBreed.lua    the program (OC glue)
                                               action.lua       + seed-chest and storage helpers, fixes
                                               scanner.lua      + isWeedLike
                                               config.lua       + breedTarget, seedContainerPos
                                               setup.lua, uninstall.lua, README.md
```

`breeding.lua` and `breedpolicy.lua` make no OC calls, so they are unit-tested on the PC.

## 5. Components

### 5.1 `scripts/build_crop_table.py` (advisor project)

- **Inputs:**
  - Wiki page "IC2 Crops List" via `fetch_wiki.api_get`: display name, internal name, tier, attributes.
  - The pack's `mods/` folder via `javap`: each crop's 5 properties (`stat(i)`), and tier/attributes where extractable. Families: IC2 (`ic2.core.crop.*`), GregTech (`GTBaseCrop` instances), GT++ (`gtPlusPlus...bartcrops`), Crops++ (`CropsPP`), GoodGenerator (Salty Root).
- **Rules:**
  - Jar data wins over the wiki; tier or attribute mismatches are printed.
  - A crop whose properties cannot be extracted gets `s = nil`, and its numeric term is 0 in both the generator and the Lua code. Such crops are listed in the summary — never filled in silently.
  - Each crop's `canGrow` is checked at size 0; crops with extra conditions are listed (the §3.5 assumption).
- **Output:** `CropBot/GTNH-CropAutomation/crops.lua`, plus a printed summary: crop count, missing properties, mismatches, `canGrow` exceptions.

`crops.lua` format — short keys to save robot memory; the `<…>` fields are filled in by the generator:

```lua
-- Generated by build_crop_table.py on <date> from wiki rev <revid> and <jar list>. Do not edit.
return {
  {n='Bauxia', d='Bauxia', t=6, a={'Metal','Aluminium','Reed','Aluminium'}, s={<5 integers>}, w=<W>},
  -- one entry per crop
}
```

`n` internal name, `d` display name, `t` tier, `a` attributes, `s` properties (or nil), `w` = `W(p)`.

### 5.2 `breeding.lua` (pure Lua 5.3)

- `load([path])` — loads `crops.lua`; builds lowercase indexes by internal name and by display name.
- `ratio(x, p)` — exactly §3.1.
- `efficiency(target, p)` — `ratio(target, p) / p.w`.
- `resolve(text)` — case-insensitive exact match on internal name, then display name; otherwise returns nil plus up to 5 substring suggestions.
- `speciesFromLabel(label)` — strips a trailing `" Seeds"` and looks up the display name; returns nil for `Unknown`, `Invalid`, unrecognised labels, and non-seed items.
- `chance(target, parents)` — `Σ ratio / Σ w` over a list of parent crops; 0 for an empty list.

### 5.3 `breedpolicy.lua` (pure Lua 5.3)

Decision functions return action codes. Context:

```
ctx = { target, eff = {name → e}, caps = {workingMaxGrowth, workingMaxResistance},
        worstParent = {slot, e}, bestChestE, keepMutations, seenInStorage(name) }
```

`worstParent` is the parent slot with the lowest `e`; an empty parent slot counts as `e = −1`; ties go to the lowest slot number.

`parentAction(crop, ctx)`:

| Condition | Action |
|---|---|
| weed-like (§5.5) | `'remove'` |
| empty slot and `bestChestE > 0` | `'plant'` |
| empty slot, nothing usable in the chest | `'wait'` (left empty for a promoted child) |
| `bestChestE > e(parent)` | `'replaceFromChest'` |
| otherwise | `'keep'` |

`childAction(crop, ctx)`, first match wins:

| # | Condition | Action |
|---|---|---|
| 1 | air | `'stick'` (place double sticks) |
| 2 | weed-like | `'weed'` (remove, re-stick) |
| 3 | target, Gr ≤ `workingMaxGrowth` and Re ≤ `workingMaxResistance` | `'captureSlot1'` (replaces the parent in slot 1) |
| 4 | target, outside those caps | `'captureStorage'` |
| 5 | `e(child) > worstParent.e` (ties do not swap) | `'promote'` (into `worstParent.slot`) |
| 6 | `keepMutations` and species new to storage | `'store'` |
| 7 | otherwise | `'destroy'` |

### 5.4 `autoBreed.lua` (OC program)

**Usage:** `autoBreed <target words...> [--check]`. The words are joined with spaces (`autoBreed Salty Root`). With no words, `config.breedTarget` is used.

**Startup:**

1. Resolve the target; if unknown, print the suggestions and exit.
2. Load the crop table, compute `e(p)` for every species, keep the `name → e` map, release the rest.
3. Print the report: target and tier; the top 5 species by `e` (shown as % per cross if every parent were that species); the species found in the seed chest with counts and `e`; free memory.
4. `--check` stops here. The robot flies to the seed chest to read it and returns to the charger; nothing on the farm or in any inventory changes.
5. `action.initWork()`, then the first scan pass of the working farm.
6. If any parent already is the target, report it and exit (suggest `autoStat`).
7. Plant from the seed chest: empty parent slots first, then parents whose `e` is below the best available bag. Best species first; only species with `e > 0`.
8. **Viability** — checked here and after every pass: at least 2 parents in total and at least 1 with `e > 0`, counting bags still usable from the seed chest. Otherwise report "need at least two parents, one useful for <target>" and exit.
9. Print `"<target>: x.xx% per cross with current parents"`.

**Main loop:** the same slot-by-slot pass as the other programs. Odd slots go through `parentAction`, even slots through `childAction`, and each action is executed via `action.lua`. The per-cross chance is reprinted whenever the set of parents changes.

**Terminal conditions:**

- target captured;
- `maxBreedRound` reached;
- Q or C pressed;
- storage full (only with `keepMutations`);
- no longer viable (startup step 8).

**On capture:** print where the target went and its stats, beep, run cleanup that keeps parents unless weed-like, then `restockAll`.

### 5.5 `scanner.lua`

Add `isWeedLike(crop)`: name `weed` or `Grass`, or Gr ≥ 24, or `venomilia` with Gr > 7. The existing `isWeed` is unchanged and still used by the other programs.

### 5.6 `action.lua`

- **Fix:** add `dumpInventory` to the forward declaration on line 13 and define it as `function dumpInventory() … end` (assigning the forward-declared local). This fixes the nil-call crash when the inventory fills mid-pass.
- **New `transplantToStorage(src)`:**
  - Starting at `database.nextStorageSlot()`, scans each storage slot.
  - An occupied slot (any crop other than `air`/`emptyCrop`, or a non-crop block) is recorded with `database.addToStorage` and skipped.
  - Transplants into the first free slot and records it; returns `false` if the storage farm is full.
  - Replaces the direct storage transplants in `autoTier`, `autoStat` and `autoSpread`, and is used by `autoBreed`.
- **New `readSeedChest()`:** goes to `config.seedContainerPos` and returns `{slot, label, size, species}` per stack, or nil if there is no inventory there.
- **New `plantFromChest(chestSlot, pos)`:**
  1. Pulls 1 bag into a free robot slot and goes to `pos`.
  2. Places a single stick if the slot is air.
  3. Equips the bag, `useDown`, unequips, and scans.
  4. If the scan does not show the expected species, returns the bag to the seed chest and reports failure.
- **`cleanUp(isBadParent)`:** optional predicate. The default is `scanner.isWeed(crop, 'working')`, so existing behaviour is unchanged; `autoBreed` passes `scanner.isWeedLike`.

### 5.7 `config.lua`

- Add `breedTarget = nil` (default target when no argument is given).
- Add `seedContainerPos = {-3, 0}` (seed chest, one past the storage chest in the chest row, outside the farm).
- Settings this fork carries for the user: `workingMaxResistance = 6`, `storageMaxResistance = 6`, `autoStatThreshold = 46`, `autoSpreadThreshold = 44`.

### 5.8 `setup.lua`, `uninstall.lua`, `README.md`

- Add `crops.lua`, `breeding.lua`, `breedpolicy.lua`, `autoBreed.lua` to both file lists.
- README gains an autoBreed section: usage, seed chest, `--check`, chaining, scanned bags required. It also notes that the storage farm now fills across runs instead of being overwritten.

## 6. Behaviour notes

1. **Why fill with the best species:** see §3.5. Mixing in a worse species can only lower the per-cross chance, except where it is needed to reach 2 participants — which the viability rule allows.
2. **Removed parents:** their seed bags go to the storage chest with the robot's other drops. The README tells users to make it a real chest if they want them back.
3. **Planting failures:** a double stick or missing farmland returns the bag to the chest and skips the slot for that pass.
4. **Opportunistic upgrades:** a child whose species has a higher `e` than the worst parent (Argentia or Plumbilia for Bauxia) replaces that parent. Children of the best species fill empty slots the same way.

## 7. Testing

**PC:** Python `unittest`, plus the `lupa` package to run Lua 5.3 (installing `lupa` requires the user's OK).

1. **Formula:** hand-worked cases from §3.1 — same species (500), case-insensitive and duplicated attributes, tier-gap boundaries `d = 1, 2, −3, −4`, clamping at 0 — against both the Python and the Lua implementation.
2. **Cross-implementation:** for targets Bauxia, Titania, Salty Root, Stickreed and Diareed, Lua `e(p)` equals Python `e(p)` for every `p` within 1e-12.
3. **Generator:** `crops.lua` loads in Lua; every crop has a tier and attributes; spot values match the bytecode (Bauxia: tier 6, `Metal, Aluminium, Reed, Aluminium`).
4. **Labels:** `"Stagnium Seeds"` → Stagnium; `"Salty Root Seeds"` → Salty Root; `"Unknown Seeds"` → nil; an unknown label → nil.
5. **Policy:** table-driven cases for every row of the `parentAction` and `childAction` tables, including ties and the capture-caps boundary.

**In-game checklist, in order:**

1. `autoBreed Bauxia --check` prints the ranking, the seed-chest contents and free memory, and changes nothing.
2. One empty parent slot plus one scanned bag in the chest: it plants the bag and reads back the right species.
3. The real run.

## 8. Deployment

1. Work is committed on branch `autobreed` in `CropBot/GTNH-CropAutomation`. The generator lives in the advisor project's `scripts/`.
2. The user forks `DylanTaylor1/GTNH-CropAutomation` on GitHub, adds the fork as a remote, and pushes `autobreed`.
3. Robot install, with the user's GitHub username in place of `<user>`:

   ```
   wget -f https://raw.githubusercontent.com/<user>/GTNH-CropAutomation/autobreed/setup.lua && setup autobreed https://raw.githubusercontent.com/<user>/GTNH-CropAutomation/
   ```

## 9. Risks

| Risk | Mitigation |
|---|---|
| Property extraction coverage across five mod families | Per-crop fallback plus an explicit report (§5.1) |
| The candidate assumption (§3.5) | Generator flags crops with extra `canGrow` conditions |
| Robot memory on Tier 2 RAM (crop table ≈ 15 KB on disk) | Keep only the `name → e` map after ranking; `--check` reports free memory |
| A language pack renaming seed bags | In-game check 1 prints the raw labels |
