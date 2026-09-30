-- Crop math for autoBreed. Pure Lua with no OpenComputers calls, so it can be
-- unit-tested off the robot. ratio() mirrors IC2's
-- TileEntityCrop.calculateRatioFor (industrialcraft-2-2.2.828-experimental).
local crops, byName, byDisplay
local info, infoByDisplay, targetKey


local function load(data)
    crops = data or require('crops')
    byName, byDisplay = {}, {}
    for _, c in ipairs(crops) do
        byName[c.n:lower()] = c
        byDisplay[c.d:lower()] = c
    end
    return #crops
end


-- Frees the full table; anything built by prepare() keeps working.
local function unload()
    crops, byName, byDisplay = nil, nil, nil
    package.loaded.crops = nil
end


local function propertiesKnown()
    local known = 0
    for _, c in ipairs(crops) do
        if c.s then
            known = known + 1
        end
    end
    return known, #crops
end


local function numbers(text)
    local out = {}
    for value in text:gmatch('[^,]+') do
        out[#out+1] = tonumber(value)
    end
    return out
end


-- Weight of species x in a cross that parent p joined.
local function ratio(x, p)
    if x.n == p.n then
        return 500
    end

    local v = 0
    if x.s and p.s then
        local xs, ps = numbers(x.s), numbers(p.s)
        for i=1, 5 do
            v = v + 2 - math.abs(xs[i] - ps[i])
        end
    end

    for a in x.a:gmatch('[^,]+') do
        for b in p.a:gmatch('[^,]+') do
            if a:lower() == b:lower() then
                v = v + 5
            end
        end
    end

    local d = x.t - p.t
    if d > 1 then
        v = v - 2 * d
    end
    if d < -3 then
        v = v + d
    end
    return math.max(v, 0)
end


-- Finds a crop by internal or display name (any case). Returns the record, or
-- nil plus up to 5 display names containing the text.
local function resolve(text)
    local key = text:lower()
    local hit = byName[key] or byDisplay[key]
    if hit then
        return hit
    end

    local suggestions = {}
    for _, c in ipairs(crops) do
        if #suggestions < 5 and (c.n:lower():find(key, 1, true) or c.d:lower():find(key, 1, true)) then
            suggestions[#suggestions+1] = c.d
        end
    end
    return nil, suggestions
end


-- Builds the per-crop info map for a target, keyed by lowercase internal name:
-- {n, d, t, r = ratio(target, crop), w, e = r / w, k = both crops' hidden
-- properties known (e is exact) or not (e is an estimate)}.
local function prepare(target)
    info, infoByDisplay, targetKey = {}, {}, target.n:lower()
    for _, c in ipairs(crops) do
        local r = ratio(target, c)
        local key = c.n:lower()
        info[key] = {n=c.n, d=c.d, t=c.t, r=r, w=c.w, e=r / c.w, k=(target.s ~= nil and c.s ~= nil)}
        infoByDisplay[c.d:lower()] = key
    end
    return info
end


-- "Stagnium Seeds" -> "stagnium"; nil for unscanned, invalid or unknown bags.
local function labelToKey(label)
    local name = label:match('^(.-) Seeds$')
    if not name then
        return nil
    end
    name = name:lower()
    if info[name] then
        return name
    end
    return infoByDisplay[name]
end


-- Chance that a cross among these parents yields the target. Unknown keys are ignored.
local function chance(keys)
    local num, den = 0, 0
    for _, key in ipairs(keys) do
        local entry = info[key]
        if entry then
            num = num + entry.r
            den = den + entry.w
        end
    end
    if den == 0 then
        return 0
    end
    return num / den
end


-- The best parents for the target (e > 0), best first.
local function top(count)
    local list = {}
    for key, entry in pairs(info) do
        if key ~= targetKey and entry.e > 0 then
            list[#list+1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.e ~= b.e then
            return a.e > b.e
        end
        return a.d < b.d
    end)
    while #list > count do
        table.remove(list)
    end
    return list
end


return {
    load = load,
    unload = unload,
    propertiesKnown = propertiesKnown,
    ratio = ratio,
    resolve = resolve,
    prepare = prepare,
    labelToKey = labelToKey,
    chance = chance,
    top = top
}
