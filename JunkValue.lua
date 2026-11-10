local addonName, ns = ...

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
JunkValueDB = JunkValueDB or { countEUIJunk = false }
local dataObject = LDB:NewDataObject("JunkValue", {
    type = "data source",
    label = "Junk",
    text = "0c",
})
ns.dataObject = dataObject

local pendingInfo = false
local infoFrame = CreateFrame("Frame")

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

local function isEUIJunk(itemID)
    if not JunkValueDB.countEUIJunk then return false end
    local manager = _G.EUI_CategoryManager
    if not manager or type(manager.IsJunk) ~= "function" then return false end
    local ok, result = pcall(manager.IsJunk, manager, itemID)
    return ok and not not result
end

local function scanBags()
    local slots = {}
    for bag = 0, 4 do
        local slotCount = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slotCount do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID then
                local name, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(item.itemID)
                if not name then
                    slots[#slots + 1] = { occupied = true, quality = nil, sellPrice = nil }
                else
                    slots[#slots + 1] = {
                        occupied = true,
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
    local total, stackCount, pending = ns.SumSellableSlots(slots)
    pendingInfo = pending
    if pending then
        infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        infoFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    dataObject.text = formatMoney(total)
    dataObject.value = total
    dataObject.stacks = stackCount
    dataObject.pending = pending
end

infoFrame:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" and pendingInfo then
        scanBags()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" or event == "MERCHANT_CLOSED" then
        scanBags()
    end
end)
infoFrame:RegisterEvent("BAG_UPDATE_DELAYED")
infoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
infoFrame:RegisterEvent("MERCHANT_CLOSED")

function dataObject:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Junk Value")
    GameTooltip:AddDoubleLine("Total", formatMoney(self.value or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Stacks", tostring(self.stacks or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
end

function dataObject:OnLeave()
    GameTooltip:Hide()
end

function dataObject:OnClick(button)
    if button == "LeftButton" and ToggleAllBags then ToggleAllBags() end
end

scanBags()
