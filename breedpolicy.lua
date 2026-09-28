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
