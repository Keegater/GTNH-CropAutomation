import unittest

from lua_env import REPO, runtime


def new_robot(chest="", chest_size=27, physical=None):
    """A freshly booted robot: modules load fresh, so gps.lua assumes it is on the
    charger facing direction 1. `physical` is where the robot really is (x, y, facing)."""
    lua = runtime(stubs=True)
    lua.execute("stub.chest = {%s}" % chest)
    if chest_size is None:
        lua.execute("stub.chestSize = nil")
    if physical:
        lua.execute("stub.physical = {x=%d, y=%d, facing=%d}" % physical)
    return lua


def run_program(lua, *args):
    lines = []
    lua.globals().print = lambda *parts: lines.append(" ".join(str(p) for p in parts))
    source = (REPO / "autoBreed.lua").read_text(encoding="utf-8")
    run = lua.eval("function(src, ...) return assert(load(src, '=autoBreed'))(...) end")
    run(source, *args)
    return "\n".join(lines)


def physical(lua):
    p = lua.eval("stub.physical")
    return (p['x'], p['y'], p['facing'])


def run_autobreed(*args, chest="", chest_size=27):
    return run_program(new_robot(chest, chest_size), *args)


class AutoBreedCheckTest(unittest.TestCase):
    CHEST = ("[1]={label='Stagnium Seeds', size=4}, [2]={label='Nickelback Seeds', size=2},"
             " [5]={label='Unknown Seeds', size=1}")

    def test_check_reports_ranking_and_chest(self):
        out = run_autobreed("Bauxia", "--check", chest=self.CHEST)
        self.assertIn("Target Bauxia (tier 6)", out)
        best = next(line for line in out.splitlines() if "best parents:" in line)
        for name in ("Titania", "Galvania", "Plumbilia"):
            self.assertIn(name, best)
        seeds = next(line for line in out.splitlines() if "seed chest:" in line)
        self.assertIn("Stagnium", seeds)
        self.assertIn("(4)", seeds)
        self.assertIn("Nickelback", seeds)
        self.assertIn("(2)", seeds)
        self.assertIn("ignored:      Unknown Seeds", out)
        self.assertIn("free memory:  200 KB", out)
        self.assertIn("values marked ~ are estimates", out)
        self.assertIn("Aluminium Oreberry", best)
        self.assertIn("%~", best)                          # its properties are unknown
        self.assertNotIn("~", seeds)                       # Stagnium and Nickelback are exact

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


class RobotHeadingTest(unittest.TestCase):
    """The robot has no compass: after a reboot gps.lua assumes it is on the charger
    facing direction 1, so every program must leave it exactly there."""

    def test_check_reads_the_seed_chest_at_its_position(self):
        lua = new_robot()
        run_program(lua, "Bauxia", "--check")
        reads = [(r['x'], r['y']) for r in lua.eval("stub.chestReads").values()]
        self.assertEqual(reads, [(-3, 0)])

    def test_check_parks_on_the_charger_facing_forward(self):
        lua = new_robot()
        run_program(lua, "Bauxia", "--check")
        self.assertEqual(physical(lua), (0, 0, 1))

    def test_check_after_a_reboot_still_reads_the_seed_chest(self):
        first = new_robot()
        run_program(first, "Bauxia", "--check")
        second = new_robot(physical=physical(first))   # reboot: the robot stays where it is
        run_program(second, "Bauxia", "--check")
        reads = [(r['x'], r['y']) for r in second.eval("stub.chestReads").values()]
        self.assertEqual(reads, [(-3, 0)])

    def test_run_that_stops_early_also_parks_facing_forward(self):
        lua = new_robot()   # empty farm and empty seed chest: it stops for lack of parents
        out = run_program(lua, "Bauxia")
        self.assertIn("need at least two parents", out)
        self.assertEqual(physical(lua), (0, 0, 1))


if __name__ == "__main__":
    unittest.main()
