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

    def test_fertilia_parents_follow_the_hidden_properties(self):
        lua = runtime()
        b = lua.eval("require('breeding')")
        b.load()
        info = b.prepare(b.resolve('Fertilia'))
        self.assertEqual(info['dandelion']['e'], 0)       # shares Flower, but its properties rule it out
        self.assertGreater(info['zomplant']['e'], 0)      # shares nothing, but its properties are close

    def test_bauxia_is_in_the_table(self):
        lua = runtime()
        b = lua.eval("require('breeding')")
        b.load()
        rec = b.resolve('bauxia')
        self.assertEqual((rec['n'], rec['t'], rec['a']), ('Bauxia', 6, 'Metal,Aluminium,Reed,Aluminium'))


if __name__ == "__main__":
    unittest.main()
