# autoBreed Implementation Plan (Plan 2 of 2): hidden crop properties

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put IC2's five hidden crop properties into `crops.lua` so `autoBreed` ranks parents correctly. For Fertilia, for example, the IC2 flowers turn out to be useless and Zomplant a real parent. This plan also fixes the capture bug that destroys a target found while the storage farm is full.

**Architecture:**
- `scripts/crop_bytecode.py` runs `javap` on the pack's IC2 and GregTech jars and evaluates the methods that define each crop with a tiny interpreter. Only the instructions those methods use are supported; anything else means "properties unknown".
- `build_crop_table.py` merges those records into the wiki data. The jar wins for tier and attributes.
- The robot marks any value that still depends on an unknown crop with `~`.
- `autoBreed` leaves a target it can't store on the farm and ends the `&&` chain.

**Tech Stack:** Python 3.14 + `unittest`, `javap` from any installed JDK, Lua 5.3 (`lupa` in tests).

**Spec:** `docs/superpowers/specs/2026-09-27-autobreed-design.md` (§5.1 jar extraction; §5.4 capture)

**Scope:** IC2 and GregTech crops only (84 of 161). Crops++, GT++ and GoodGenerator need branches and loops in the interpreter and come later; they stay "unknown" (`~`).

## Verified facts this plan relies on

Checked against the real jars on 2026-09-30:

- **The instructions used** by GregTech's `CropLoader.run()`, IC2's `IC2Crops` `<clinit>` and `init()`, and every IC2 crop's constructor, `name`, `tier`, `stat` and `attributes`:
  - constants, locals, `dup`/`pop`, arrays, fields, `new`, `invoke*`, `checkcast`, `goto`, `tableswitch`, returns;
  - no conditional branches.
- **Prototype results:** 84 crops read in under 1 s:
  - Stagnium `[2,0,0,1,0]`, IC2 flowers `[1,1,0,5,1]`, weed `[0,0,1,0,5]` (built in `IC2Crops.init()`);
  - Bauxia `[5,0,2,3,3]`, Fertilia `[2,3,5,4,8]`, Zomplant `[1,3,4,2,6]`.
- **Mushrooms:** GregTech also registers "Brown Mushrooms" and "Red Mushrooms". The wiki's IC2 table gives IC2's `brownMushroom`/`redMushroom` those same names.
  - Plan 1 renamed the rows in *both* tables, so the GregTech mushrooms were dropped as duplicates.
  - The rename must apply to the IC2 table only.
  - With that fix: 161 crops, all 84 jar crops matched, no tier or attribute mismatches.
- **`javap` location:** the JDK 17 that was on PATH is gone; JDK 21 and 24 remain under `C:\Program Files\Java`. So `javap` has to be discovered, not hard-coded.
- **OpenOS `&&`:** runs the next command only when the exit code is 0. `os.exit(code)` raises `{reason="terminated", code=code}` (from `lib/core/full_filesystem.lua` and `full_sh.lua`).

## Paths

- **ADV** = `C:\Users\loope\Desktop\GTNH 2.8.4 Agent` (not a git repo)
- **BOT** = `C:\Users\loope\Desktop\GTNH 2.8.4 Agent\CropBot\GTNH-CropAutomation` (branch `autobreed`, remote `fork`)
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1: `crop_bytecode.py` — javap parser, interpreter, extraction

**Files:**
- Create: ADV `scripts/crop_bytecode.py`
- Create: ADV `tests/test_crop_bytecode.py`

- [ ] **Step 1: Write the failing tests** in ADV `tests/test_crop_bytecode.py`

```python
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import crop_bytecode as cb  # noqa: E402

SAMPLE = """Compiled from "Base.java"
public abstract class demo.Base extends ic2.api.crops.CropCard {
  public demo.Base();
    descriptor: ()V
    Code:
       0: aload_0
       1: invokespecial #1                  // Method ic2/api/crops/CropCard."<init>":()V
       4: return

  public int tier();
    descriptor: ()I
    Code:
       0: iconst_2
       1: ireturn
}
Compiled from "Flower.java"
public class demo.Flower extends demo.Base {
  private final java.lang.String name;
    descriptor: Ljava/lang/String;

  public demo.Flower(java.lang.String);
    descriptor: (Ljava/lang/String;)V
    Code:
       0: aload_0
       1: invokespecial #2                  // Method demo/Base."<init>":()V
       4: aload_0
       5: aload_1
       6: putfield      #3                  // Field name:Ljava/lang/String;
       9: return

  public java.lang.String name();
    descriptor: ()Ljava/lang/String;
    Code:
       0: aload_0
       1: getfield      #3                  // Field name:Ljava/lang/String;
       4: areturn

  public int stat(int);
    descriptor: (I)I
    Code:
       0: iload_1
       1: tableswitch   { // 0 to 1
                     0: 24
                     1: 26
               default: 29
          }
      24: iconst_2
      25: ireturn
      26: bipush        7
      28: ireturn
      29: iconst_0
      30: ireturn

  public java.lang.String[] attributes();
    descriptor: ()[Ljava/lang/String;
    Code:
       0: iconst_2
       1: anewarray     #4                  // class java/lang/String
       4: dup
       5: iconst_0
       6: ldc           #5                  // String Red
       8: aastore
       9: dup
      10: iconst_1
      11: ldc           #6                  // String Flower
      13: aastore
      14: areturn
}
Compiled from "Registry.java"
public class demo.Registry {
  static {};
    descriptor: ()V
    Code:
       0: new           #7                  // class demo/Flower
       3: dup
       4: ldc           #8                  // String rose
       6: invokespecial #9                  // Method demo/Flower."<init>":(Ljava/lang/String;)V
       9: putstatic     #10                 // Field rose:Ldemo/Flower;
      12: getstatic     #11                 // Field other/Mod.instance:Lother/Mod;
      15: ldc           #12                 // String ignored
      17: invokevirtual #13                 // Method other/Mod.lookup:(Ljava/lang/String;)Ljava/lang/Object;
      20: pop
      21: goto          25
      24: athrow
      25: return
}
"""

GT_SAMPLE = """Compiled from "CropLoader.java"
public class gregtech.loaders.postload.CropLoader {
  public void run();
    descriptor: ()V
    Code:
       0: new           #1                  // class gregtech/api/util/GTBaseCrop
       3: dup
       4: sipush        154
       7: ldc           #2                  // String Bauxia
       9: ldc           #3                  // String unknown
      11: aconst_null
      12: bipush        6
      14: iconst_3
      15: iconst_0
      16: iconst_2
      17: iconst_3
      18: iconst_5
      19: iconst_0
      20: iconst_2
      21: iconst_3
      22: iconst_3
      23: iconst_2
      24: anewarray     #4                  // class java/lang/String
      27: dup
      28: iconst_0
      29: ldc           #5                  // String Metal
      31: aastore
      32: dup
      33: iconst_1
      34: ldc           #6                  // String Reed
      36: aastore
      37: getstatic     #7                  // Field gregtech/api/enums/Materials.Aluminium:Lgregtech/api/enums/Materials;
      40: getstatic     #8                  // Field gregtech/api/enums/ItemList.Crop_Drop_Bauxite:Lgregtech/api/enums/ItemList;
      43: lconst_1
      44: iconst_0
      45: anewarray     #9                  // class java/lang/Object
      48: invokevirtual #10                 // Method gregtech/api/enums/ItemList.get:(J[Ljava/lang/Object;)Lnet/minecraft/item/ItemStack;
      51: aconst_null
      52: ldc           #11                 // String gt.crop.bauxia.name
      54: invokespecial #12                 // Method gregtech/api/util/GTBaseCrop."<init>":(ILjava/lang/String;Ljava/lang/String;Lnet/minecraft/item/ItemStack;IIIIIIIIII[Ljava/lang/String;Lgregtech/api/enums/Materials;Lnet/minecraft/item/ItemStack;[Lnet/minecraft/item/ItemStack;Ljava/lang/String;)V
      57: pop
      58: return
}
"""


class ParseJavapTest(unittest.TestCase):
    def test_classes_methods_and_switch_tables(self):
        classes = cb.parse_javap(SAMPLE)
        self.assertEqual(sorted(classes), ["demo/Base", "demo/Flower", "demo/Registry"])
        self.assertEqual(classes["demo/Base"]["super"], "ic2/api/crops/CropCard")
        self.assertEqual(sorted(classes["demo/Flower"]["methods"]),
                         [("<init>", "(Ljava/lang/String;)V"), ("attributes", "()[Ljava/lang/String;"),
                          ("name", "()Ljava/lang/String;"), ("stat", "(I)I")])
        switch = classes["demo/Flower"]["methods"][("stat", "(I)I")][1]
        self.assertEqual(switch[1], "tableswitch")
        self.assertEqual(switch[4], {"0": 24, "1": 26, "default": 29})
        self.assertIn(("<clinit>", "()V"), classes["demo/Registry"]["methods"])


class InterpreterTest(unittest.TestCase):
    def test_registry_builds_crops_and_accessors_evaluate(self):
        classes = cb.parse_javap(SAMPLE)
        self.assertEqual(cb.ic2_crops(classes, registry="demo/Registry"),
                         [{"n": "rose", "t": 2, "s": [2, 7, 0, 0, 0], "a": ["Red", "Flower"]}])

    def test_unknown_instructions_raise(self):
        with self.assertRaises(cb.Unsupported):
            cb.Interpreter({}).run([(0, "athrow", "", "", None)], [])

    def test_gregtech_constructor_arguments(self):
        self.assertEqual(cb.gregtech_crops(cb.parse_javap(GT_SAMPLE)),
                         [{"n": "Bauxia", "t": 6, "s": [5, 0, 2, 3, 3], "a": ["Metal", "Reed"]}])


MODS = (Path(os.environ.get("APPDATA", "")) / "PrismLauncher" / "instances"
        / "GT_New_Horizons_2.8.4_Java_17-25" / ".minecraft" / "mods")


@unittest.skipUnless(MODS.exists() and cb.find_javap(), "needs the GTNH 2.8.4 install and a JDK")
class RealJarsTest(unittest.TestCase):
    def test_known_crops(self):
        by = {c["n"]: c for c in cb.extract(MODS, cb.find_javap())}
        self.assertEqual(len(by), 84)
        self.assertEqual(by["stagnium"], {"n": "stagnium", "t": 6, "s": [2, 0, 0, 1, 0],
                                          "a": ["Shiny", "Leaves", "Metal"]})
        self.assertEqual(by["dandelion"]["s"], [1, 1, 0, 5, 1])
        self.assertEqual(by["weed"]["s"], [0, 0, 1, 0, 5])
        self.assertEqual(by["Bauxia"]["s"], [5, 0, 2, 3, 3])
        self.assertEqual(by["Fertilia"]["s"], [2, 3, 5, 4, 8])
        self.assertEqual(by["Zomplant"]["s"], [1, 3, 4, 2, 6])
        self.assertIn("brownMushroom", by)
        self.assertIn("Brown Mushrooms", by)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -p "test_crop_bytecode.py" -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'crop_bytecode'`

- [ ] **Step 3: Create ADV `scripts/crop_bytecode.py`**

```python
"""Read IC2 crop data (name, tier, the five hidden properties, attributes) from
the pack's jars.

GTNH has no data file for the hidden properties, so this runs `javap` on the
crop classes and evaluates the few methods that define them with a tiny
interpreter. It understands only the instructions those methods use; anything
else raises Unsupported, and the crop is left as "properties unknown".

Covered: IC2 (crops built in ic2.core.crop.IC2Crops) and GregTech (GTBaseCrop
instances built in gregtech.loaders.postload.CropLoader).
"""
import os
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

CROP_CARD = "ic2/api/crops/CropCard"
GT_BASE_CROP = "gregtech/api/util/GTBaseCrop"
GT_LOADER = "gregtech/loaders/postload/CropLoader"
IC2_REGISTRY = "ic2/core/crop/IC2Crops"


class Unsupported(Exception):
    """The interpreter met an instruction or value it cannot evaluate."""


class Opaque:
    """A value the interpreter cannot know (world state, other mods' objects)."""


class Obj:
    def __init__(self, cls):
        self.cls = cls
        self.fields = {}


# ---------------------------------------------------------------- javap text

CLASS_RE = re.compile(r"^[\w ]*?\b(?:class|interface|enum) ([\w.$]+)(?: extends ([\w.$]+))?")
INS_RE = re.compile(r"^\s+(\d+): (\w+)(.*)$")
CASE_RE = re.compile(r"^\s+(-?\d+|default): (\d+)$")


def parse_javap(text):
    """Parse `javap -c -p -s -constants` output.

    Returns {class: {"super": name, "methods": {(name, descriptor): code}}}, where
    code is a list of (offset, opcode, operand, comment, switch_table).
    Class names use slashes, as in the bytecode.
    """
    classes, cls_name, pending, code, switch = {}, None, None, None, None
    for line in text.splitlines():
        if not line.startswith(" "):
            m = CLASS_RE.match(line)
            if m:
                cls_name = m.group(1).replace(".", "/")
                parent = (m.group(2) or "java.lang.Object").replace(".", "/")
                classes[cls_name] = {"super": parent, "methods": {}}
            continue
        if cls_name is None:
            continue
        if not line.startswith("   "):          # member header: exactly two spaces
            header = line.strip()
            if header == "static {};":
                pending = "<clinit>"
            elif "(" in header:
                simple = header.split("(")[0].split()[-1]
                pending = "<init>" if simple.replace(".", "/") == cls_name else simple.split(".")[-1]
            else:
                pending = None
            code = None
            continue
        if line.startswith("    descriptor: "):
            if pending:
                code = classes[cls_name]["methods"][(pending, line.split(":", 1)[1].strip())] = []
            continue
        if code is None:
            continue
        if switch is not None:
            m = CASE_RE.match(line)
            if m:
                switch[m.group(1)] = int(m.group(2))
            elif line.strip() == "}":
                switch = None
            continue
        if line.strip().startswith("Exception table:"):
            code = None
            continue
        m = INS_RE.match(line)
        if m:
            operand, _, comment = m.group(3).partition("//")
            table = {} if m.group(2) in ("tableswitch", "lookupswitch") else None
            code.append((int(m.group(1)), m.group(2), operand.strip(), comment.strip(), table))
            if table is not None:
                switch = table
    return classes


def parse_ref(comment):
    """'Method owner/Cls."<init>":(I)V' -> ('owner/Cls', '<init>', '(I)V'); owner is None if omitted."""
    _, _, rest = comment.partition(" ")
    target, _, desc = rest.rpartition(":")
    owner, _, name = target.rpartition(".")
    return owner.strip('"') or None, name.strip('"'), desc


def arg_count(desc):
    return len(re.findall(r"\[*(?:[BCDFIJSZ]|L[^;]+;)", desc[1:desc.index(")")]))


def ldc_value(comment):
    kind, _, text = comment.partition(" ")
    if kind == "String":
        return text
    if kind == "int":
        return int(text)
    return Opaque()


# --------------------------------------------------------------- interpreter

class Interpreter:
    def __init__(self, classes, on_new=None, max_steps=500000):
        self.classes = classes
        self.on_new = on_new        # on_new(owner, args) -> True to skip running that constructor
        self.created = []           # crop objects whose constructor ran, in creation order
        self.max_steps = max_steps

    def find(self, cls, key):
        while cls in self.classes:
            code = self.classes[cls]["methods"].get(key)
            if code is not None:
                return code
            cls = self.classes[cls]["super"]
        return None

    def is_subclass(self, cls, parent):
        while cls in self.classes and cls != parent:
            cls = self.classes[cls]["super"]
        return cls == parent

    def call(self, obj, name, desc, args=()):
        code = self.find(obj.cls, (name, desc))
        if code is None:
            raise Unsupported(f"{obj.cls}.{name}{desc} not found")
        return self.run(code, [obj, *args])

    def construct(self, obj, owner, desc, args):
        if self.on_new and self.on_new(owner, args):
            return
        code = self.find(owner, ("<init>", desc)) if owner in self.classes else None
        if code is not None:
            self.run(code, [obj, *args])
        if obj.cls == owner and self.is_subclass(owner, CROP_CARD):
            self.created.append(obj)

    def invoke(self, op, comment, stack):
        owner, name, desc = parse_ref(comment)
        args = [stack.pop() for _ in range(arg_count(desc))][::-1]
        receiver = None if op == "invokestatic" else stack.pop()
        if name == "<init>":
            if isinstance(receiver, Obj):
                self.construct(receiver, owner, desc, args)
            return
        result = Opaque()
        if isinstance(receiver, Obj) and op in ("invokevirtual", "invokeinterface"):
            code = self.find(receiver.cls, (name, desc))
            if code is not None:
                result = self.run(code, [receiver, *args])
        if not desc.endswith(")V"):
            stack.append(result)

    def run(self, code, local_vars):
        at = {ins[0]: i for i, ins in enumerate(code)}
        local_vars = list(local_vars) + [None] * 32
        stack, i = [], 0
        for _ in range(self.max_steps):
            _, op, operand, comment, table = code[i]
            i += 1
            if op.startswith(("iconst_", "lconst_", "fconst_", "dconst_")):
                stack.append(-1 if op.endswith("m1") else int(op[-1]))
            elif op in ("bipush", "sipush"):
                stack.append(int(operand))
            elif op in ("ldc", "ldc_w", "ldc2_w"):
                stack.append(ldc_value(comment))
            elif op == "aconst_null":
                stack.append(None)
            elif op[1:6] == "load_" or op[1:] == "load":
                stack.append(local_vars[int(op[-1]) if "_" in op else int(operand)])
            elif op[1:7] == "store_" or op[1:] == "store":
                local_vars[int(op[-1]) if "_" in op else int(operand)] = stack.pop()
            elif op == "dup":
                stack.append(stack[-1])
            elif op == "pop":
                stack.pop()
            elif op in ("anewarray", "newarray"):
                size = stack.pop()
                stack.append([None] * size if isinstance(size, int) else Opaque())
            elif op in ("aastore", "iastore"):
                value, index, array = stack.pop(), stack.pop(), stack.pop()
                if isinstance(array, list) and isinstance(index, int):
                    array[index] = value
            elif op in ("aaload", "iaload"):
                index, array = stack.pop(), stack.pop()
                ok = isinstance(array, list) and isinstance(index, int)
                stack.append(array[index] if ok else Opaque())
            elif op == "new":
                stack.append(Obj(comment.partition(" ")[2]))
            elif op == "getstatic":
                stack.append(Opaque())
            elif op == "putstatic":
                stack.pop()
            elif op == "getfield":
                target = stack.pop()
                name = parse_ref(comment)[1]
                stack.append(target.fields.get(name, Opaque()) if isinstance(target, Obj) else Opaque())
            elif op == "putfield":
                value, target = stack.pop(), stack.pop()
                if isinstance(target, Obj):
                    target.fields[parse_ref(comment)[1]] = value
            elif op.startswith("invoke"):
                self.invoke(op, comment, stack)
            elif op == "checkcast":
                pass
            elif op == "goto":
                i = at[int(operand)]
            elif op in ("tableswitch", "lookupswitch"):
                key = stack.pop()
                if not isinstance(key, int):
                    raise Unsupported("switch on an unknown value")
                i = at[table.get(str(key), table["default"])]
            elif op.endswith("return") and op != "return":
                return stack.pop()
            elif op == "return":
                return None
            else:
                raise Unsupported(op)
        raise Unsupported("step limit reached")


# ---------------------------------------------------------------- extraction

def find_javap(explicit=None):
    """javap to use: the explicit path, then PATH, then JAVA_HOME, then the newest installed JDK."""
    if explicit:
        return Path(explicit)
    found = shutil.which("javap")
    if found:
        return Path(found)
    java_home = os.environ.get("JAVA_HOME")
    if java_home and (Path(java_home) / "bin" / "javap.exe").exists():
        return Path(java_home) / "bin" / "javap.exe"
    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    installed = [*program_files.glob("Java/*/bin/javap.exe"), *program_files.glob("Eclipse Adoptium/*/bin/javap.exe")]
    installed.sort(key=lambda p: p.parent.parent.name)
    return installed[-1] if installed else None


def javap_classes(javap, jar, names):
    out = subprocess.run([str(javap), "-c", "-p", "-s", "-constants", "-classpath", str(jar), *names],
                         capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)
    return parse_javap(out.stdout)


def crop_record(name, tier, props, attrs):
    ok = (isinstance(name, str) and isinstance(tier, int)
          and isinstance(props, list) and len(props) == 5 and all(isinstance(p, int) for p in props)
          and isinstance(attrs, list) and all(isinstance(a, str) for a in attrs))
    return {"n": name, "t": tier, "s": props, "a": attrs} if ok else None


def gregtech_crops(classes):
    built = []

    def capture(owner, args):
        if owner == GT_BASE_CROP:
            built.append(args)
            return True
        return False

    Interpreter(classes, on_new=capture).call(Obj(GT_LOADER), "run", "()V")
    crops = []
    for args in built:
        # GTBaseCrop(id, name, discoverer, seed, tier, maxSize, growthSpeed,
        #            afterHarvest, harvest, 5 properties, attributes, ...); mTier = max(1, tier)
        tier = max(1, args[4]) if isinstance(args[4], int) else args[4]
        record = crop_record(args[1], tier, list(args[9:14]), args[14])
        if record:
            crops.append(record)
    return crops


def ic2_crops(classes, registry=IC2_REGISTRY):
    interp = Interpreter(classes)
    methods = classes[registry]["methods"]
    for key in (("<clinit>", "()V"), ("init", "()V")):     # init() builds the weed crop
        if key in methods:
            interp.run(methods[key], [])
    crops = []
    for obj in interp.created:
        try:
            record = crop_record(interp.call(obj, "name", "()Ljava/lang/String;"),
                                 interp.call(obj, "tier", "()I"),
                                 [interp.call(obj, "stat", "(I)I", [i]) for i in range(5)],
                                 interp.call(obj, "attributes", "()[Ljava/lang/String;"))
        except Unsupported:
            record = None
        if record:
            crops.append(record)
    return crops


def extract(mods_dir, javap):
    """Every IC2 and GregTech crop readable from the pack's jars, as {n, t, s, a} records."""
    mods = Path(mods_dir)
    ic2_jar = next(mods.glob("industrialcraft-2-*.jar"))
    gt_jar = next(mods.glob("gregtech-*.jar"))
    with zipfile.ZipFile(ic2_jar) as z:
        names = [n[:-6].replace("/", ".") for n in z.namelist()
                 if n.startswith("ic2/core/crop/") and n.endswith(".class") and "$" not in n
                 and n.split("/")[-1].startswith(("Crop", "Ic2CropCard", "IC2Crops"))]
    return (ic2_crops(javap_classes(javap, ic2_jar, names))
            + gregtech_crops(javap_classes(javap, gt_jar, [GT_LOADER.replace("/", ".")])))
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -p "test_crop_bytecode.py" -v`

Expected: `Ran 5 tests` … `OK` (the real-jar test runs on this PC; it is skipped where the pack or a JDK is missing)

---

### Task 2: Generator merges the jar data

**Files:**
- Modify: ADV `scripts/build_crop_table.py`
- Modify: ADV `tests/test_build_crop_table.py`

- [ ] **Step 1: Update the tests** in ADV `tests/test_build_crop_table.py`

In `ParseTablesTest.test_columns_are_mapped_per_table`, add at the end:

```python
        self.assertEqual(rows[0]["_section"], "Crops added by IC2")
        self.assertEqual(rows[2]["_section"], "Crops added by Crops++")
```

Replace the whole `CropsFromRowsTest` class with:

```python
class CropsFromRowsTest(unittest.TestCase):
    def test_records_fixes_duplicates_and_bad_rows(self):
        rows = bct.parse_tables(WIKITEXT) + [
            {"_section": "Crops added by GregTech", "Name": "Brown Mushrooms", "Tier": "1",
             "Internal Name": "Brown Mushrooms", "Attributes": "Food, Mushroom, Ingredient"},
            {"_section": "Crops added by GregTech", "Name": "Stagnium", "Tier": "6",
             "Internal Name": "stagnium", "Attributes": "Shiny"},
            {"_section": None, "Name": "Broken", "Tier": "", "Internal Name": "broken", "Attributes": "X"},
        ]
        crops, warnings = bct.crops_from_rows(rows)
        # The IC2 table's "Brown Mushrooms" is IC2's brownMushroom; GregTech's keeps its name.
        self.assertEqual([c["n"] for c in crops], ["stagnium", "brownMushroom", "saltroot", "Brown Mushrooms"])
        self.assertEqual(crops[0], {"n": "stagnium", "d": "Stagnium", "t": 6,
                                    "a": ["Shiny", "Leaves", "Metal"], "s": None})
        self.assertEqual(crops[2]["d"], "Salty Root")
        self.assertEqual(len(warnings), 2)    # duplicate stagnium, broken row
```

Add above `if __name__ == "__main__":`

```python
class MergeJarDataTest(unittest.TestCase):
    def test_fills_properties_and_prefers_the_jar(self):
        crops = [crop("stagnium", 6, ["Shiny", "Leaves", "Metal"]), crop("Bauxia", 5, ["Metal"]),
                 crop("Strawberry", 2, ["Berry"])]
        jar = [{"n": "stagnium", "t": 6, "s": [2, 0, 0, 1, 0], "a": ["metal", "leaves", "shiny"]},
               {"n": "Bauxia", "t": 6, "s": [5, 0, 2, 3, 3], "a": ["Metal", "Aluminium", "Reed", "Aluminium"]},
               {"n": "weed", "t": 0, "s": [0, 0, 1, 0, 5], "a": ["Weed", "Bad"]}]
        warnings = bct.merge_jar_data(crops, jar)
        self.assertEqual(crops[0]["s"], [2, 0, 0, 1, 0])
        self.assertEqual(crops[0]["a"], ["Shiny", "Leaves", "Metal"])   # same attributes: wiki spelling kept
        self.assertEqual((crops[1]["t"], crops[1]["a"]), (6, ["Metal", "Aluminium", "Reed", "Aluminium"]))
        self.assertIsNone(crops[2]["s"])
        self.assertEqual(len(warnings), 3)   # Bauxia tier, Bauxia attributes, weed not on the wiki
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -p "test_build_crop_table.py" -v`

Expected: FAIL. The `_section` key is missing (`KeyError: '_section'`), the crop names differ, and `merge_jar_data` doesn't exist yet.

- [ ] **Step 3: Scope the name fix to the IC2 table.** In ADV `scripts/build_crop_table.py`, replace:

```python
# The wiki's "Internal Name" is wrong for these IC2 crops; the real names are
# returned by CropBrownMushroom.name() / CropRedMushroom.name() in the IC2 jar.
INTERNAL_NAME_FIXES = {"brown mushrooms": "brownMushroom", "red mushrooms": "redMushroom"}
```

with:

```python
# The wiki's IC2 table gives IC2's two mushroom crops GregTech's crop names. The
# IC2 jar's CropBrownMushroom.name() / CropRedMushroom.name() return these; the
# GregTech table's "Brown Mushrooms" / "Red Mushrooms" are separate, real crops.
INTERNAL_NAME_FIXES = {("Crops added by IC2", "brown mushrooms"): "brownMushroom",
                       ("Crops added by IC2", "red mushrooms"): "redMushroom"}
```

- [ ] **Step 4: Record each row's section.** In `parse_tables`, replace:

```python
    rows = []
    for table in re.findall(r"\{\|(.*?)\n\|\}", wikitext, re.S):
        chunks = re.split(r"\n\|-", table)
```

with:

```python
    headings = [(m.start(), strip_wikimarkup(m.group(1)))
                for m in re.finditer(r"^=+\s*(.+?)\s*=+\s*$", wikitext, re.M)]
    rows = []
    for match in re.finditer(r"\{\|(.*?)\n\|\}", wikitext, re.S):
        section = next((name for pos, name in reversed(headings) if pos < match.start()), None)
        chunks = re.split(r"\n\|-", match.group(1))
```

and replace:

```python
            if cells:
                rows.append({h: strip_wikimarkup(c) for h, c in zip(headers, cells)})
```

with:

```python
            if cells:
                rows.append({"_section": section, **{h: strip_wikimarkup(c) for h, c in zip(headers, cells)}})
```

Update the docstring's second paragraph to:

```python
    """Return every data row of every wiki table as a {column header: text} dict.

    Columns are mapped by each table's own header row, because the Crops++
    table has an extra "Premature Drop" column. "_section" is the heading above
    the table, e.g. "Crops added by IC2".
    """
```

- [ ] **Step 5: Use the section in `crops_from_rows`.** Replace:

```python
        internal = INTERNAL_NAME_FIXES.get(internal.lower(), internal)
```

with:

```python
        internal = INTERNAL_NAME_FIXES.get((row.get("_section"), internal.lower()), internal)
```

- [ ] **Step 6: Add the merge, jar options and imports.**

Replace `import argparse` … `from fetch_wiki import api_get, strip_wikimarkup  # noqa: E402` with:

```python
import argparse
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import crop_bytecode  # noqa: E402
from fetch_wiki import api_get, strip_wikimarkup  # noqa: E402
```

After the `DEFAULT_OUT = …` line add:

```python
DEFAULT_MODS = (Path(os.environ.get("APPDATA", "")) / "PrismLauncher" / "instances"
                / "GT_New_Horizons_2.8.4_Java_17-25" / ".minecraft" / "mods")
```

After `add_total_weights` add:

```python
def merge_jar_data(crops, jar_crops):
    """Fill in hidden properties from the jars; the jar wins for tier and attributes.

    Returns warnings for every disagreement and for jar crops missing from the wiki.
    """
    by_name = {c["n"].lower(): c for c in jar_crops}
    warnings, used = [], set()
    for crop in crops:
        jar = by_name.get(crop["n"].lower())
        if jar is None:
            continue
        used.add(crop["n"].lower())
        crop["s"] = jar["s"]
        if jar["t"] != crop["t"]:
            warnings.append(f"{crop['n']}: tier {crop['t']} on the wiki, {jar['t']} in the jar (using the jar)")
            crop["t"] = jar["t"]
        if sorted(a.lower() for a in jar["a"]) != sorted(a.lower() for a in crop["a"]):
            warnings.append(f"{crop['n']}: attributes {crop['a']} on the wiki, {jar['a']} in the jar (using the jar)")
            crop["a"] = jar["a"]
    for key, jar in by_name.items():
        if key not in used:
            warnings.append(f"{jar['n']} is in the jars but not on the wiki (left out)")
    return warnings
```

Replace the start of `main` up to and including `add_total_weights(crops)` with:

```python
def main(argv=None):
    parser = argparse.ArgumentParser(description="Build crops.lua for the crop bot's autoBreed.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--mods", type=Path, default=DEFAULT_MODS,
                        help="the pack's mods folder, read for hidden crop properties")
    parser.add_argument("--javap", type=Path, help="javap to use (default: PATH, JAVA_HOME, newest JDK)")
    args = parser.parse_args(argv)

    data = api_get({"action": "parse", "page": PAGE, "prop": "wikitext|revid"})["parse"]
    crops, warnings = crops_from_rows(parse_tables(data["wikitext"]))
    javap = crop_bytecode.find_javap(args.javap)
    if javap is None:
        warnings.append("no javap found (install a JDK or pass --javap); hidden properties left unknown")
    else:
        try:
            warnings += merge_jar_data(crops, crop_bytecode.extract(args.mods, javap))
        except (OSError, KeyError, StopIteration, subprocess.CalledProcessError, crop_bytecode.Unsupported) as err:
            warnings.append(f"could not read crops from {args.mods} ({err!r}); hidden properties left unknown")
    add_total_weights(crops)
```

- [ ] **Step 7: Run all generator tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/tests" -v`

Expected: `Ran 15 tests` … `OK`

---

### Task 3: Regenerate `crops.lua`; robot tests use the real properties

**Files:**
- Regenerate: BOT `crops.lua`
- Modify: BOT `tests/test_breeding.py`
- Modify: BOT `tests/test_autobreed.py`

- [ ] **Step 1: Generate**

Run: `python "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/scripts/build_crop_table.py"`

Expected:

```
wrote 161 crops to C:\Users\loope\Desktop\GTNH 2.8.4 Agent\CropBot\GTNH-CropAutomation\crops.lua
hidden properties known for 84 of 161 crops
```

There should be no warnings.

- [ ] **Step 2: Add real-data expectations** to `RealTableTest` in BOT `tests/test_breeding.py`

```python
    def test_fertilia_parents_follow_the_hidden_properties(self):
        lua = runtime()
        b = lua.eval("require('breeding')")
        b.load()
        info = b.prepare(b.resolve('Fertilia'))
        self.assertEqual(info['dandelion']['e'], 0)       # shares Flower, but its properties rule it out
        self.assertGreater(info['zomplant']['e'], 0)      # shares nothing, but its properties are close
```

- [ ] **Step 3: Update the ranking expectation** in `AutoBreedCheckTest.test_check_reports_ranking_and_chest` (BOT `tests/test_autobreed.py`).

With real properties, Bauxia's top five are Titania, Aluminium Oreberry (an estimate), Galvania, Plumbilia and Nickelback. Replace:

```python
        for name in ("Argentia", "Plumbilia", "Titania"):
```

with:

```python
        for name in ("Titania", "Galvania", "Plumbilia"):
```

- [ ] **Step 4: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`. `test_lua_weights_match_the_generator` now also checks the property term against Python for every crop.

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add crops.lua tests/test_breeding.py tests/test_autobreed.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: crop table carries IC2's hidden properties for IC2 and GregTech crops" -m "84 of 161 crops now have their five hidden properties, read from the pack's jars. Also restores GregTech's Brown/Red Mushrooms, which the wiki name fix had dropped as duplicates." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Mark estimates with `~`

**Files:**
- Modify: BOT `breeding.lua`
- Modify: BOT `autoBreed.lua`
- Modify: BOT `tests/test_breeding.py`
- Modify: BOT `tests/test_autobreed.py`

- [ ] **Step 1: Write the failing tests**

Add to `BreedingTest` in BOT `tests/test_breeding.py`:

```python
    def test_prepare_marks_exact_values(self):
        lua = runtime()
        b = lua.eval("require('breeding')")
        lua.execute("""require('breeding').load({
            {n='T', d='T', t=1, a='X', s='1,1,1,1,1', w=500},
            {n='K', d='K', t=1, a='X', s='1,1,1,1,1', w=515},
            {n='U', d='U', t=1, a='X', w=505}})""")
        info = b.prepare(b.resolve('T'))
        self.assertTrue(info['k']['k'])      # both crops' properties known: exact
        self.assertFalse(info['u']['k'])     # U's properties unknown: estimate
```

In `AutoBreedCheckTest.test_check_reports_ranking_and_chest` (BOT `tests/test_autobreed.py`), replace `self.assertIn("odds are estimates", out)` with:

```python
        self.assertIn("values marked ~ are estimates", out)
        self.assertIn("Aluminium Oreberry", best)
        self.assertIn("%~", best)                          # its properties are unknown
        self.assertNotIn("~", seeds)                       # Stagnium and Nickelback are exact
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: FAIL. `info['k']['k']` is None, so assertTrue fails, and "values marked ~ are estimates" isn't printed yet.

- [ ] **Step 3: `breeding.lua` — flag exact values.** In `prepare`, replace:

```lua
        info[key] = {n=c.n, d=c.d, t=c.t, r=r, w=c.w, e=r / c.w}
```

with:

```lua
        info[key] = {n=c.n, d=c.d, t=c.t, r=r, w=c.w, e=r / c.w, k=(target.s ~= nil and c.s ~= nil)}
```

and replace the comment above `prepare` with:

```lua
-- Builds the per-crop info map for a target, keyed by lowercase internal name:
-- {n, d, t, r = ratio(target, crop), w, e = r / w, k = both crops' hidden
-- properties known (e is exact) or not (e is an estimate)}.
```

- [ ] **Step 4: `autoBreed.lua` — print the marks.**

Add after `local function pct(value) … end`:

```lua


local function mark(entry)
    return entry.k and '' or '~'
end
```

In `resolveTarget`, replace:

```lua
        print(string.format('autoBreed: hidden crop properties known for %d of %d crops, so odds are estimates', known, total))
```

with:

```lua
        print(string.format('autoBreed: hidden crop properties known for %d of %d crops; values marked ~ are estimates', known, total))
```

In `report`, replace:

```lua
        best[#best+1] = entry.d .. ' ' .. pct(entry.e)
```

with:

```lua
        best[#best+1] = entry.d .. ' ' .. pct(entry.e) .. mark(entry)
```

and replace:

```lua
            have[#have+1] = string.format('%s %s (%d)', info[key].d, pct(info[key].e), entry.count)
```

with:

```lua
            have[#have+1] = string.format('%s %s%s (%d)', info[key].d, pct(info[key].e), mark(info[key]), entry.count)
```

Replace `printChance` with:

```lua
local function printChance()
    local keys = parentKeys()
    local chance, exact = breeding.chance(keys), true
    for _, key in ipairs(keys) do
        if not (info[key] and info[key].k) then
            exact = false
        end
    end
    local text = pct(chance) .. (exact and '' or '~')
    if text ~= lastChance then
        lastChance = text
        print(string.format('autoBreed: %s %s per cross with current parents', target.d, text))
    end
end
```

- [ ] **Step 5: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add breeding.lua autoBreed.lua tests/test_breeding.py tests/test_autobreed.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "feat: mark autoBreed odds that are estimates with ~" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: A target that can't be stored survives

**Files:**
- Modify: BOT `tests/oc_stubs.lua`
- Modify: BOT `tests/test_autobreed.py`
- Modify: BOT `autoBreed.lua`
- Modify: BOT `README.md`
- Modify: BOT `docs/superpowers/specs/2026-09-27-autobreed-design.md`

- [ ] **Step 1: Teach the stubs `os.exit` and `swingDown`.** In BOT `tests/oc_stubs.lua`:

In the `stub = {…}` table, after `chestReads = {},`, add:

```lua
    swings = {},      -- physical {x, y} of every swingDown()
```

After `os.sleep = function() end` add:

```lua
-- OpenOS ends a program by raising this; a real os.exit would kill the test run.
os.exit = function(code)
    error({reason = 'terminated', code = code}, 0)
end
```

Replace `        swingDown = function() return true end,` with:

```lua
        swingDown = function()
            table.insert(stub.swings, {x=stub.physical.x, y=stub.physical.y})
            return true
        end,
```

- [ ] **Step 2: Report the exit code, and write the failing test.** In BOT `tests/test_autobreed.py`, replace `run_program` with:

```python
def run_program(lua, *args):
    return run_with_code(lua, *args)[0]


def run_with_code(lua, *args):
    """Run autoBreed; return (printed output, exit code as the OpenOS shell sees it)."""
    lines = []
    lua.globals().print = lambda *parts: lines.append(" ".join(str(p) for p in parts))
    source = (REPO / "autoBreed.lua").read_text(encoding="utf-8")
    run = lua.eval("""function(src, ...)
        local ok, err = pcall(assert(load(src, '=autoBreed')), ...)
        if ok then return 0 end
        if type(err) == 'table' and err.reason == 'terminated' then return err.code or 0 end
        error(err, 0)
    end""")
    code = run(source, *args)
    return "\n".join(lines), code
```

and add above `if __name__ == "__main__":`

```python
class StrandedTargetTest(unittest.TestCase):
    PARENT = ("{name='IC2:blockCrop', ['crop:name']='%s', ['crop:growth']=1, ['crop:gain']=1,"
              " ['crop:resistance']=1, ['crop:tier']=6, ['crop:size']=3, ['crop:maxSize']=4}")
    BAUXIA = ("{name='IC2:blockCrop', ['crop:name']='Bauxia', ['crop:growth']=5, ['crop:gain']=5,"
              " ['crop:resistance']=5, ['crop:tier']=6, ['crop:size']=1, ['crop:maxSize']=3}")
    AIR = "{name='minecraft:air'}"

    def test_target_found_with_storage_full_is_left_alone_and_stops_the_chain(self):
        lua = new_robot()
        first_pass = [self.PARENT % 'stagnium', self.AIR, self.PARENT % 'Nickelback'] + [self.AIR] * 33
        second_pass = [self.PARENT % 'stagnium', self.BAUXIA]           # Re 5: above the cap of 2
        storage = ["{name='minecraft:stone'}"] * 81                      # every storage slot taken
        lua.execute("stub.scans = {%s}" % ", ".join(first_pass + second_pass + storage))
        out, code = run_with_code(lua, "Bauxia")
        self.assertIn("storage farm is full", out)
        self.assertEqual(code, 1)                                        # `&& autoStat` does not run
        swings = [(s['x'], s['y']) for s in lua.eval("stub.swings").values()]
        self.assertNotIn((0, 2), swings)                                 # slot 2, where the Bauxia is
        self.assertEqual(physical(lua), (0, 0, 1))
```

- [ ] **Step 3: Run it and watch it fail**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -p "test_autobreed.py" -v`

Expected: `test_target_found_with_storage_full_is_left_alone_and_stops_the_chain` FAILS: the exit code is 0 and cleanup swings at (0, 2).

- [ ] **Step 4: Fix `autoBreed.lua`.**

Add `local stranded` after `local captured = false`.

In `capture`, replace:

```lua
    else
        print(string.format('autoBreed: Found %s (%s) but the storage farm is full; it is still on the working farm', target.d, stats))
    end
```

with:

```lua
    else
        stranded = slot
        print(string.format('autoBreed: Found %s (%s) in working-farm slot %d, but the storage farm is full.', target.d, stats, slot))
        print('  Left it there and stopped. Empty the storage farm and run autoBreed again, or take it by hand.')
    end
```

In `main`, directly after the `while breedOnce(false) do … end` loop, add:

```lua

    -- A target left on the working farm must survive: skip cleanUp and stop any && chain
    if stranded then
        action.restockAll()
        events.unhookEvents()
        os.exit(1)
    end
```

- [ ] **Step 5: Run all bot tests**

Run: `python -m unittest discover -s "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation/tests" -v`

Expected: `OK`

- [ ] **Step 6: Document it.** In BOT `README.md`, replace:

```
Parents removed to make room for better ones go to the storage chest, so make it a real chest if you want them back.
```

with:

```
Parents removed to make room for better ones go to the storage chest, so make it a real chest if you want them back.

The odds use each crop's hidden properties, read from the pack's jars for IC2 and GregTech crops. Values marked `~` are estimates, because that crop's properties are not known yet (Crops++, GT++, GoodGenerator). If the target turns up while the storage farm is full and its stats are above your working caps, autoBreed leaves it on the working farm, stops, and skips the rest of an `&&` chain. Empty the storage farm and run autoBreed again.
```

In BOT `docs/superpowers/specs/2026-09-27-autobreed-design.md`, replace:

```
**On capture:** print where the target went and its stats, beep, run cleanup that keeps parents unless weed-like, then `restockAll`.
```

with:

```
**On capture:** print where the target went and its stats, beep, run cleanup that keeps parents unless weed-like, then `restockAll`. If the target has to go to storage and the storage farm is full, leave it where it is, skip cleanup, park, and `os.exit(1)` so an `&&` chain stops.
```

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" add autoBreed.lua README.md docs/superpowers/specs/2026-09-27-autobreed-design.md tests/oc_stubs.lua tests/test_autobreed.py
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" commit -m "fix: a target found while storage is full is no longer destroyed" -m "The capture fell through to the end-of-run cleanup, which breaks every child crop. autoBreed now leaves the target in place, parks, and exits with code 1 so && chains stop." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Deploy

- [ ] **Step 1: Push** (the same branch the user already approved for testing):

```bash
git -C "C:/Users/loope/Desktop/GTNH 2.8.4 Agent/CropBot/GTNH-CropAutomation" push fork autobreed
```

- [ ] **Step 2: Confirm the fork serves the new table.** Run `curl -s https://raw.githubusercontent.com/Keegater/GTNH-CropAutomation/autobreed/crops.lua | head -2`. Expected: the second line reads `-- Hidden crop properties known for 84 of 161 crops …`.

- [ ] **Step 3: User, in game.** First empty the storage farm. Then:

```
wget -f https://raw.githubusercontent.com/Keegater/GTNH-CropAutomation/autobreed/setup.lua && setup autobreed
reboot
autoBreed Fertilia --check
```

Zomplant should show without `~`, and the IC2 flowers should not appear in the ranking at all.
