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
local updateAltTip
local euiRescanPending = false
local hookedEUIButtons = setmetatable({}, { __mode = "k" })
local euiRefreshHooks = setmetatable({}, { __mode = "k" })

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
    if refreshSettingsPanel then refreshSettingsPanel(true) end
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
    panel:SetSize(660, 660)
    settingsPanel = panel

    local panelWidth = 660
    local function sectionHeader(text, anchor, first)
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetTextColor(0.90, 0.72, 0.32)
        header:SetText(text)
        if first then header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
        else header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -8, -16) end
        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(0.68, 0.52, 0.25, 0.65)
        divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        divider:SetSize(panelWidth - 32, 1)
        return header, divider
    end

    local displayHeader, displayDivider = sectionHeader("Display", nil, true)

    local showIcon = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showIcon:SetSize(26, 26)
    showIcon:SetPoint("TOPLEFT", displayDivider, "BOTTOMLEFT", 8, -8)
    local showIconText = showIcon:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    showIconText:SetPoint("LEFT", showIcon, "RIGHT", 4, 0)
    showIconText:SetText("Show icon")
    showIcon:SetScript("OnClick", function(widget) applyOption("showIcon", not not widget:GetChecked()) end)
    panel.showIconCheck = showIcon

    local iconLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    iconLabel:SetText("Icon")
    iconLabel:SetPoint("TOPLEFT", showIcon, "BOTTOMLEFT", 0, -8)
    local choices = {}
    local previousChoice
    for index, entry in ipairs({ { "white", "White glyph" }, { "pouch", "Pouch" }, { "coin", "Coin" } }) do
        local choice, label = entry[1], entry[2]
        local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        radio:SetSize(24, 24)
        if index == 1 then radio:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -4)
        else radio:SetPoint("LEFT", previousChoice, "RIGHT", 18, 0) end
        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", radio, "RIGHT", 1, 0)
        text:SetText(label)
        local preview = panel:CreateTexture(nil, "ARTWORK")
        preview:SetSize(20, 20)
        preview:SetPoint("LEFT", text, "RIGHT", 5, 0)
        preview:SetTexture(icons[choice])
        radio:SetScript("OnClick", function() applyOption("iconChoice", choice) end)
        panel["icon_" .. choice] = radio
        choices[#choices + 1] = radio
        previousChoice = preview
    end

    local behaviorHeader, behaviorDivider = sectionHeader("Behavior", choices[1])
    local previousBehavior = behaviorDivider
    local function addBehaviorCheck(label, key)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        if previousBehavior == behaviorDivider then check:SetPoint("TOPLEFT", previousBehavior, "BOTTOMLEFT", 8, -8)
        else check:SetPoint("TOPLEFT", previousBehavior, "BOTTOMLEFT", 0, -8) end
        local text = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(label)
        check:SetScript("OnClick", function(widget) applyOption(key, not not widget:GetChecked()) end)
        panel[key .. "Check"] = check
        previousBehavior = check
    end
    addBehaviorCheck("Vendor summary", "merchantSummary")
    addBehaviorCheck("Gold-only display over 1g", "goldOnlyOverOneGold")
    addBehaviorCheck("Include EllesmereUI Junk Marker", "countEUIJunk")

    local customHeader, customDivider = sectionHeader("Custom junk", previousBehavior)
    local itemInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    itemInput:SetSize(260, 26)
    itemInput:SetAutoFocus(false)
    itemInput:SetPoint("TOPLEFT", customDivider, "BOTTOMLEFT", 8, -8)
    itemInput:SetTextInsets(6, 6, 0, 0)
    itemInput:SetHyperlinksEnabled(true)
    itemInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.itemInput = itemInput

    local addAlways = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addAlways:SetSize(112, 24)
    addAlways:SetPoint("LEFT", itemInput, "RIGHT", 10, 0)
    addAlways:SetText("Add to Always")
    local addNever = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addNever:SetSize(112, 24)
    addNever:SetPoint("LEFT", addAlways, "RIGHT", 8, 0)
    addNever:SetText("Add to Never")

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetTextColor(0.68, 0.68, 0.68)
    help:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", 0, -4)
    help:SetText("Paste an item link or ID. Shift-click an item while this box is focused.")

    local columnWidth, listHeight = 298, 200
    local function createListColumn(title, list, xOffset)
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetText(title)
        header:SetPoint("TOPLEFT", help, "BOTTOMLEFT", xOffset, -12)

        local box = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
        box:SetSize(columnWidth, listHeight)
        box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
        if box.SetBackdrop then
            box:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            box:SetBackdropColor(0.035, 0.035, 0.035, 0.95)
            box:SetBackdropBorderColor(0.42, 0.42, 0.42, 0.9)
        end

        local scroll = CreateFrame("ScrollFrame", nil, box)
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -22, 8)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(columnWidth - 32, listHeight - 16)
        scroll:SetScrollChild(content)

        local scrollbar = CreateFrame("Slider", nil, box, BackdropTemplateMixin and "BackdropTemplate" or nil)
        scrollbar:SetOrientation("VERTICAL")
        scrollbar:SetWidth(8)
        scrollbar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -7, -8)
        scrollbar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -7, 8)
        if scrollbar.SetBackdrop then
            scrollbar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            scrollbar:SetBackdropColor(0.11, 0.11, 0.11, 0.8)
        end
        scrollbar:SetMinMaxValues(0, 0)
        scrollbar:SetValue(0)
        scrollbar:SetValueStep(22)
        local thumb = scrollbar:CreateTexture(nil, "ARTWORK")
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(0.62, 0.62, 0.62, 0.95)
        thumb:SetSize(8, 28)
        scrollbar:SetThumbTexture(thumb)
        scrollbar:Hide()
        scrollbar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            local low, high = scrollbar:GetMinMaxValues()
            scrollbar:SetValue(math.max(low, math.min(high, scrollbar:GetValue() - delta * 22)))
        end)

        local column = { header = header, box = box, scroll = scroll, content = content, scrollbar = scrollbar, rows = {}, empty = nil, list = list }
        panel[title == "Always junk" and "alwaysList" or "neverList"] = column
        return column
    end

    local alwaysColumn = createListColumn("Always junk", JunkValueDB.alwaysJunk, 0)
    local neverColumn = createListColumn("Never junk", JunkValueDB.neverJunk, columnWidth + 16)

    local function updateColumnScroll(column, contentHeight)
        local viewportHeight = column.scroll:GetHeight()
        local range = math.max(0, contentHeight - viewportHeight)
        column.scrollbar:SetMinMaxValues(0, range)
        column.scrollbar:SetShown(range > 0)
        column.scrollbar:SetValue(math.min(column.scroll:GetVerticalScroll() or 0, range))
        if range == 0 then column.scroll:SetVerticalScroll(0) end
    end

    local function addListEntry(column, itemID, anchor)
        local row = CreateFrame("Frame", nil, column.content)
        row:SetSize(columnWidth - 32, 22)
        if anchor then row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
        else row:SetPoint("TOPLEFT", column.content, "TOPLEFT", 0, 0) end
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        local name, texture = itemNameAndIcon(itemID)
        icon:SetTexture(texture)
        local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        remove:SetSize(56, 18)
        remove:SetPoint("RIGHT", row, "RIGHT", -1, 0)
        remove:SetText("Remove")
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        label:SetPoint("RIGHT", remove, "LEFT", -5, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(name .. " (" .. tostring(itemID) .. ")")
        remove:SetScript("OnClick", function()
            column.list[itemID] = nil
            scanBags()
            listDirty = true
            refreshSettingsPanel()
        end)
        column.rows[#column.rows + 1] = row
        return row
    end

    local listDirty = true
    local function rebuildColumn(column)
        for _, row in ipairs(column.rows) do row:Hide() end
        column.rows = {}
        if column.empty then column.empty:Hide() end
        local ids = {}
        for id, enabled in pairs(column.list) do if enabled then ids[#ids + 1] = tonumber(id) or id end end
        table.sort(ids, function(a, b) return tonumber(a) and tonumber(b) and tonumber(a) < tonumber(b) or tostring(a) < tostring(b) end)
        if #ids == 0 then
            if not column.empty then
                column.empty = column.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                column.empty:SetTextColor(0.62, 0.62, 0.62)
                column.empty:SetText("No items")
            end
            column.empty:ClearAllPoints()
            column.empty:SetPoint("CENTER", column.scroll, "CENTER", 0, 0)
            column.empty:Show()
        else
            local previous
            for _, id in ipairs(ids) do previous = addListEntry(column, id, previous) end
        end
        local contentHeight = math.max(column.scroll:GetHeight(), #ids * 22)
        column.content:SetSize(columnWidth - 32, contentHeight)
        updateColumnScroll(column, contentHeight)
    end

    local tip = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", alwaysColumn.box, "BOTTOMLEFT", 0, -5)
    tip:SetText("Tip: Alt+right-click an item in your bags to toggle it.")
    panel.altTip = tip
    updateAltTip = function()
        local euiLoaded = IsAddOnLoaded and IsAddOnLoaded("EllesmereUIBags")
        local active = euiLoaded and ns.hookStatus.euiButtons > 0 or (not euiLoaded and ns.hookStatus.container == "installed")
        tip:SetShown(not not active)
    end

    local clearButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearButton:SetSize(150, 24)
    clearButton:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -4)
    clearButton:SetText("Clear Lists")
    clearButton:SetScript("OnClick", function(self)
        local now = GetTime()
        if clearPanelConfirmUntil > 0 and now <= clearPanelConfirmUntil then
            wipe(JunkValueDB.alwaysJunk)
            wipe(JunkValueDB.neverJunk)
            clearPanelConfirmUntil = 0
            self:SetText("Clear Lists")
            scanBags()
            listDirty = true
            refreshSettingsPanel()
        else
            clearPanelConfirmUntil = now + 5
            self:SetText("Click again to confirm")
        end
    end)
    clearButton:SetScript("OnUpdate", function(self)
        if clearPanelConfirmUntil > 0 and GetTime() > clearPanelConfirmUntil then
            clearPanelConfirmUntil = 0
            self:SetText("Clear Lists")
        end
    end)

    local function addItem(list)
        local id = ns.ParseItemID(itemInput:GetText())
        if not id then printMessage("Enter an item link or numeric item ID."); return end
        list[id] = true
        scanBags()
        listDirty = true
        refreshSettingsPanel()
        itemInput:SetText("")
    end
    addAlways:SetScript("OnClick", function() addItem(JunkValueDB.alwaysJunk) end)
    addNever:SetScript("OnClick", function() addItem(JunkValueDB.neverJunk) end)
    if type(hooksecurefunc) == "function" and type(HandleModifiedItemClick) == "function" then
        pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
            if IsShiftKeyDown and IsShiftKeyDown() and itemInput:HasFocus() and type(link) == "string" and link:find("item:%d+") then
                itemInput:SetText(link)
                itemInput:SetCursorPosition(0)
            end
        end)
    end

    panel:SetScript("OnShow", function()
        listDirty = true
        if refreshSettingsPanel then refreshSettingsPanel() end
    end)
    refreshSettingsPanel = function(refreshLists)
        if refreshLists then listDirty = true end
        showIcon:SetChecked(not not JunkValueDB.showIcon)
        for _, choice in ipairs({ "white", "pouch", "coin" }) do
            panel["icon_" .. choice]:SetChecked(JunkValueDB.iconChoice == choice)
        end
        panel.merchantSummaryCheck:SetChecked(not not JunkValueDB.merchantSummary)
        panel.goldOnlyOverOneGoldCheck:SetChecked(not not JunkValueDB.goldOnlyOverOneGold)
        panel.countEUIJunkCheck:SetChecked(not not JunkValueDB.countEUIJunk)
        if listDirty then
            rebuildColumn(alwaysColumn)
            rebuildColumn(neverColumn)
            listDirty = false
        end
        updateAltTip()
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
        if refreshSettingsPanel then refreshSettingsPanel(true) end
    elseif cmd == "list" then listEntries()
    elseif cmd == "clear" and not arg then
        requestClearConfirmation()
    elseif cmd == "clear" and arg and arg:lower() == "confirm" then
        confirmClear()
    elseif cmd == "icon" then
        toggleOption("showIcon", "Icon")
    elseif cmd == "debug" then
        printMessage("Blizzard bag hook: " .. tostring(ns.hookStatus.container) .. "; EUI bag hook: " .. tostring(ns.hookStatus.eui) .. " (" .. tostring(ns.hookStatus.euiButtons) .. " buttons); item tooltip hook: " .. tostring(ns.hookStatus.tooltip) .. ".")
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
    if InCombatLockdown and InCombatLockdown() then return end
    local list = quality == 0 and JunkValueDB.neverJunk or JunkValueDB.alwaysJunk
    if list[itemID] then list[itemID] = nil; printMessage("Removed " .. itemID .. " from custom list.")
    else list[itemID] = true; printMessage((quality == 0 and "Kept " or "Always junk ") .. itemID .. ".") end
    scanBags()
    if refreshSettingsPanel then refreshSettingsPanel(true) end
end
local function processBagModifiedClick(button, mouseButton, isEUIButton)
    if not databaseLoaded or (InCombatLockdown and InCombatLockdown()) then return end
    if not button or (hookedEUIButtons[button] and not isEUIButton) then return end
    if mouseButton ~= "RightButton" or not IsAltKeyDown or not IsAltKeyDown() then return end
    local bag, slot = button:GetParent() and button:GetParent():GetID(), button:GetID()
    if not bag or not slot then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return end
    local _, _, quality = C_Item.GetItemInfo(info.itemID)
    if quality ~= nil then toggleCustomItem(info.itemID, quality) end
end
local function handleBagModifiedClick(button, mouseButton)
    processBagModifiedClick(button, mouseButton, false)
end
local function handleEUIBagButtonClick(button, mouseButton)
    processBagModifiedClick(button, mouseButton, true)
end
ns.hookStatus = { container = "not installed", tooltip = "not installed", eui = "not available", euiButtons = 0 }
if type(hooksecurefunc) == "function" and type(ContainerFrameItemButton_OnModifiedClick) == "function" and type(handleBagModifiedClick) == "function" then
    local ok = pcall(hooksecurefunc, "ContainerFrameItemButton_OnModifiedClick", handleBagModifiedClick)
    ns.hookStatus.container = ok and "installed" or "installation failed"
else
    ns.hookStatus.container = "handler unavailable"
end

local function hookEUIItemButton(button)
    if not button or hookedEUIButtons[button] then return end
    local hookable, reason = ns.CanHookScript(button, "OnClick", handleEUIBagButtonClick)
    if not hookable or type(button.HookScript) ~= "function" then return false, reason or "hookscript_unavailable" end
    local ok = pcall(function() button:HookScript("OnClick", handleEUIBagButtonClick) end)
    if not ok then return false, "hook_failed" end
    hookedEUIButtons[button] = true
    ns.hookStatus.euiButtons = ns.hookStatus.euiButtons + 1
    if updateAltTip then updateAltTip() end
    return true
end

local function hookEUIBagButtons()
    if InCombatLockdown and InCombatLockdown() then
        euiRescanPending = true
        infoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    euiRescanPending = false
    local eui = EllesmereUI
    local moduleNS = eui and eui._ModuleNS and eui._ModuleNS["EllesmereUIBags"]
    local internals = moduleNS and moduleNS._bagsInternals
    local pools = {}
    if internals and type(internals.itemSlots) == "table" then pools[#pools + 1] = internals.itemSlots end
    if internals and type(internals.reagentSlots) == "table" then pools[#pools + 1] = internals.reagentSlots end
    local foundPool = false
    if pools then
        for _, pool in ipairs(pools) do
            if type(pool) == "table" then
                foundPool = true
                for _, button in pairs(pool) do hookEUIItemButton(button) end
            end
        end
    end
    ns.hookStatus.eui = foundPool and (ns.hookStatus.euiButtons > 0 and "active" or "waiting for item buttons") or "EUI pools unavailable"
    if updateAltTip then updateAltTip() end
end

local function installEUIRefreshHook(frame)
    if not frame or type(frame.RefreshInventory) ~= "function" then return false end
    if euiRefreshHooks[frame] then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, frame, "RefreshInventory", function()
        if InCombatLockdown and InCombatLockdown() then
            euiRescanPending = true
            infoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            hookEUIBagButtons()
        end
    end)
    if ok then euiRefreshHooks[frame] = true end
    return ok
end

local function installEUIBagHooks()
    local hooked = installEUIRefreshHook(_G.EUI_Bags)
    hooked = installEUIRefreshHook(_G.EUI_BagsReagent) or hooked
    if hooked then hookEUIBagButtons() end
    ns.hookStatus.eui = hooked and (ns.hookStatus.euiButtons > 0 and "active" or "refresh hooks active") or "EUI refresh unavailable"
    if updateAltTip then updateAltTip() end
end

function dataObject:OnClick(button)
    if button == "LeftButton" then
        if ToggleAllBags then ToggleAllBags() end
    elseif button == "RightButton" then
        openOptionsPanel()
    end
end

local function appendItemListTooltip(tooltip)
    if not databaseLoaded then return end
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
        if loadedName == "EllesmereUIBags" then installEUIBagHooks() end
        if loadedName == addonName and not databaseLoaded then
            JunkValueDB = ns.MergeDefaults(JunkValueDB, defaultSettings)
            databaseLoaded = true
            updateIcon()
            scanBags()
            installEUIBagHooks()
            if not InCombatLockdown or not InCombatLockdown() then
                createSettingsPanel()
            else
                infoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and databaseLoaded and not settingsPanel then
        createSettingsPanel()
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if euiRescanPending then hookEUIBagButtons() end
        if not euiRescanPending then infoFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if not databaseLoaded then return end
    if event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        scanBags()
        if event == "GET_ITEM_INFO_RECEIVED" and refreshSettingsPanel then refreshSettingsPanel(true) end
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
