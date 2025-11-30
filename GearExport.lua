-- ======================================
-- GearExport v7.7 (Ordered JSON + Weapon Type)
-- ======================================

DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99GearExport v7.7 loaded!|r")

local DEBUG = false -- set true for verbose output

-------------------------------------------------
-- Utility: strip color codes / item links
-------------------------------------------------
local function CleanLink(text)
    if type(text) ~= "string" then text = tostring(text or "") end
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|Hitem:[^|]+|h(.-)|h", "%1")
    return text
end

-------------------------------------------------
-- Fixed stat order
-------------------------------------------------
local STAT_ORDER = {
    "str", "agi", "int", "spi", "sta",
    "hit", "crit", "ap",
    "strEnchant", "agiEnchant", "intEnchant", "spiEnchant", "staEnchant"
}

-------------------------------------------------
-- JSON encoder (ordered for stats)
-------------------------------------------------
local function toJSON(tbl)
    local function escape(val)
        if val == nil then return "" end
        if type(val) ~= "string" then val = tostring(val) end
        val = string.gsub(val, '"', '\\"')
        return val
    end

    local function serialize(v, key)
        local t = type(v)
        if t == "table" then
            local parts = {}

            -- If it's a stats table, serialize in our fixed order
            if key == "stats" then
                for _, statKey in ipairs(STAT_ORDER) do
                    if v[statKey] ~= nil then
                        table.insert(parts, '"' .. statKey .. '":' .. serialize(v[statKey]))
                    end
                end
            else
                -- Normal unordered table
                for k, val in pairs(v) do
                    table.insert(parts, '"' .. escape(k) .. '":' .. serialize(val, k))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"

        elseif t == "string" then
            return '"' .. escape(v) .. '"'
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        else
            return '""'
        end
    end
    return serialize(tbl)
end

-------------------------------------------------
-- Equipment slot names
-------------------------------------------------
local slotNames = {
    [1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",[6]="Waist",
    [7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",[11]="Finger1",[12]="Finger2",
    [13]="Trinket1",[14]="Trinket2",[15]="Back",[16]="MainHand",[17]="OffHand",[18]="Ranged"
}

-------------------------------------------------
-- Tooltip scanner setup
-------------------------------------------------
local scanner = CreateFrame("GameTooltip", "GE_TooltipScanner", UIParent, "GameTooltipTemplate")
for i=1,30 do
    scanner:AddFontStrings(
        scanner:CreateFontString("GE_TooltipScannerTextLeft"..i, nil, "GameTooltipText"),
        scanner:CreateFontString("GE_TooltipScannerTextRight"..i, nil, "GameTooltipText")
    )
end

-------------------------------------------------
-- Tooltip stat extraction
-------------------------------------------------
local function GetItemStats(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return nil end

    local baseStats = {str=0,agi=0,sta=0,int=0,spi=0,ap=0,crit=0,hit=0}
    local enchStats = {str=0,agi=0,sta=0,int=0,spi=0}

    local lines = {}
    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetInventoryItem("player", slotId)
    scanner:Show()

    for i=1,30 do
        local left = _G["GE_TooltipScannerTextLeft"..i]
        if left and left.GetText then
            local raw = left:GetText()
            if raw and raw ~= "" then
                table.insert(lines, string.lower(raw))
            end
        end
    end

    for _, text in ipairs(lines) do
        local function parseStat(statName, key)
            local base = tonumber(string.match(text, "^%+(%d+)%s*" .. statName))
            local ench = tonumber(string.match(text, statName .. "%s*%+(%d+)"))
            if base then
                baseStats[key] = baseStats[key] + base
            elseif ench then
                enchStats[key] = enchStats[key] + ench
            end
        end

        parseStat("strength","str")
        parseStat("agility","agi")
        parseStat("stamina","sta")
        parseStat("intellect","int")
        parseStat("spirit","spi")

        local ap = tonumber(string.match(text,"equip:%s*%+(%d+)%s*attack power"))
            or tonumber(string.match(text,"%+(%d+)%s*attack power"))
            or tonumber(string.match(text,"ranged attack power[^%d]*(%d+)"))
            or tonumber(string.match(text,"increases attack power by%s*(%d+)"))
        if ap then baseStats.ap = baseStats.ap + ap end

        local crit = tonumber(string.match(text,"critical[^%d]*(%d+%.?%d*)"))
            or tonumber(string.match(text,"crit[^%d]*(%d+%.?%d*)"))
        if crit then baseStats.crit = baseStats.crit + crit end

        local hit = tonumber(string.match(text,"chance to hit[^%d]*(%d+%.?%d*)"))
            or tonumber(string.match(text,"hit[^%d]*(%d+%.?%d*)"))
        if hit then baseStats.hit = baseStats.hit + hit end
    end

    local stats = {
        str=baseStats.str, agi=baseStats.agi, int=baseStats.int, spi=baseStats.spi, sta=baseStats.sta,
        hit=baseStats.hit, crit=baseStats.crit, ap=baseStats.ap,
        strEnchant=enchStats.str, agiEnchant=enchStats.agi, intEnchant=enchStats.int, spiEnchant=enchStats.spi, staEnchant=enchStats.sta
    }

    -------------------------------------------------
    -- Weapon info
    -------------------------------------------------
    local weaponInfo
    if slotId == 16 or slotId == 17 or slotId == 18 then
        local minDmg, maxDmg, dps
        for i=1,30 do
            local left = _G["GE_TooltipScannerTextLeft"..i]
            if left and left:GetText() then
                local line = string.lower(left:GetText())
                local a,b = string.match(line,"(%d+)%s*%-%s*(%d+)%s*damage")
                if a and b then minDmg,maxDmg = tonumber(a),tonumber(b) end
                local dpsVal = string.match(line,"%((%d+%.?%d*)%s*damage per second%)")
                if dpsVal then dps = tonumber(dpsVal) end
            end
        end
        if minDmg and maxDmg and dps then
            local avg = (minDmg + maxDmg) / 2
            local speed = avg / dps
            local _, _, _, _, _, _, _, _, _, _, _, _, itemSubType = GetItemInfo(link)
            weaponInfo = {
                type = itemSubType or "Unknown",
                min = minDmg, max = maxDmg,
                speed = math.floor(speed * 100 + 0.5) / 100,
                dps = dps
            }
        end
    end

    return stats, CleanLink(link), weaponInfo
end

-------------------------------------------------
-- Build gear JSON
-------------------------------------------------
local function GenerateGearJSON()
    local gear = {}
    for slotId, slotName in pairs(slotNames) do
        local stats, link, weaponInfo = GetItemStats(slotId)
        if link then
            gear[slotName] = { item = link, stats = stats }
            if weaponInfo then gear[slotName].weapon = weaponInfo end
        end
    end
    return toJSON(gear)
end

-------------------------------------------------
-- Simple window UI
-------------------------------------------------
local frame = CreateFrame("Frame","GE_MainFrame",UIParent)
frame:SetWidth(600); frame:SetHeight(400)
frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
frame:SetBackdrop({
    bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    tile=true,tileSize=16,edgeSize=16,
    insets={left=4,right=4,top=4,bottom=4}
})
frame:SetBackdropColor(0,0,0,0.8)
frame:EnableMouse(true); frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart",function() frame:StartMoving() end)
frame:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
frame:Hide()

local title = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
title:SetPoint("TOP",0,-10); title:SetText("Gear Export")

local scroll = CreateFrame("ScrollFrame","GE_ScrollFrame",frame,"UIPanelScrollFrameTemplate")
scroll:SetWidth(560); scroll:SetHeight(320)
scroll:SetPoint("TOPLEFT",20,-40)

local editBox = CreateFrame("EditBox","GE_EditBox",scroll)
editBox:SetWidth(560); editBox:SetHeight(320)
editBox:SetMultiLine(true); editBox:SetAutoFocus(false)
editBox:SetFontObject(GameFontHighlightSmall)
editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
editBox:SetScript("OnEditFocusGained", function() editBox:HighlightText() end)
scroll:SetScrollChild(editBox)
frame.editBox = editBox

local btn = CreateFrame("Button","GE_GenerateButton",frame,"UIPanelButtonTemplate")
btn:SetWidth(140); btn:SetHeight(24)
btn:SetPoint("BOTTOM",frame,"BOTTOM",0,10)
btn:SetText("Generate JSON")
btn:SetScript("OnClick",function()
    local json = GenerateGearJSON()
    frame.editBox:SetText(json)
    frame.editBox:HighlightText()
end)

SLASH_GEAR_EXPORT1 = "/gearjson"
SlashCmdList["GEAR_EXPORT"] = function()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
