local addonName, ns = ...

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local defaultSettings = {
    countEUIJunk = false,
    merchantSummary = false,
    goldOnlyOverOneGold = false,
    alwaysJunk = {},
    neverJunk = {},
    showIcon = true,
    iconChoice = "white",
}
local databaseLoaded = false
local settingsPanel
local clearPanelConfirmUntil = 0
local refreshSettingsPanel

local sessionEarned = 0
local scanResult = { total = 0, stackCount = 0, pending = false, stacks = {} }
local merchantOpen = false
local merchantMoneyBefore = 0
local merchantLastMoney = 0
local merchantProceeds = 0
local merchantCarryBefore = 0
local clearConfirmUntil = 0

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
    if not databaseLoaded then return end
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

local function requestClearConfirmation()
    clearConfirmUntil = GetTime() + 10
    printMessage("Type /junkvalue clear confirm within 10s to clear both custom lists.")
end

local function confirmClear()
    local now = GetTime()
    if not ns.IsClearConfirmed(now, clearConfirmUntil) then
        clearConfirmUntil = 0
        printMessage("Clear confirmation expired; type /junkvalue clear to try again.")
        return
    end
    clearConfirmUntil = 0
    wipe(JunkValueDB.alwaysJunk)
    wipe(JunkValueDB.neverJunk)
    scanBags()
    printMessage("Custom lists cleared.")
end

local function setOption(key, value, description)
    JunkValueDB[key] = value
    if key == "countEUIJunk" or key == "showIcon" or key == "iconChoice" then
        if key ~= "countEUIJunk" then updateIcon() end
        scanBags()
    else dataObject.text = formatDisplay(scanResult.total) end
    if refreshSettingsPanel then refreshSettingsPanel() end
    printMessage(description)
end

local function toggleOption(key, label)
    local enabled = not JunkValueDB[key]
    setOption(key, enabled, label .. (enabled and " enabled." or " disabled."))
end

local function applyOption(key, value)
    JunkValueDB[key] = value
    if key == "showIcon" or key == "iconChoice" then updateIcon() end
    scanBags()
    if refreshSettingsPanel then refreshSettingsPanel() end
end

local function openOptionsPanel()
    if InCombatLockdown and InCombatLockdown() then
        printMessage("Options unavailable in combat.")
        return
    end
    if not settingsPanel then
        printMessage("Options are still loading. Try again in a moment.")
        return
    end
    if settingsPanel.category and Settings and type(Settings.OpenToCategory) == "function" then
        local ok, categoryID = pcall(settingsPanel.category.GetID, settingsPanel.category)
        if ok and categoryID ~= nil then
            local opened, result = pcall(Settings.OpenToCategory, categoryID)
            if opened and result ~= false then return end
        end
    end
    if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    else
        printMessage("Options panel is unavailable.")
    end
end

local function itemNameAndIcon(itemID)
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getter then return "Item " .. tostring(itemID), "Interface\\Icons\\INV_Misc_QuestionMark" end
    local name, _, _, _, _, _, _, _, _, icon = getter(itemID)
    return name or ("Item " .. tostring(itemID)), icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function createSettingsPanel()
    if settingsPanel then return end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "JunkValue"
    panel:SetSize(620, 620)
    settingsPanel = panel

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1050)
    scroll:SetScrollChild(content)
    panel.content = content

    local heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -8)
    heading:SetText("JunkValue")
    local preview = content:CreateTexture(nil, "ARTWORK")
    preview:SetSize(32, 32)
    preview:SetPoint("TOPRIGHT", content, "TOPRIGHT", -25, -6)
    panel.preview = preview

    local y = -48
    local function addCheckbox(label, key)
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
        check:SetSize(26, 26)
        local text = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(label)
        check:SetScript("OnClick", function(widget) applyOption(key, not not widget:GetChecked()) end)
        panel[key .. "Check"] = check
        y = y - 30
    end
    addCheckbox("Show icon", "showIcon")

    local iconLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    iconLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
    iconLabel:SetText("Icon")
    y = y - 25
    for _, entry in ipairs({ { "white", "White glyph" }, { "pouch", "Pouch" }, { "coin", "Coin" } }) do
        local choice, label = entry[1], entry[2]
        local radio = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        radio:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
        radio:SetSize(26, 26)
        local text = radio:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", radio, "RIGHT", 4, 0)
        text:SetText(label)
        radio:SetScript("OnClick", function() applyOption("iconChoice", choice) end)
        panel["icon_" .. choice] = radio
        y = y - 28
    end
    addCheckbox("Vendor summary", "merchantSummary")
    addCheckbox("Gold-only display over 1g", "goldOnlyOverOneGold")
    addCheckbox("Include EllesmereUI Junk Marker", "countEUIJunk")

    local addListSection
    local function addItemEntry(itemID, list, rowY)
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(520, 28)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 12, rowY)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        local name, texture = itemNameAndIcon(itemID)
        icon:SetTexture(texture)
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetWidth(390)
        label:SetJustifyH("LEFT")
        label:SetText(name .. " (" .. tostring(itemID) .. ")")
        local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        remove:SetSize(78, 22)
        remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        remove:SetText("Remove")
        remove:SetScript("OnClick", function()
            list[itemID] = nil
            scanBags()
            addListSection()
        end)
        return row
    end

    local listRows = {}
    local listStartY
    addListSection = function()
        for _, row in ipairs(listRows) do row:Hide() end
        listRows = {}
        local rowY = listStartY or y
        for _, section in ipairs({ { "Always junk", JunkValueDB.alwaysJunk }, { "Never junk", JunkValueDB.neverJunk } }) do
            local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", content, "TOPLEFT", 12, rowY)
            title:SetText(section[1])
            listRows[#listRows + 1] = title
            rowY = rowY - 27
            local ids = {}
            for id, enabled in pairs(section[2]) do if enabled then ids[#ids + 1] = tonumber(id) or id end end
            table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
            if #ids == 0 then
                local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                empty:SetPoint("TOPLEFT", content, "TOPLEFT", 18, rowY)
                empty:SetText("No items")
                listRows[#listRows + 1] = empty
                rowY = rowY - 24
            else
                for _, id in ipairs(ids) do
                    listRows[#listRows + 1] = addItemEntry(id, section[2], rowY)
                    rowY = rowY - 30
                end
            end
        end
        content:SetHeight(math.max(1050, -rowY + 120))
    end

    local itemInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    itemInput:SetSize(250, 26)
    itemInput:SetAutoFocus(false)
    itemInput:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y - 44)
    itemInput:SetTextInsets(6, 6, 0, 0)
    itemInput:SetHyperlinksEnabled(true)
    itemInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.itemInput = itemInput
    local neverTarget = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    neverTarget:SetSize(26, 26)
    neverTarget:SetPoint("TOPLEFT", content, "TOPLEFT", 270, y - 12)
    local targetLabel = neverTarget:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    targetLabel:SetPoint("LEFT", neverTarget, "RIGHT", 4, 0)
    targetLabel:SetText("Add to Never junk")
    panel.neverTarget = neverTarget
    local addButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addButton:SetSize(80, 24)
    addButton:SetPoint("LEFT", itemInput, "RIGHT", 8, 0)
    addButton:SetText("Add")
    panel.addButton = addButton

    local clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearButton:SetSize(150, 24)
    clearButton:SetPoint("LEFT", addButton, "RIGHT", 10, 0)
    clearButton:SetText("Clear lists")
    clearButton:SetScript("OnClick", function(self)
        local now = GetTime()
        if clearPanelConfirmUntil > 0 and now <= clearPanelConfirmUntil then
            wipe(JunkValueDB.alwaysJunk)
            wipe(JunkValueDB.neverJunk)
            clearPanelConfirmUntil = 0
            self:SetText("Clear lists")
            scanBags()
            addListSection()
        else
            clearPanelConfirmUntil = now + 5
            self:SetText("Click again to confirm")
        end
    end)
    clearButton:SetScript("OnUpdate", function(self)
        if clearPanelConfirmUntil > 0 and GetTime() > clearPanelConfirmUntil then
            clearPanelConfirmUntil = 0
            self:SetText("Clear lists")
        end
    end)

    local function addItem(argument)
        local id = ns.ParseItemID(argument)
        if not id then printMessage("Enter an item link or numeric item ID."); return end
        local list = neverTarget:GetChecked() and JunkValueDB.neverJunk or JunkValueDB.alwaysJunk
        list[id] = true
        scanBags()
        addListSection()
        itemInput:SetText("")
    end
    addButton:SetScript("OnClick", function() addItem(itemInput:GetText()) end)
    if type(hooksecurefunc) == "function" and type(HandleModifiedItemClick) == "function" then
        pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
            if IsShiftKeyDown and IsShiftKeyDown() and itemInput:HasFocus() and type(link) == "string" and link:find("item:%d+") then
                itemInput:SetText(link)
                itemInput:SetCursorPosition(0)
            end
        end)
    end

    local footer = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    footer:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", 0, -8)
    footer:SetText("Paste an item link or ID. Shift-click an item while this field is focused to insert its link.")
    panel.footer = footer
    listStartY = y - 82
    panel:SetScript("OnShow", function() if refreshSettingsPanel then refreshSettingsPanel() end end)

    refreshSettingsPanel = function()
        if not settingsPanel then return end
        for _, key in ipairs({ "showIcon", "merchantSummary", "goldOnlyOverOneGold", "countEUIJunk" }) do
            panel[key .. "Check"]:SetChecked(not not JunkValueDB[key])
        end
        for _, choice in ipairs({ "white", "pouch", "coin" }) do
            panel["icon_" .. choice]:SetChecked(JunkValueDB.iconChoice == choice)
        end
        preview:SetTexture(icons[JunkValueDB.iconChoice] or icons.white)
        preview:SetAlpha(JunkValueDB.showIcon and 1 or 0.35)
        addListSection()
    end

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "JunkValue")
        if ok and category then
            settingsPanel.category = category
            local registered = pcall(Settings.RegisterAddOnCategory, category)
            if not registered then settingsPanel.category = nil end
        end
    end
    if not settingsPanel.category and type(InterfaceOptions_AddCategory) == "function" then
        pcall(InterfaceOptions_AddCategory, panel)
    end
    refreshSettingsPanel()
end

SLASH_JUNKVALUE1 = "/junkvalue"
local function listEntries()
    local a, n = {}, {}
    for id in pairs(JunkValueDB.alwaysJunk) do a[#a + 1] = tostring(id) end
    for id in pairs(JunkValueDB.neverJunk) do n[#n + 1] = tostring(id) end
    table.sort(a); table.sort(n)
    printMessage("Always junk (" .. #a .. "): " .. (#a > 0 and table.concat(a, ", ") or "none"))
    printMessage("Never junk (" .. #n .. "): " .. (#n > 0 and table.concat(n, ", ") or "none"))
end
SlashCmdList.JUNKVALUE = function(message)
    local cmd, arg = ns.ParseSlashCommand(message)
    if cmd == "" then openOptionsPanel(); return end
    local itemID = ns.ParseItemID(arg)
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
    elseif cmd == "list" then listEntries()
    elseif cmd == "clear" and not arg then
        requestClearConfirmation()
    elseif cmd == "clear" and arg and arg:lower() == "confirm" then
        confirmClear()
    elseif cmd == "icon" then
        toggleOption("showIcon", "Icon")
    elseif cmd == "debug" then
        printMessage("Container click hook: " .. tostring(ns.hookStatus.container) .. "; item tooltip hook: " .. tostring(ns.hookStatus.tooltip) .. ".")
    elseif cmd == "marker" then
        toggleOption("countEUIJunk", "EllesmereUI Junk Marker")
    elseif cmd == "summary" then
        toggleOption("merchantSummary", "Merchant summary")
    elseif cmd == "format" then
        toggleOption("goldOnlyOverOneGold", "Gold-only format")
    else
        printMessage("Use /junkvalue with no command for options, or add/remove/never <itemlink or id>, list, clear, icon, debug, marker, summary, or format.")
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
        openOptionsPanel()
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

infoFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = select(1, ...)
        if loadedName == addonName and not databaseLoaded then
            JunkValueDB = ns.MergeDefaults(JunkValueDB, defaultSettings)
            databaseLoaded = true
            updateIcon()
            scanBags()
            if not InCombatLockdown or not InCombatLockdown() then
                createSettingsPanel()
            else
                infoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and databaseLoaded and not settingsPanel then
        infoFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        createSettingsPanel()
        return
    end
    if not databaseLoaded then return end
    if event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        scanBags()
        if event == "GET_ITEM_INFO_RECEIVED" and refreshSettingsPanel then refreshSettingsPanel() end
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
infoFrame:RegisterEvent("ADDON_LOADED")
infoFrame:RegisterEvent("BAG_UPDATE_DELAYED")
infoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
infoFrame:RegisterEvent("PLAYER_MONEY")
infoFrame:RegisterEvent("MERCHANT_SHOW")
infoFrame:RegisterEvent("MERCHANT_CLOSED")
