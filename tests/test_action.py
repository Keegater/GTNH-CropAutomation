import unittest

from lua_env import runtime

STAGNIUM = ("{name='IC2:blockCrop', ['crop:name']='stagnium', ['crop:growth']=3, ['crop:gain']=4,"
            " ['crop:resistance']=5, ['crop:tier']=6, ['crop:size']=1, ['crop:maxSize']=4}")


class DumpInventoryFixTest(unittest.TestCase):
    def test_deweed_with_full_inventory_dumps_instead_of_crashing(self):
        lua = runtime(stubs=True)
        lua.execute("""
            for i=1, 16 do stub.inventory[i] = 1 end
            require('action').deweed()
        """)


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
