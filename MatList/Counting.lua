-- MatList: counting bags + cached bank, and throttled refresh scheduling.
local ADDON, ns = ...
local Counting = {}
ns.Counting = Counting

local THROTTLE = 0.3
local bankOpen = false
local rows, rowByItem = {}, {}
local pending = false

------------------------------------------------------------------------
-- Bank state.
-- Event names (BANKFRAME_OPENED/CLOSED, PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE) are the retail
-- ones and are NOT verified for Forever, so we also fall back to checking BankFrame visibility.
------------------------------------------------------------------------
function Counting.IsBankOpen()
    if bankOpen then return true end
    return _G.BankFrame ~= nil and _G.BankFrame.IsShown ~= nil and _G.BankFrame:IsShown() or false
end

local function GetCount(itemID, includeBank)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    -- includeUses=false; includeReagentBank / includeAccountBank = true only matter when includeBank.
    return C_Item.GetItemCount(itemID, includeBank and true or false, false, includeBank and true or false, includeBank and true or false) or 0
end

-- Bank contribution for one item. Only readable live while the bank is open; otherwise use the cache.
local function BankCount(itemID)
    local cache = ns.db.bankCache
    if Counting.IsBankOpen() then
        local n = math.max(0, GetCount(itemID, true) - GetCount(itemID, false))
        cache.counts[itemID] = n
        cache.updated = time()
        return n
    end
    return cache.counts[itemID] or 0
end

function Counting.BankAge()
    local t = ns.db.bankCache.updated
    if not t then return nil end
    return time() - t
end

------------------------------------------------------------------------
-- Rows: one per material, sorted missing-first.
------------------------------------------------------------------------
local function ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return "Item " .. itemID, false
    end
    return name, true
end

function Counting.Recount()
    local groups = ns.Data.Aggregate()
    rows, rowByItem = {}, {}
    local bankSeen = false
    for _, g in ipairs(groups) do
        local have = 0
        for _, itemID in ipairs(g.items) do
            have = have + GetCount(itemID, false) + BankCount(itemID)
        end
        local name = ItemName(g.key)
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(g.key)
        local row = {
            key = g.key, items = g.items, name = name, icon = icon,
            have = have, need = g.need, missing = math.max(0, g.need - have),
            recipes = g.recipes,
        }
        rows[#rows + 1] = row
        for _, itemID in ipairs(g.items) do rowByItem[itemID] = row end
    end
    table.sort(rows, function(a, b)
        local am, bm = a.missing > 0, b.missing > 0
        if am ~= bm then return am end
        if a.missing ~= b.missing then return a.missing > b.missing end
        return a.name < b.name
    end)
end

function Counting.GetRows() return rows end
function Counting.GetRowForItem(itemID) return rowByItem[itemID] end

------------------------------------------------------------------------
-- Throttled refresh. Events only set a flag/timer; work happens at most once per THROTTLE seconds.
------------------------------------------------------------------------
function ns.RequestRefresh()
    if pending or not ns.db then return end
    pending = true
    C_Timer.After(THROTTLE, function()
        pending = false
        ns.Safe("recount", Counting.Recount)
        if ns.UI and ns.UI.Refresh then ns.Safe("ui refresh", ns.UI.Refresh) end
    end)
end

-- Bag changes (BAG_UPDATE_DELAYED is the retail "all updates for this frame done" event).
ns.On("BAG_UPDATE_DELAYED", ns.RequestRefresh)
ns.On("PLAYERBANKSLOTS_CHANGED", ns.RequestRefresh)
ns.On("PLAYERREAGENTBANKSLOTS_CHANGED", ns.RequestRefresh)
ns.On("PLAYERBANKBAGSLOTS_CHANGED", ns.RequestRefresh)
ns.On("ITEM_DATA_LOAD_RESULT", ns.RequestRefresh) -- item names arrive after RequestLoadItemDataByID

ns.On("BANKFRAME_OPENED", function()
    bankOpen = true
    ns.RequestRefresh()
end)
ns.On("BANKFRAME_CLOSED", function()
    -- Counts were snapshotted on the last refresh while open. Keep the flag until then.
    bankOpen = false
    ns.RequestRefresh()
end)

-- Newer retail clients report banker interaction through this event pair instead.
local function IsBanker(interactionType)
    local T = Enum and Enum.PlayerInteractionType
    return T ~= nil and (interactionType == T.Banker or interactionType == T.AccountBanker)
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, t)
    if IsBanker(t) then bankOpen = true ns.RequestRefresh() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, t)
    if IsBanker(t) then bankOpen = false ns.RequestRefresh() end
end)
