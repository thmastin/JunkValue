local ns = {}
assert(loadfile("JunkValueCore.lua"))("JunkValue", ns)
local sumSellableSlots = ns.SumSellableSlots

local cases = {
    { "gray with price", {{ occupied=true, quality=0, sellPrice=7, stackCount=1 }}, 7, 1, false },
    { "hasNoValue", {{ occupied=true, quality=0, sellPrice=7, hasNoValue=true }}, 0, 0, false },
    { "price zero", {{ occupied=true, quality=0, sellPrice=0 }}, 0, 0, false },
    { "non-gray", {{ occupied=true, quality=1, sellPrice=7 }}, 0, 0, false },
    { "stack multiplier", {{ occupied=true, quality=0, sellPrice=7, stackCount=4 }}, 28, 1, false },
    { "pending/nil info", {{ occupied=true, quality=nil, sellPrice=nil }}, 0, 0, true },
}

for _, case in ipairs(cases) do
    local total, stacks, pending = sumSellableSlots(case[2])
    assert(total == case[3] and stacks == case[4] and pending == case[5], case[1] .. " failed")
    print("PASS " .. case[1])
end
print(("%d tests passed"):format(#cases))
