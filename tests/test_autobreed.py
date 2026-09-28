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
