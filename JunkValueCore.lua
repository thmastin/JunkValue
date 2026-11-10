local addonName, ns = ...

function ns.SumSellableSlots(slots)
    local total, stacks, pending = 0, 0, false
    for _, slot in ipairs(slots) do
        if slot.occupied then
            if slot.quality == nil or slot.sellPrice == nil then
                pending = true
            elseif (slot.quality == 0 or slot.markedJunk) and not slot.hasNoValue and slot.sellPrice > 0 then
                local count = slot.stackCount or 1
                total = total + slot.sellPrice * count
                stacks = stacks + 1
            end
        end
    end
    return total, stacks, pending
end
