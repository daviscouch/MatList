-- MatList: list model, aggregation, export/import.
--
-- Data model (ns.db.recipes):
--   [recipeID] = { qty = <number of crafts>, name = "...", reagents = { {items = {itemID, ...}, qty = n}, ... } }
-- A reagent "slot" lists every quality tier of one material; they are counted together.
-- Reagent lists are cached at add time so the list works without the profession window open.
-- Aggregation is computed on demand (never stored) so Phase 2 features (nested crafting,
-- vendor/farmed flags in ns.db.mats, alt counts in ns.db.alts) can hook in here cleanly.
local ADDON, ns = ...
local Data = {}
ns.Data = Data

local aggCache

local function Changed()
    aggCache = nil
    if ns.RequestRefresh then ns.RequestRefresh() end
end
Data.Changed = Changed

------------------------------------------------------------------------
-- Reading a recipe from the game
------------------------------------------------------------------------
-- Returns name, reagents  OR  nil, errorMessage
local function ReadRecipe(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil, "the recipe API (C_TradeSkillUI.GetRecipeSchematic) isn't available on this client."
    end
    -- Verified present in Forever's API list. Schematic layout (reagentSlotSchematics[].reagents[].itemID,
    -- .quantityRequired, .reagentType) is the retail 10.x+ layout - NOT verified in-game on Forever.
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" then
        return nil, "no recipe data for ID " .. tostring(recipeID) .. " (is it a real recipe you know?)."
    end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        -- Only required ("Basic") reagents; optional/finishing slots are not shopping needs.
        local wanted = true
        if basic ~= nil and slot.reagentType ~= nil then wanted = (slot.reagentType == basic) end
        local qty = tonumber(slot.quantityRequired)
        if wanted and qty and qty > 0 then
            local items = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then items[#items + 1] = reagent.itemID end -- skips currency reagents
            end
            if #items > 0 then reagents[#reagents + 1] = { items = items, qty = qty } end
        end
    end
    if #reagents == 0 then
        return nil, "recipe " .. tostring(recipeID) .. " has no required item reagents."
    end
    local name = schematic.name
    if not name and C_TradeSkillUI.GetRecipeInfo then
        local ok2, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok2 and type(info) == "table" then name = info.name end
    end
    return name or ("Recipe " .. recipeID), reagents
end

------------------------------------------------------------------------
-- List management
------------------------------------------------------------------------
-- Adding a recipe that is already listed increases its quantity.
function Data.AddRecipe(recipeID, qty)
    recipeID = tonumber(recipeID)
    qty = math.floor(tonumber(qty) or 1)
    if not recipeID then return false, "invalid recipe ID." end
    if qty < 1 then return false, "quantity must be at least 1." end
    local existing = ns.db.recipes[recipeID]
    if existing then
        existing.qty = existing.qty + qty
        Changed()
        return true, string.format("%s (now x%d)", existing.name, existing.qty)
    end
    local name, reagents = ReadRecipe(recipeID)
    if not name then return false, reagents end
    ns.db.recipes[recipeID] = { qty = qty, name = name, reagents = reagents, addedAt = time() }
    Changed()
    return true, string.format("%s x%d", name, qty)
end

function Data.SetQty(recipeID, qty)
    local r = ns.db.recipes[recipeID]
    if not r then return end
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 then
        ns.db.recipes[recipeID] = nil
    else
        r.qty = qty
    end
    Changed()
end

function Data.RemoveRecipe(recipeID)
    ns.db.recipes[recipeID] = nil
    Changed()
end

function Data.Clear()
    ns.db.recipes = {}
    Changed()
end

-- Recipes as a sorted array: { {id=, name=, qty=}, ... }
function Data.SortedRecipes()
    local out = {}
    for id, r in pairs(ns.db.recipes) do
        out[#out + 1] = { id = id, name = r.name or ("Recipe " .. id), qty = r.qty }
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

------------------------------------------------------------------------
-- Aggregation: merges the same material across recipes (and across quality tiers).
-- Returns array of { key = itemID, items = {itemIDs}, need = n, recipes = { {name=, need=}, ... } }
------------------------------------------------------------------------
function Data.Aggregate()
    if aggCache then return aggCache end
    local groups, itemToGroup = {}, {}
    local ids = {}
    for id in pairs(ns.db.recipes) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, rid in ipairs(ids) do
        local r = ns.db.recipes[rid]
        for _, slot in ipairs(r.reagents or {}) do
            local g
            for _, itemID in ipairs(slot.items) do
                if itemToGroup[itemID] then g = itemToGroup[itemID] break end
            end
            if not g then
                g = { key = slot.items[1], items = {}, need = 0, recipes = {}, byRecipe = {} }
                groups[#groups + 1] = g
            end
            for _, itemID in ipairs(slot.items) do
                if not itemToGroup[itemID] then
                    itemToGroup[itemID] = g
                    g.items[#g.items + 1] = itemID
                end
            end
            local add = slot.qty * r.qty
            g.need = g.need + add
            local entry = g.byRecipe[rid]
            if not entry then
                entry = { name = r.name or ("Recipe " .. rid), need = 0 }
                g.byRecipe[rid] = entry
                g.recipes[#g.recipes + 1] = entry
            end
            entry.need = entry.need + add
        end
    end
    aggCache = groups
    return groups
end

------------------------------------------------------------------------
-- Export / import: one line of text, "MATLIST1:" + records joined by ";"
-- record = recipeID ~ qty ~ name ~ slot ^ slot ...   slot = itemID . itemID = qty
------------------------------------------------------------------------
local HEADER = "MATLIST1:"

function Data.Export()
    local records = {}
    for _, e in ipairs(Data.SortedRecipes()) do
        local r = ns.db.recipes[e.id]
        local slots = {}
        for _, slot in ipairs(r.reagents or {}) do
            slots[#slots + 1] = table.concat(slot.items, ".") .. "=" .. slot.qty
        end
        local safeName = (r.name or ""):gsub("[;~^=.|]", " ")
        records[#records + 1] = table.concat({ e.id, r.qty, safeName, table.concat(slots, "^") }, "~")
    end
    return HEADER .. table.concat(records, ";")
end

-- Replaces the current list. Returns true, count  OR  false, errorMessage. Never modifies data on failure.
function Data.Import(text)
    text = (text or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if text:sub(1, #HEADER) ~= HEADER then
        return false, "that doesn't look like a MatList export (should start with " .. HEADER .. ")."
    end
    local body = text:sub(#HEADER + 1)
    local parsed, count = {}, 0
    for record in body:gmatch("[^;]+") do
        local idStr, qtyStr, name, slotStr = record:match("^(%d+)~(%d+)~([^~]*)~(.+)$")
        local rid, qty = tonumber(idStr), tonumber(qtyStr)
        if not rid or not qty or qty < 1 then
            return false, "couldn't read a recipe entry: " .. record:sub(1, 40)
        end
        local reagents = {}
        for slot in slotStr:gmatch("[^^]+") do
            local itemStr, needStr = slot:match("^([%d%.]+)=(%d+)$")
            local need = tonumber(needStr)
            if not itemStr or not need then
                return false, "couldn't read a reagent in recipe " .. rid .. "."
            end
            local items = {}
            for itemID in itemStr:gmatch("%d+") do items[#items + 1] = tonumber(itemID) end
            if #items == 0 then return false, "empty reagent in recipe " .. rid .. "." end
            reagents[#reagents + 1] = { items = items, qty = need }
        end
        parsed[rid] = { qty = qty, name = name ~= "" and name or ("Recipe " .. rid), reagents = reagents, addedAt = time() }
        count = count + 1
    end
    ns.db.recipes = parsed
    Changed()
    return true, count
end
