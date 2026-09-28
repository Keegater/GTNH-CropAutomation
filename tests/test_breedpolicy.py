import unittest

from lua_env import runtime

CTX = """{
    info = {bauxia = {e = 0.5}, stagnium = {e = 0.01}, nickelback = {e = 0.009}},
    targetKey = 'bauxia',
    caps = {workingMaxGrowth = 21, workingMaxResistance = 6},
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
        self.assertEqual(act(self.crop('Bauxia', gr=21, re=6), self.ctx()), 'captureSlot1')
        self.assertEqual(act(self.crop('Bauxia', gr=22, re=1), self.ctx()), 'captureStorage')
        self.assertEqual(act(self.crop('Bauxia', gr=1, re=7), self.ctx()), 'captureStorage')
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
