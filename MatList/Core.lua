-- MatList: namespace, event dispatch, helpers, slash commands.
-- Built for World of Warcraft: Forever (interface 16001), which runs the retail (Midnight-era) API.
-- No global addon table on purpose; only MatListDB (SavedVariables) and the slash command are global.
local ADDON, ns = ...

ns.VERSION = "0.1.0"
ns.missingEvents = {}

function ns.Print(msg)
    print("|cff33ff99MatList|r: " .. tostring(msg))
end

-- Run fn; on error print it once (avoids chat spam from repeating events) instead of a Lua error popup.
local seenErrors = {}
function ns.Safe(label, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        local key = label .. tostring(a)
        if not seenErrors[key] then
            seenErrors[key] = true
            ns.Print("internal error in " .. label .. ": " .. tostring(a))
        end
        return nil
    end
    return a, b, c
end

------------------------------------------------------------------------
-- Event dispatcher.
-- Forever quirk (per community findings): registering an event name the client doesn't know
-- throws, so every registration is pcall'd and rejected events are recorded for /matlist debug.
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    if not frame:IsEventRegistered(event) then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then ns.missingEvents[event] = true end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        ns.Safe("event " .. event, list[i], event, ...)
    end
end)

-- Plain-texture button so we don't depend on Blizzard button templates that may differ in Forever.
function ns.MakeButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.15)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

------------------------------------------------------------------------
-- Saved variables.
-- KNOWN FOREVER BETA BUG: the client writes SavedVariables but may never restore them, so the
-- list can be empty every login. Export/Import is the reliable way to keep a list.
------------------------------------------------------------------------
local function InitDB()
    if type(_G.MatListDB) ~= "table" then _G.MatListDB = {} end
    local db = _G.MatListDB
    db.version = db.version or 1
    db.recipes = type(db.recipes) == "table" and db.recipes or {}
    db.bankCache = type(db.bankCache) == "table" and db.bankCache or {}
    db.bankCache.counts = type(db.bankCache.counts) == "table" and db.bankCache.counts or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.settings.window = type(db.settings.window) == "table" and db.settings.window or {}
    if db.settings.hideCompleted == nil then db.settings.hideCompleted = false end
    db.mats = db.mats or {} -- reserved (Phase 2): per-item flags like vendor / farmed / craftable
    db.alts = db.alts or {} -- reserved (Phase 2): other characters' bag/bank counts
    ns.db = db
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    InitDB()
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then InitDB() end
    if next(ns.db.recipes) == nil then
        ns.Print("list is empty. If you expected saved recipes, SavedVariables may not have been restored (known beta bug) - use /matlist import.")
    end
    if ns.RequestRefresh then ns.RequestRefresh() end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
-- Returns recipeID, qty, hadLink. Accepts "<id> [qty]", "<recipe link> [qty]" or "[qty]".
local function ParseRecipeArgs(args)
    args = args or ""
    local link = args:match("|H.-|h.-|h")
    local rid
    if link then
        rid = tonumber(link:match("enchant:(%d+)")) or tonumber(link:match("recipe:(%d+)"))
        args = args:gsub("|H.-|h.-|h", "")
    end
    args = args:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local nums = {}
    for n in args:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    if link then return rid, nums[1], true end
    return nums[1], nums[2], false
end

local function FindRecipe(text)
    local rid = ParseRecipeArgs(text)
    if rid and ns.db.recipes[rid] then return rid end
    text = (text or ""):lower()
    if text == "" then return nil end
    for id, r in pairs(ns.db.recipes) do
        if r.name and r.name:lower():find(text, 1, true) then return id end
    end
end

local function PrintHelp()
    ns.Print("commands:")
    print("  /matlist - show or hide the shopping list")
    print("  /matlist add [recipeID or link] [qty] - add a recipe (with a recipe selected in the profession window, just '/matlist add 5' makes 5)")
    print("  /matlist set <recipe name or ID> <qty> - change a quantity")
    print("  /matlist remove <recipe name or ID> - remove a recipe")
    print("  /matlist clear - remove everything")
    print("  /matlist export | import - back up / restore your list as text")
    print("  /matlist debug - print diagnostics (paste this to Claude when reporting problems)")
end

local function CmdAdd(rest)
    local rid, qty, hadLink = ParseRecipeArgs(rest)
    local selected = ns.Prof and ns.Prof.GetSelectedRecipeID()
    -- A single bare number with a recipe selected in the profession window means "quantity".
    if not hadLink and rid and not qty and selected then
        qty, rid = rid, selected
    end
    rid = rid or selected
    if not rid then
        ns.Print("no recipe given and none selected. Use /matlist add <recipeID or recipe link> [qty].")
        return
    end
    local ok, info = ns.Data.AddRecipe(rid, qty or 1)
    ns.Print(ok and ("added " .. info) or info)
end

local function Slash(msg)
    if not ns.db then ns.Print("not loaded yet, try again in a moment.") return end
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "toggle" then
        ns.UI.Toggle()
    elseif cmd == "help" or cmd == "?" then
        PrintHelp()
    elseif cmd == "add" then
        CmdAdd(rest)
    elseif cmd == "set" then
        local nameText, q = rest:match("^(.-)%s+(%d+)$")
        local rid = nameText and FindRecipe(nameText)
        if not rid then ns.Print("usage: /matlist set <recipe name or ID> <qty>") return end
        ns.Data.SetQty(rid, tonumber(q))
        local r = ns.db.recipes[rid]
        ns.Print(string.format("%s is now x%d", r and r.name or rid, r and r.qty or 0))
    elseif cmd == "remove" or cmd == "rm" then
        local rid = FindRecipe(rest)
        if not rid then ns.Print("no matching recipe on your list.") return end
        local name = ns.db.recipes[rid].name
        ns.Data.RemoveRecipe(rid)
        ns.Print("removed " .. tostring(name))
    elseif cmd == "clear" then
        ns.Data.Clear()
        ns.Print("list cleared.")
    elseif cmd == "export" then
        ns.UI.ShowExport()
    elseif cmd == "import" then
        ns.UI.ShowImport()
    elseif cmd == "debug" then
        ns.Debug()
    else
        ns.Print("unknown command '" .. cmd .. "'.")
        PrintHelp()
    end
end

_G.SLASH_MATLIST1 = "/matlist"
_G.SlashCmdList["MATLIST"] = function(msg) ns.Safe("slash command", Slash, msg) end

------------------------------------------------------------------------
-- /matlist debug
------------------------------------------------------------------------
function ns.Debug()
    ns.Print("debug v" .. ns.VERSION)
    print("  interface: " .. tostring(select(4, GetBuildInfo())) .. "  WOW_PROJECT_ID: " .. tostring(_G.WOW_PROJECT_ID))
    local n = 0
    for _ in pairs(ns.db.recipes) do n = n + 1 end
    print("  recipes on list: " .. n)
    local missing = {}
    for e in pairs(ns.missingEvents) do missing[#missing + 1] = e end
    print("  events the client rejected: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
    print("  bank open: " .. tostring(ns.Counting.IsBankOpen()))
    print("  tooltip hook: " .. tostring(ns.Tooltip and ns.Tooltip.mode))
    local pf = _G.ProfessionsFrame
    print("  ProfessionsFrame: " .. tostring(pf ~= nil)
        .. "  CraftingPage: " .. tostring(pf ~= nil and pf.CraftingPage ~= nil)
        .. "  SchematicForm: " .. tostring(pf ~= nil and pf.CraftingPage ~= nil and pf.CraftingPage.SchematicForm ~= nil)
        .. "  selected recipe: " .. tostring(ns.Prof.GetSelectedRecipeID()))
    print("  add-button installed: " .. tostring(ns.Prof.button ~= nil))
    local rows = ns.Counting.GetRows()
    for i = 1, math.min(#rows, 10) do
        local r = rows[i]
        local id = r.items[1]
        local bagOnly = C_Item.GetItemCount(id, false) or 0
        local withBank = C_Item.GetItemCount(id, true, false, true, true) or 0
        print(string.format("  %s (%d): bags=%d, GetItemCount(includeBank)=%d, cached bank=%s, need=%d",
            r.name, id, bagOnly, withBank, tostring(ns.db.bankCache.counts[id]), r.need))
    end
    print("  (If includeBank > bags while the bank is CLOSED, the client can count bank items remotely.)")
end
