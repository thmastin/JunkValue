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
    { "marked junk", {{ occupied=true, quality=2, markedJunk=true, sellPrice=9 }}, 9, 1, false },
}

for _, case in ipairs(cases) do
    local total, stacks, pending = sumSellableSlots(case[2])
    assert(total == case[3] and stacks == case[4] and pending == case[5], case[1] .. " failed")
    print("PASS " .. case[1])
end

local customCases = {
    { "always junk white", {{occupied=true,itemID=101,quality=1,sellPrice=25}}, {[101]=true}, {}, 25, 1 },
    { "never excludes gray", {{occupied=true,itemID=102,quality=0,sellPrice=25}}, {}, {[102]=true}, 0, 0 },
    { "never wins both", {{occupied=true,itemID=103,quality=0,sellPrice=25}}, {[103]=true}, {[103]=true}, 0, 0 },
    { "always no sell price", {{occupied=true,itemID=104,quality=1,sellPrice=0}}, {[104]=true}, {}, 0, 0 },
}
for _, c in ipairs(customCases) do
    local t, n, _, _, noPrice = ns.SumSellableSlots(c[2], c[3], c[4])
    assert(t == c[5] and n == c[6], c[1] .. " failed")
    if c[1] == "always no sell price" then assert(noPrice, "missing no-price tooltip marker") end
    print("PASS " .. c[1])
end
local iconMap = {white="white-path", pouch="pouch-path", coin="coin-path"}
assert(ns.ResolveIcon(true, "white", iconMap) == "white-path", "default icon setting failed")
assert(ns.ResolveIcon(true, "coin", iconMap) == "coin-path", "selected icon setting failed")
assert(ns.ResolveIcon(false, "coin", iconMap) == nil, "hidden icon setting failed")
print("PASS icon settings")
local v111DB = { countEUIJunk = false, merchantSummary = true, goldOnlyOverOneGold = false }
local migratedDB = ns.MergeDefaults(v111DB, {
    countEUIJunk = false, merchantSummary = false, goldOnlyOverOneGold = false,
    alwaysJunk = {}, neverJunk = {}, showIcon = true, iconChoice = "white",
})
assert(migratedDB == v111DB, "migration should preserve the existing database table")
assert(migratedDB.merchantSummary == true and migratedDB.countEUIJunk == false, "migration overwrote existing v1.1.1 values")
assert(type(migratedDB.alwaysJunk) == "table" and type(migratedDB.neverJunk) == "table", "migration did not create custom lists")
assert(migratedDB.showIcon == true and migratedDB.iconChoice == "white", "migration did not add icon defaults")
print("PASS v1.1.1 database defaults migration")
local command, argument = ns.ParseSlashCommand("  ADD |Hitem:12345:AbC|h[Mixed Case Item]|h  ")
assert(command == "add" and argument == "|Hitem:12345:AbC|h[Mixed Case Item]|h", "slash parser changed argument case")
assert(ns.ParseItemID(argument) == 12345, "item link ID parsing failed")
assert(ns.ParseItemID(" 67890 ") == 67890, "bare item ID parsing failed")
print("PASS case-preserving slash parsing")
local supportedFrame = { HasScript = function(_, script) return script == "OnTooltipSetItem" end }
assert(ns.CanHookScript(nil, "OnTooltipSetItem", function() end) == false, "missing frame should not hook")
assert(ns.CanHookScript(supportedFrame, "OnTooltipSetItem", nil) == false, "missing handler should not hook")
assert(ns.CanHookScript(supportedFrame, "OnClick", function() end) == false, "unsupported frame script should not hook")
assert(ns.CanHookScript(supportedFrame, "OnTooltipSetItem", function() end) == true, "supported frame script should hook")
print("PASS guarded hook checks")
assert(ns.IsClearConfirmed(105, 110), "clear confirmation should work before its deadline")
assert(not ns.IsClearConfirmed(111, 110), "clear confirmation should expire")
assert(not ns.IsClearConfirmed(105, 0), "clear confirmation should require a pending request")
print("PASS clear confirmation timeout")

-- Regression: the tooltip host passes its own frame/tooltip, which does not
-- carry the broker object's value fields. Both views must use the same scan.
local manySlots = {}
for i = 1, 7 do
    manySlots[i] = {
        occupied = true,
        itemID = i,
        itemLink = "[Item " .. i .. "]",
        quality = 0,
        sellPrice = i * 10,
        stackCount = 1,
    }
end
local total, stackCount, pending, stacks = sumSellableSlots(manySlots)
local snapshot = { total = total, stackCount = stackCount, pending = pending, stacks = stacks }
local function fakeMoney(copper) return tostring(copper) .. "c" end
local barText = fakeMoney(snapshot.total)
local tooltip = { value = 0, stacks = 0, rows = {} }
function tooltip:AddLine(text) self.rows[#self.rows + 1] = { text = text } end
function tooltip:AddDoubleLine(left, right) self.rows[#self.rows + 1] = { left = left, right = right } end
ns.WriteTooltip(tooltip, snapshot, 123, fakeMoney)
assert(barText == "280c", "broker text did not use the expected scan total")
assert(tooltip.rows[2].left == "Total" and tooltip.rows[2].right == barText, "tooltip total diverged from broker text")
assert(tooltip.rows[3].left == "Stacks" and tooltip.rows[3].right == "7", "tooltip stack count diverged from scan")
assert(tooltip.rows[4].left == "[Item 7]" and tooltip.rows[4].right == "70c", "single stack row should omit x1 and show value on the right")
assert(not tooltip.rows[4].left:find("=", 1, true), "stack row should not contain an equals separator")
assert(tooltip.rows[9].text == "+2 more", "tooltip omitted the additional stack count")
assert(tooltip.rows[10].left == "Gold earned this session" and tooltip.rows[10].right == "123c", "session earnings row missing")
assert(tooltip.rows[12].text == "Left-click: open bags", "left-click hint missing")
assert(tooltip.rows[13].text == "Right-click: options", "right-click hint missing")
print("PASS shared scan tooltip regression and stack details")
local multiRows = ns.BuildTooltipRows({
    total = 300,
    stackCount = 1,
    stacks = {{ itemLink = "[Stack]", stackCount = 3, value = 300 }},
}, 0, fakeMoney)
assert(multiRows[3].left == "[Stack] x3" and multiRows[3].right == "300c", "multi-item stack row format incorrect")
print("PASS tooltip stack labels")
assert(ns.CalculateMerchantEarnings(80, 100, 20) == 80, "merchant sale earnings were not correlated with junk value decrease")
assert(ns.CalculateMerchantEarnings(80, 100, 100) == 0, "non-junk sale was incorrectly attributed to junk")
assert(ns.CalculateMerchantEarnings(0, 100, 20) == 0, "merchant spending was counted as earnings")
print("PASS merchant earnings correlation")
print(("%d tests passed"):format(#cases + #customCases + 8))
