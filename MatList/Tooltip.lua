-- MatList: adds "MatList: have / need (Recipe A, Recipe B)" to item tooltips.
local ADDON, ns = ...
local Tooltip = { mode = "none" }
ns.Tooltip = Tooltip

local function AddLine(tooltip, itemID)
    if not ns.db or not itemID or not tooltip.AddLine then return end
    -- Midnight "secret values" can appear on restricted paths; never touch one.
    if issecretvalue and issecretvalue(itemID) then return end
    local row = ns.Counting.GetRowForItem(itemID)
    if not row then return end
    local names = {}
    for _, r in ipairs(row.recipes) do names[#names + 1] = r.name end
    local color = row.missing == 0 and "ff80ff80" or "ffffd100"
    tooltip:AddLine(string.format("|c%sMatList:|r %d / %d (%s)", color, row.have, row.need, table.concat(names, ", ")))
end

local function Install()
    -- Preferred (retail 10.0.2+): TooltipDataProcessor. NOT verified for Forever (the API capture
    -- only lists namespaces, not global tables), so check at runtime and fall back to a script hook.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if type(data) ~= "table" then return end
            ns.Safe("tooltip", AddLine, tooltip, data.id)
        end)
        Tooltip.mode = "TooltipDataProcessor"
        return
    end
    if GameTooltip and GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link)
            ns.Safe("tooltip", AddLine, tt, id)
        end)
        if ok then Tooltip.mode = "OnTooltipSetItem (fallback)" return end
    end
    ns.Print("couldn't hook item tooltips on this client; tooltip lines are disabled.")
end

ns.On("PLAYER_LOGIN", function() ns.Safe("tooltip install", Install) end)
