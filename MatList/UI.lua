-- MatList: shopping-list window, recipe manager view, export/import popup.
-- Uses only plain frames/textures/fontstrings (no Blizzard templates) so it doesn't depend on
-- template names that might differ in Forever.
local ADDON, ns = ...
local UI = {}
ns.UI = UI

local ROW_H, HEADER_H, FOOTER_H = 20, 44, 30
local MIN_W, MIN_H = 330, 160
local mode = "mats" -- "mats" | "recipes"
local offset = 0
local rowFrames = {}
local f -- main frame

local COLOR_DONE = { 0.5, 0.5, 0.5 }

local function Win() return ns.db.settings.window end

local function SavePosition()
    if not f then return end
    local w = Win()
    local point, _, relPoint, x, y = f:GetPoint()
    w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
    w.w, w.h = f:GetWidth(), f:GetHeight()
end

local function FormatAge(sec)
    if not sec then return "never (open your bank once)" end
    if sec < 60 then return "just now" end
    if sec < 3600 then return math.floor(sec / 60) .. "m ago" end
    if sec < 86400 then return math.floor(sec / 3600) .. "h ago" end
    return math.floor(sec / 86400) .. "d ago"
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function ShowRowTooltip(row)
    local e = row.entry
    if not e or not e.recipes then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name)
    for _, r in ipairs(e.recipes) do
        GameTooltip:AddLine(string.format("%s: %d", r.name, r.need), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function GetRow(i)
    local r = rowFrames[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.list)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetJustifyH("LEFT")
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -2, 0)
    r.count:SetJustifyH("RIGHT")
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)

    r.del = ns.MakeButton(r, "x", 18, 16, function()
        if r.entry and r.entry.recipeID then ns.Data.RemoveRecipe(r.entry.recipeID) end
    end)
    r.del:SetPoint("RIGHT", -2, 0)
    r.plus = ns.MakeButton(r, "+", 18, 16, function()
        if r.entry and r.entry.recipeID then
            local rec = ns.db.recipes[r.entry.recipeID]
            if rec then ns.Data.SetQty(r.entry.recipeID, rec.qty + 1) end
        end
    end)
    r.plus:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
    r.minus = ns.MakeButton(r, "-", 18, 16, function()
        if r.entry and r.entry.recipeID then
            local rec = ns.db.recipes[r.entry.recipeID]
            if rec then ns.Data.SetQty(r.entry.recipeID, rec.qty - 1) end -- 0 removes the recipe
        end
    end)
    r.minus:SetPoint("RIGHT", r.plus, "LEFT", -2, 0)

    r:SetScript("OnEnter", ShowRowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowFrames[i] = r
    return r
end

local function BuildEntries()
    local out = {}
    if mode == "mats" then
        for _, row in ipairs(ns.Counting.GetRows()) do
            if not (ns.db.settings.hideCompleted and row.missing == 0) then out[#out + 1] = row end
        end
    else
        for _, rec in ipairs(ns.Data.SortedRecipes()) do
            out[#out + 1] = { recipeID = rec.id, name = rec.name, qty = rec.qty }
        end
    end
    return out
end

function UI.Refresh()
    if not f or not f:IsShown() then return end

    f.subtitle:SetText("Bank cache: " .. FormatAge(ns.Counting.BankAge()))
    f.btnMode.text:SetText(mode == "mats" and "Recipes" or "Materials")
    f.btnHide.text:SetText(ns.db.settings.hideCompleted and "Show done" or "Hide done")

    local entries = BuildEntries()
    local listH = math.max(ROW_H, f:GetHeight() - HEADER_H - FOOTER_H)
    local visible = math.max(1, math.floor(listH / ROW_H))
    offset = math.max(0, math.min(offset, #entries - visible))

    for i = 1, visible do
        local e = entries[offset + i]
        local row = GetRow(i)
        if e then
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            if mode == "mats" then
                row.icon:SetTexture(e.icon or 134400) -- 134400 = question mark icon
                row.icon:Show()
                row.minus:Hide() row.plus:Hide() row.del:Hide()
                row.count:Show()
                row.name:SetText(e.name)
                row.count:SetText(string.format("%d / %d%s", e.have, e.need,
                    e.missing > 0 and ("  |cffff5555-" .. e.missing .. "|r") or ""))
                if e.missing == 0 then
                    row.name:SetTextColor(unpack(COLOR_DONE))
                    row.count:SetText("|cff808080" .. string.format("%d / %d", e.have, e.need) .. "|r")
                    row.icon:SetDesaturated(true)
                else
                    row.name:SetTextColor(1, 1, 1)
                    row.icon:SetDesaturated(false)
                end
            else
                row.icon:Hide()
                row.count:Hide()
                row.minus:Show() row.plus:Show() row.del:Show()
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.name:SetPoint("RIGHT", row.minus, "LEFT", -6, 0)
                row.name:SetText(string.format("%s  |cffffd100x%d|r", e.name, e.qty))
                row.name:SetTextColor(1, 1, 1)
            end
            if mode == "mats" then
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
            end
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    for i = visible + 1, #rowFrames do rowFrames[i]:Hide() end

    if #entries == 0 then
        f.empty:SetText(mode == "mats"
            and (next(ns.db.recipes) == nil
                and "Nothing on your list.\nOpen a profession window and use 'Add to MatList',\nor type /matlist add <recipeID> [qty]."
                or "Everything is gathered!")
            or "No recipes on your list.")
        f.empty:Show()
    else
        f.empty:Hide()
    end
end

------------------------------------------------------------------------
-- Popup with a single-line edit box (export = select & copy, import = paste).
------------------------------------------------------------------------
local popup
local function EnsurePopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "MatListPopup", UIParent)
    popup:SetSize(460, 96)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.title:SetPoint("TOPLEFT", 10, -8)
    popup.help = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.help:SetPoint("TOPLEFT", 10, -26)
    local ebBg = popup:CreateTexture(nil, "ARTWORK")
    ebBg:SetPoint("TOPLEFT", 8, -44)
    ebBg:SetPoint("TOPRIGHT", -8, -44)
    ebBg:SetHeight(22)
    ebBg:SetColorTexture(0, 0, 0, 0.7)
    local eb = CreateFrame("EditBox", nil, popup)
    eb:SetPoint("TOPLEFT", ebBg, "TOPLEFT", 4, 0)
    eb:SetPoint("BOTTOMRIGHT", ebBg, "BOTTOMRIGHT", -4, 0)
    eb:SetFontObject("ChatFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() popup:Hide() end)
    popup.edit = eb
    popup.ok = ns.MakeButton(popup, "Import", 70, 20, function()
        if popup.onAccept then popup.onAccept(eb:GetText()) end
    end)
    popup.ok:SetPoint("BOTTOMRIGHT", -84, 6)
    popup.close = ns.MakeButton(popup, "Close", 70, 20, function() popup:Hide() end)
    popup.close:SetPoint("BOTTOMRIGHT", -8, 6)
    table.insert(UISpecialFrames, "MatListPopup") -- Escape closes it
    popup:Hide()
    return popup
end

function UI.ShowExport()
    local p = EnsurePopup()
    p.title:SetText("MatList export")
    p.help:SetText("Press Ctrl+C to copy, then save it somewhere safe.")
    p.ok:Hide()
    p.onAccept = nil
    p.edit:SetText(ns.Data.Export())
    p:Show()
    p.edit:SetFocus()
    p.edit:HighlightText()
end

function UI.ShowImport()
    local p = EnsurePopup()
    p.title:SetText("MatList import")
    p.help:SetText("Paste an export string (Ctrl+V), then click Import. This REPLACES your current list.")
    p.ok:Show()
    p.edit:SetText("")
    p.onAccept = function(text)
        local ok, res = ns.Data.Import(text)
        if ok then
            ns.Print(string.format("imported %d recipe(s).", res))
            p:Hide()
        else
            ns.Print("import failed: " .. tostring(res))
        end
    end
    p:Show()
    p.edit:SetFocus()
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local function Create()
    local w = Win()
    f = CreateFrame("Frame", "MatListFrame", UIParent)
    f:SetSize(w.w or 360, w.h or 300)
    if w.point then
        f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    end
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetFrameStrata("MEDIUM")
    -- Retail 10.0+ uses SetResizeBounds; older API was SetMinResize. Guarded for safety.
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H)
    elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(24)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() SavePosition() end)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.15, 0.15, 0.25, 1)
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetText("MatList")

    local close = ns.MakeButton(bar, "x", 20, 18, function() f:Hide() end)
    close:SetPoint("RIGHT", -3, 0)

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.subtitle:SetPoint("TOPLEFT", 8, -28)

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetPoint("TOPLEFT", 6, -HEADER_H)
    f.list:SetPoint("BOTTOMRIGHT", -6, FOOTER_H)
    f.list:SetClipsChildren(true)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER", f.list, "CENTER")
    f.empty:SetJustifyH("CENTER")

    f:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 2)
        UI.Refresh()
    end)

    -- Footer buttons
    f.btnMode = ns.MakeButton(f, "Recipes", 62, 20, function()
        mode = (mode == "mats") and "recipes" or "mats"
        offset = 0
        UI.Refresh()
    end)
    f.btnMode:SetPoint("BOTTOMLEFT", 6, 6)
    f.btnHide = ns.MakeButton(f, "Hide done", 62, 20, function()
        ns.db.settings.hideCompleted = not ns.db.settings.hideCompleted
        UI.Refresh()
    end)
    f.btnHide:SetPoint("LEFT", f.btnMode, "RIGHT", 3, 0)

    local clearTimer
    f.btnClear = ns.MakeButton(f, "Clear", 50, 20, function(self)
        if self.armed then
            self.armed = false
            self.text:SetText("Clear")
            ns.Data.Clear()
        else
            self.armed = true
            self.text:SetText("Sure?")
            if clearTimer then clearTimer:Cancel() end
            clearTimer = C_Timer.NewTimer(3, function() self.armed = false self.text:SetText("Clear") end)
        end
    end)
    f.btnClear:SetPoint("LEFT", f.btnHide, "RIGHT", 3, 0)
    f.btnExport = ns.MakeButton(f, "Export", 50, 20, UI.ShowExport)
    f.btnExport:SetPoint("LEFT", f.btnClear, "RIGHT", 3, 0)
    f.btnImport = ns.MakeButton(f, "Import", 50, 20, UI.ShowImport)
    f.btnImport:SetPoint("LEFT", f.btnExport, "RIGHT", 3, 0)

    -- Resize grip (bottom-right)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    local gtex = grip:CreateTexture(nil, "OVERLAY")
    gtex:SetAllPoints()
    gtex:SetColorTexture(1, 1, 1, 0.3)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() SavePosition() UI.Refresh() end)
    f:SetScript("OnSizeChanged", function() UI.Refresh() end)

    f:SetScript("OnShow", function()
        Win().shown = true
        ns.Safe("recount", ns.Counting.Recount)
        UI.Refresh()
    end)
    f:SetScript("OnHide", function() Win().shown = false end)
    f:Hide()
end

function UI.Toggle()
    if not f then Create() end
    if f:IsShown() then f:Hide() else f:Show() end
end

function UI.Show()
    if not f then Create() end
    f:Show()
end

-- Restore "was open" state after login.
ns.On("PLAYER_LOGIN", function()
    if ns.db and Win().shown then UI.Show() end
end)
