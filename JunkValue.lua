local addonName, ns = ...

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
JunkValueDB = type(JunkValueDB) == "table" and JunkValueDB or {}
local defaults = {
    countEUIJunk = false,
    merchantSummary = false,
    goldOnlyOverOneGold = false,
}
for key, default in pairs(defaults) do
    if type(JunkValueDB[key]) ~= "boolean" then
        JunkValueDB[key] = default
    end
end

local sessionEarned = 0
local scanResult = { total = 0, stackCount = 0, pending = false, stacks = {} }
local merchantOpen = false
local merchantMoneyBefore = 0
local merchantLastMoney = 0
local merchantProceeds = 0
local merchantCarryBefore = 0

local function formatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemainder = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if copperRemainder > 0 or #parts == 0 then parts[#parts + 1] = copperRemainder .. "c" end
    return table.concat(parts, " ")
end

local function formatDisplay(copper)
    if JunkValueDB.goldOnlyOverOneGold and copper > 10000 then
        local gold = math.floor(copper / 10000)
        if GetCoinTextureString then return GetCoinTextureString(gold * 10000) end
        return gold .. "g"
    end
    return formatMoney(copper)
end

local function printMessage(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd6b35aJunkValue:|r " .. message)
    elseif print then
        print("JunkValue: " .. message)
    end
end

local dataObject = LDB:NewDataObject("JunkValue", {
    type = "data source",
    label = "Junk",
    text = "0c",
    icon = "Interface\\AddOns\\JunkValue\\media\\icon",
    OnTooltipShow = function(tooltip)
        -- Tooltip hosts pass their own tooltip/frame here. Always read the exact
        -- scan snapshot used to publish the broker text, never fields on that frame.
        ns.WriteTooltip(tooltip, scanResult, sessionEarned, formatMoney)
    end,
})
ns.dataObject = dataObject

local infoFrame = CreateFrame("Frame")

local function isEUIJunk(itemID)
    if not JunkValueDB.countEUIJunk then return false end
    local manager = _G.EUI_CategoryManager
    if not manager or type(manager.IsJunk) ~= "function" then return false end
    local ok, result = pcall(manager.IsJunk, manager, itemID)
    return ok and not not result
end

local function recordMerchantSale(currentCarry)
    if not merchantOpen then return end
    local moneyNow = GetMoney and GetMoney() or merchantLastMoney
    local finalGain = moneyNow - merchantLastMoney
    if finalGain > 0 then merchantProceeds = merchantProceeds + finalGain end
    sessionEarned = sessionEarned + ns.CalculateMerchantEarnings(merchantProceeds, merchantCarryBefore, currentCarry)
    merchantOpen = false
end

local function scanBags()
    local slots = {}
    for bag = 0, 4 do
        local slotCount = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slotCount do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID then
                local name, itemLink, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(item.itemID)
                if not name then
                    slots[#slots + 1] = {
                        occupied = true,
                        itemID = item.itemID,
                        itemLink = item.hyperlink,
                        quality = nil,
                        sellPrice = nil,
                    }
                else
                    slots[#slots + 1] = {
                        occupied = true,
                        itemID = item.itemID,
                        itemLink = itemLink or item.hyperlink,
                        quality = quality,
                        sellPrice = sellPrice,
                        hasNoValue = item.hasNoValue,
                        markedJunk = isEUIJunk(item.itemID),
                        stackCount = item.stackCount,
                    }
                end
            end
        end
    end

    local total, stackCount, pending, stacks = ns.SumSellableSlots(slots)
    scanResult = { total = total, stackCount = stackCount, pending = pending, stacks = stacks }
    if pending then
        infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        infoFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    dataObject.text = formatDisplay(scanResult.total)
    dataObject.value = scanResult.total
    dataObject.stacks = scanResult.stackCount
    dataObject.pending = scanResult.pending

end

local function setOption(key, value, description)
    JunkValueDB[key] = value
    if key == "countEUIJunk" then scanBags() else dataObject.text = formatDisplay(scanResult.total) end
    printMessage(description)
end

local function toggleOption(key, label)
    local enabled = not JunkValueDB[key]
    setOption(key, enabled, label .. (enabled and " enabled." or " disabled."))
end

local function openOptionsMenu()
    if not (UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton and ToggleDropDownMenu) then
        printMessage("Options menu is unavailable; use /junkvalue marker, /junkvalue summary, or /junkvalue format.")
        return
    end

    if not ns.optionsMenu then
        ns.optionsMenu = CreateFrame("Frame", "JunkValueOptionsMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ns.optionsMenu, function(_, level)
        local options = {
            {
                label = "Include EllesmereUI Junk Marker",
                checked = JunkValueDB.countEUIJunk,
                toggle = function() toggleOption("countEUIJunk", "EllesmereUI Junk Marker") end,
            },
            {
                label = "Merchant carrying summary",
                checked = JunkValueDB.merchantSummary,
                toggle = function() toggleOption("merchantSummary", "Merchant summary") end,
            },
            {
                label = "Gold-only bar text over 1g",
                checked = JunkValueDB.goldOnlyOverOneGold,
                toggle = function() toggleOption("goldOnlyOverOneGold", "Gold-only format") end,
            },
        }
        for _, option in ipairs(options) do
            local menuOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = menuOption.label
            info.checked = menuOption.checked
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.func = menuOption.toggle
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, ns.optionsMenu, "cursor", 0, 0)
end

SLASH_JUNKVALUE1 = "/junkvalue"
SlashCmdList.JUNKVALUE = function(message)
    local option = (message or ""):lower():match("^%s*(.-)%s*$")
    if option == "marker" then
        toggleOption("countEUIJunk", "EllesmereUI Junk Marker")
    elseif option == "summary" then
        toggleOption("merchantSummary", "Merchant summary")
    elseif option == "format" then
        toggleOption("goldOnlyOverOneGold", "Gold-only format")
    else
        printMessage("Use /junkvalue marker, /junkvalue summary, or /junkvalue format to toggle options.")
    end
end

function dataObject:OnClick(button)
    if button == "LeftButton" then
        if ToggleAllBags then ToggleAllBags() end
    elseif button == "RightButton" then
        openOptionsMenu()
    end
end

infoFrame:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        scanBags()
    elseif event == "PLAYER_MONEY" then
        if merchantOpen then
            local moneyNow = GetMoney and GetMoney() or merchantLastMoney
            local gain = moneyNow - merchantLastMoney
            if gain > 0 then merchantProceeds = merchantProceeds + gain end
            merchantLastMoney = moneyNow
        end
    elseif event == "MERCHANT_SHOW" then
        scanBags()
        merchantOpen = true
        merchantMoneyBefore = GetMoney and GetMoney() or 0
        merchantLastMoney = merchantMoneyBefore
        merchantProceeds = 0
        merchantCarryBefore = scanResult.total
        if JunkValueDB.merchantSummary then
            printMessage("Carrying " .. formatMoney(scanResult.total) .. " of sellable junk across " .. tostring(scanResult.stackCount) .. " stacks.")
        end
    elseif event == "MERCHANT_CLOSED" then
        scanBags()
        recordMerchantSale(scanResult.total)
    end
end)
infoFrame:RegisterEvent("BAG_UPDATE_DELAYED")
infoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
infoFrame:RegisterEvent("PLAYER_MONEY")
infoFrame:RegisterEvent("MERCHANT_SHOW")
infoFrame:RegisterEvent("MERCHANT_CLOSED")

scanBags()
