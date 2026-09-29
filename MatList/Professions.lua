-- MatList: "Add to MatList" button on the profession window.
-- The profession UI (Blizzard_Professions) is load-on-demand and its internal structure is NOT
-- verified for Forever. Everything here is nil-checked; if something's missing we say so once in chat
-- and /matlist add still works.
local ADDON, ns = ...
local Prof = {}
ns.Prof = Prof

local warned = false

local function GetForm()
    local pf = _G.ProfessionsFrame
    local page = pf and pf.CraftingPage
    return page and page.SchematicForm
end

-- Currently displayed recipe: tries the form's schematic, then its recipe info, then the last recipe
-- seen by our Init hook.
function Prof.GetSelectedRecipeID()
    local form = GetForm()
    if form then
        local s = form.recipeSchematic
        if type(s) == "table" and tonumber(s.recipeID) then return s.recipeID end
        if type(form.GetRecipeInfo) == "function" then
            local ok, info = pcall(form.GetRecipeInfo, form)
            if ok and type(info) == "table" and tonumber(info.recipeID) then return info.recipeID end
        end
    end
    return Prof.lastRecipeID
end

local function UpdateButtonLabel()
    if not Prof.button then return end
    local rid = Prof.GetSelectedRecipeID()
    local rec = rid and ns.db and ns.db.recipes[rid]
    Prof.button.text:SetText(rec and "Add more to MatList" or "Add to MatList")
end

local function OnAddClicked()
    local rid = Prof.GetSelectedRecipeID()
    if not rid then
        ns.Print("select a recipe first (or use /matlist add <recipeID>).")
        return
    end
    local qty = tonumber(Prof.qtyBox:GetText()) or 1
    local ok, info = ns.Data.AddRecipe(rid, qty)
    ns.Print(ok and ("added " .. info) or info)
    UpdateButtonLabel()
end

function Prof.Install()
    if Prof.button then return true end
    local pf = _G.ProfessionsFrame
    if not pf then return false end

    -- Placed just below the profession window so it can't overlap Blizzard's own buttons.
    -- Layout is a guess; tell Claude if it looks wrong.
    local holder = CreateFrame("Frame", nil, pf)
    holder:SetSize(190, 24)
    holder:SetPoint("TOPRIGHT", pf, "BOTTOMRIGHT", 0, -2)
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.85)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetText("Qty")

    local ebBg = holder:CreateTexture(nil, "ARTWORK")
    ebBg:SetSize(36, 18)
    ebBg:SetPoint("LEFT", label, "RIGHT", 4, 0)
    ebBg:SetColorTexture(0, 0, 0, 0.8)
    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetAllPoints(ebBg)
    eb:SetFontObject("ChatFontNormal")
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(4)
    eb:SetJustifyH("CENTER")
    eb:SetText("1")
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    Prof.qtyBox = eb

    Prof.button = ns.MakeButton(holder, "Add to MatList", 118, 20, OnAddClicked)
    Prof.button:SetPoint("RIGHT", -3, 0)
    Prof.holder = holder

    -- Remember the last recipe the form was initialised with (hooksecurefunc never taints Blizzard code).
    local form = GetForm()
    if form and type(form.Init) == "function" then
        pcall(hooksecurefunc, form, "Init", function(_, recipeInfo)
            if type(recipeInfo) == "table" and tonumber(recipeInfo.recipeID) then
                Prof.lastRecipeID = recipeInfo.recipeID
            end
            UpdateButtonLabel()
        end)
    end
    return true
end

local function TryInstall(reason)
    if not ns.db then return end
    if Prof.Install() then return end
    if reason == "shown" and not warned then
        warned = true
        ns.Print("couldn't find the profession window (ProfessionsFrame) - use /matlist add <recipeID> instead. Run /matlist debug for details.")
    end
end

ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_Professions" then C_Timer.After(0, function() TryInstall("loaded") end) end
end)
ns.On("PLAYER_LOGIN", function() TryInstall("login") end)
ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.2, function() TryInstall("shown") end) end)
