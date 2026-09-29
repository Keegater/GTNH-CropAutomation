-- Minimal OpenComputers stand-ins so action.lua and autoBreed.lua can run in
-- tests. The global `stub` lets a test set the seed chest and scan results.
stub = {
    chest = {},       -- chest slot -> {label=, size=}
    chestSize = 27,   -- getInventorySize() result; nil means "no inventory"
    scans = {},       -- queue of geolyzer.analyze() results; empty queue = air
    inventory = {},   -- robot slot -> item count
    physical = {x=0, y=0, facing=1},  -- where the robot really is; gps.lua only believes
    chestReads = {},  -- physical {x, y} of every getInventorySize() call
}

-- Same axes as gps.lua: facing 1 = +y, 2 = +x, 3 = -y, 4 = -x; turnRight counts up.
local steps = {{0, 1}, {1, 0}, {0, -1}, {-1, 0}}

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
        forward = function()
            local step = steps[stub.physical.facing]
            stub.physical.x = stub.physical.x + step[1]
            stub.physical.y = stub.physical.y + step[2]
            return true
        end,
        turnLeft = function()
            stub.physical.facing = (stub.physical.facing + 2) % 4 + 1
            return true
        end,
        turnRight = function()
            stub.physical.facing = stub.physical.facing % 4 + 1
            return true
        end,
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
            getInventorySize = function()
                table.insert(stub.chestReads, {x=stub.physical.x, y=stub.physical.y})
                return stub.chestSize
            end,
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
