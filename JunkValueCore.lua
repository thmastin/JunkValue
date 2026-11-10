local addonName, ns = ...

function ns.SumSellableSlots(slots)
    local total, stackCount, pending, sellableStacks = 0, 0, false, {}
    for _, slot in ipairs(slots) do
        if slot.occupied then
            if slot.quality == nil or slot.sellPrice == nil then
                pending = true
            elseif (slot.quality == 0 or slot.markedJunk) and not slot.hasNoValue and slot.sellPrice > 0 then
                local count = slot.stackCount or 1
                local stackValue = slot.sellPrice * count
                total = total + stackValue
                stackCount = stackCount + 1
                sellableStacks[#sellableStacks + 1] = {
                    itemID = slot.itemID,
                    itemLink = slot.itemLink,
                    stackCount = count,
                    unitPrice = slot.sellPrice,
                    value = stackValue,
                }
            end
        end
    end

    table.sort(sellableStacks, function(a, b)
        if a.value == b.value then
            return (a.itemLink or tostring(a.itemID or "")) < (b.itemLink or tostring(b.itemID or ""))
        end
        return a.value > b.value
    end)

    return total, stackCount, pending, sellableStacks
end

function ns.BuildTooltipRows(scanResult, sessionEarned, formatMoney, limit)
    local rows = {
        { kind = "double", left = "Total", right = formatMoney(scanResult.total) },
        { kind = "double", left = "Stacks", right = tostring(scanResult.stackCount) },
    }

    local topCount = math.min(limit or 5, #scanResult.stacks)
    for i = 1, topCount do
        local stack = scanResult.stacks[i]
        local link = stack.itemLink or ("[Item " .. tostring(stack.itemID or "?") .. "]")
        local label = link
        if stack.stackCount > 1 then label = link .. " x" .. tostring(stack.stackCount) end
        rows[#rows + 1] = {
            kind = "double",
            left = label,
            right = formatMoney(stack.value),
        }
    end
    if #scanResult.stacks > topCount then
        rows[#rows + 1] = { kind = "line", text = "+" .. tostring(#scanResult.stacks - topCount) .. " more" }
    end

    rows[#rows + 1] = { kind = "double", left = "Gold earned this session", right = formatMoney(sessionEarned or 0) }
    rows[#rows + 1] = { kind = "line", text = " " }
    rows[#rows + 1] = { kind = "line", text = "Left-click: open bags" }
    rows[#rows + 1] = { kind = "line", text = "Right-click: options" }
    return rows
end

function ns.WriteTooltip(tooltip, scanResult, sessionEarned, formatMoney)
    tooltip:AddLine("Junk Value")
    local rows = ns.BuildTooltipRows(scanResult, sessionEarned, formatMoney, 5)
    for _, row in ipairs(rows) do
        if row.kind == "double" then
            tooltip:AddDoubleLine(row.left, row.right, 1, 1, 1, 1, 1, 1)
        else
            tooltip:AddLine(row.text)
        end
    end
end

function ns.CalculateMerchantEarnings(moneyEarned, junkBefore, junkAfter)
    local junkValueDecrease = (junkBefore or 0) - (junkAfter or 0)
    if (moneyEarned or 0) <= 0 or junkValueDecrease <= 0 then return 0 end
    return math.min(moneyEarned, junkValueDecrease)
end
