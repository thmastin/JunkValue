local addonName, ns = ...

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
JunkValueDB = type(JunkValueDB) == "table" and JunkValueDB or {}
local defaults = {
    countEUIJunk = false,
    merchantSummary = false,
    goldOnlyOverOneGold = false,
    alwaysJunk = {},
    neverJunk = {},
    showIcon = true,
    iconChoice = "white",
}
for key, default in pairs(defaults) do
    if type(JunkValueDB[key]) ~= "boolean" then
        JunkValueDB[key] = default
    end
end
for _, key in ipairs({"alwaysJunk", "neverJunk"}) do
    if type(JunkValueDB[key]) ~= "table" then JunkValueDB[key] = {} end
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
    icon = nil,
    OnTooltipShow = function(tooltip)
        -- Tooltip hosts pass their own tooltip/frame here. Always read the exact
        -- scan snapshot used to publish the broker text, never fields on that frame.
        ns.WriteTooltip(tooltip, scanResult, sessionEarned, formatMoney)
    end,
})
ns.dataObject = dataObject
local icons = {
    white = "Interface\\AddOns\\JunkValue\\media\\icon-white",
    pouch = "Interface\\AddOns\\JunkValue\\media\\icon",
    coin = "Interface\\Icons\\INV_Misc_Coin_01",
}
local function updateIcon()
    dataObject.icon = ns.ResolveIcon(JunkValueDB.showIcon, JunkValueDB.iconChoice, icons)
end
if not icons[JunkValueDB.iconChoice] then JunkValueDB.iconChoice = "white" end
updateIcon()

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

    local total, stackCount, pending, stacks, noPriceCustom = ns.SumSellableSlots(slots, JunkValueDB.alwaysJunk, JunkValueDB.neverJunk)
    scanResult = { total = total, stackCount = stackCount, pending = pending, stacks = stacks, noPriceCustom = noPriceCustom }
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
    if key == "countEUIJunk" or key == "showIcon" or key == "iconChoice" then
        if key ~= "countEUIJunk" then updateIcon() end
        scanBags()
    else dataObject.text = formatDisplay(scanResult.total) end
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
        local alwaysCount, neverCount = 0, 0
        for _ in pairs(JunkValueDB.alwaysJunk) do alwaysCount = alwaysCount + 1 end
        for _ in pairs(JunkValueDB.neverJunk) do neverCount = neverCount + 1 end
        local options = {
            { label = "Custom lists: " .. alwaysCount .. " always / " .. neverCount .. " kept", title = true },
            { label = "Clear custom lists...", toggle = function() if StaticPopup_Show then StaticPopup_Show("JUNKVALUE_CLEAR") end end },
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
            { label = "Show icon", checked = JunkValueDB.showIcon, toggle = function() toggleOption("showIcon", "Icon") end },
            { label = "Icon: white glyph", checked = JunkValueDB.iconChoice == "white", toggle = function() setOption("iconChoice", "white", "White icon selected.") end },
            { label = "Icon: pouch", checked = JunkValueDB.iconChoice == "pouch", toggle = function() setOption("iconChoice", "pouch", "Pouch icon selected.") end },
            { label = "Icon: coin", checked = JunkValueDB.iconChoice == "coin", toggle = function() setOption("iconChoice", "coin", "Coin icon selected.") end },
        }
        for _, option in ipairs(options) do
            local menuOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = menuOption.label
            info.checked = menuOption.checked
            info.isTitle = menuOption.title
            info.disabled = menuOption.title
            info.isNotRadio = not menuOption.label:match("^Icon:")
            info.keepShownOnClick = true
            info.func = menuOption.toggle
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, ns.optionsMenu, "cursor", 0, 0)
end

SLASH_JUNKVALUE1 = "/junkvalue"
local function resolveItemID(arg)
    return tonumber(arg and (arg:match("item:(%d+)") or arg:match("^%s*(%d+)%s*$")))
end
local function listEntries()
    local a, n = {}, {}
    for id in pairs(JunkValueDB.alwaysJunk) do a[#a + 1] = tostring(id) end
    for id in pairs(JunkValueDB.neverJunk) do n[#n + 1] = tostring(id) end
    table.sort(a); table.sort(n)
    printMessage("Always junk (" .. #a .. "): " .. (#a > 0 and table.concat(a, ", ") or "none"))
    printMessage("Never junk (" .. #n .. "): " .. (#n > 0 and table.concat(n, ", ") or "none"))
end
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs.JUNKVALUE_CLEAR = {
    text = "Clear all JunkValue custom item lists?", button1 = YES, button2 = NO,
    OnAccept = function()
        wipe(JunkValueDB.alwaysJunk); wipe(JunkValueDB.neverJunk); scanBags(); printMessage("Custom lists cleared.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
SlashCmdList.JUNKVALUE = function(message)
    local option = (message or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = option:match("^(%S+)%s+(.+)$")
    local itemID = resolveItemID(arg)
    if cmd == "add" or cmd == "never" or cmd == "remove" then
        if not itemID then printMessage("Provide an item link or numeric item ID."); return end
        if cmd == "remove" then
            JunkValueDB.alwaysJunk[itemID], JunkValueDB.neverJunk[itemID] = nil, nil
            printMessage("Removed " .. itemID .. " from custom lists.")
        elseif cmd == "add" then
            JunkValueDB.alwaysJunk[itemID] = true; printMessage("Always junk: " .. itemID .. ".")
        else
            JunkValueDB.neverJunk[itemID] = true; printMessage("Never junk: " .. itemID .. ".")
        end
        scanBags()
    elseif option == "list" then listEntries()
    elseif option == "clear" then
        if StaticPopup_Show then StaticPopup_Show("JUNKVALUE_CLEAR") else printMessage("Confirmation popup unavailable.") end
    elseif option == "icon" then
        toggleOption("showIcon", "Icon")
    elseif option == "debug" then
        printMessage("Container click hook: " .. tostring(ns.hookStatus.container) .. "; item tooltip hook: " .. tostring(ns.hookStatus.tooltip) .. ".")
    elseif option == "marker" then
        toggleOption("countEUIJunk", "EllesmereUI Junk Marker")
    elseif option == "summary" then
        toggleOption("merchantSummary", "Merchant summary")
    elseif option == "format" then
        toggleOption("goldOnlyOverOneGold", "Gold-only format")
    else
        printMessage("Use add/remove/never <itemlink or id>, list, clear, icon, debug, marker, summary, or format.")
    end
end

local function toggleCustomItem(itemID, quality)
    local list = quality == 0 and JunkValueDB.neverJunk or JunkValueDB.alwaysJunk
    if list[itemID] then list[itemID] = nil; printMessage("Removed " .. itemID .. " from custom list.")
    else list[itemID] = true; printMessage((quality == 0 and "Kept " or "Always junk ") .. itemID .. ".") end
    scanBags()
end
local function handleBagModifiedClick(button, mouseButton)
    if mouseButton ~= "RightButton" or not IsAltKeyDown or not IsAltKeyDown() then return end
    local bag, slot = button:GetParent() and button:GetParent():GetID(), button:GetID()
    if not bag or not slot then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return end
    local _, _, quality = C_Item.GetItemInfo(info.itemID)
    if quality ~= nil then toggleCustomItem(info.itemID, quality) end
end
ns.hookStatus = { container = "not installed", tooltip = "not installed" }
if type(hooksecurefunc) == "function" and type(ContainerFrameItemButton_OnModifiedClick) == "function" and type(handleBagModifiedClick) == "function" then
    local ok = pcall(hooksecurefunc, "ContainerFrameItemButton_OnModifiedClick", handleBagModifiedClick)
    ns.hookStatus.container = ok and "installed" or "installation failed"
else
    ns.hookStatus.container = "handler unavailable"
end

function dataObject:OnClick(button)
    if button == "LeftButton" then
        if ToggleAllBags then ToggleAllBags() end
    elseif button == "RightButton" then
        openOptionsMenu()
    end
end

local function appendItemListTooltip(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    local id = tonumber(link and (link:match("item:(%d+)") or link:match("^%s*(%d+)%s*$")))
    if not id then return end
    if JunkValueDB.neverJunk[id] then tooltip:AddLine("JunkValue: kept (custom)", 1, .8, .3)
    elseif JunkValueDB.alwaysJunk[id] then tooltip:AddLine("JunkValue: always junk (custom)", 1, .8, .3) end
end
local tooltipHookable, tooltipReason = ns.CanHookScript(GameTooltip, "OnTooltipSetItem", appendItemListTooltip)
if tooltipHookable then
    local ok = pcall(function() GameTooltip:HookScript("OnTooltipSetItem", appendItemListTooltip) end)
    ns.hookStatus.tooltip = ok and "installed" or "installation failed"
else
    ns.hookStatus.tooltip = tooltipReason
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
