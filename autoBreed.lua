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
local stranded
local lastChance

-- ===================== FUNCTIONS ======================

local function pct(value)
    return string.format('%.2f%%', value * 100)
end


local function mark(entry)
    return entry.k and '' or '~'
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
        print(string.format('autoBreed: hidden crop properties known for %d of %d crops; values marked ~ are estimates', known, total))
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
        best[#best+1] = entry.d .. ' ' .. pct(entry.e) .. mark(entry)
    end
    print('  best parents: ' .. (#best > 0 and table.concat(best, ', ') or 'none share anything with it'))

    if ignored == nil then
        print(string.format('  seed chest:   none found at {%d, %d}', config.seedContainerPos[1], config.seedContainerPos[2]))
    else
        local have = {}
        for key, entry in pairs(chest) do
            have[#have+1] = string.format('%s %s%s (%d)', info[key].d, pct(info[key].e), mark(info[key]), entry.count)
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
        stranded = slot
        print(string.format('autoBreed: Found %s (%s) in working-farm slot %d, but the storage farm is full.', target.d, stats, slot))
        print('  Left it there and stopped. Empty the storage farm and run autoBreed again, or take it by hand.')
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
        -- Park like charge() does: after a reboot gps.lua assumes charger, facing 1
        gps.go(config.chargerPos)
        gps.turnTo(1)
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

    -- A target left on the working farm must survive: skip cleanUp and stop any && chain
    if stranded then
        action.restockAll()
        events.unhookEvents()
        os.exit(1)
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
