-- Run from the repository root with Lua 5.1.
local addon = "MerchantsFavourOptimiser/"
dofile(addon .. "WritData.lua")
dofile(addon .. "WritCalculations.lua")
dofile(addon .. "InventoryProvider.lua")

local Writ = MFO_WritCalculations
local function constant() return 100 end
local function contains(rows, id)
  local count = 0
  for _, row in ipairs(rows) do
    if row.id == id then count = count + 1 end
  end
  return count
end

local results = Writ.available("Alliance")
assert(#results == 130)
for _, row in ipairs(results) do
  local result = assert(Writ.calculateSelection({row.id}, "Horde", constant))
  local quantity = 0
  for _, item in ipairs(row.items) do quantity = quantity + item.qty end
  assert(result.reputation == row.reputation and result.writCost == 100)
  assert(result.itemCost == 100 * quantity and result.total == 100 * (quantity + 1))
  assert(result.costPerRep == result.total / row.reputation and result.ownedSavings == 0)
end

local both = Writ.available("Horde", {Leatherworking = true, Tailoring = true})
assert(contains(both, 264144) == 1)
assert(contains(Writ.available("Horde", {Tailoring = true}), 264144) == 1)
assert(contains(Writ.available("Horde", {Engineering = true}), 264065) == 1)
assert(contains(Writ.available("Horde", {Alchemy = true}), 264144) == 0)
assert(#Writ.available("Horde", {}) == 0)
local function rejected(ids, faction, reason, expectedID)
  local result, errorMessage, id = Writ.calculateSelection(ids, faction, function()
    error("Invalid selection reached the price callback")
  end)
  assert(result == nil and errorMessage == reason and id == expectedID)
end
rejected({264011}, "Alliance", "Unknown Writ", 264011)
rejected({264065, 264065}, "Horde", "Duplicate Writ", 264065)

local bags, bank = {[264037] = 1, [8069] = 120}, {[8069] = 30}
local function stock(id)
  return MFO_InventoryProvider.TotalCount(id, bags, bank, "native")
end
local mixed = assert(Writ.calculateSelection({264037, 264065}, "Alliance", constant, stock))
assert(mixed.writCost == 100 and mixed.itemCost == 5100 and mixed.total == 5200)
assert(mixed.reputation == 200 and mixed.costPerRep == 26 and mixed.ownedSavings == 15100)
assert(mixed.shopping[8069] == 50 and mixed.owned[8069] == 150)
assert(not mixed.shopping[264037] and bags[8069] == 120 and bank[8069] == 30)

local prototype = {id = 10, reputation = 40, items = {{id = 20, qty = 2}, {id = 20, qty = 3}}}
local single = assert(Writ.calculate(prototype, constant, function() return 2 end))
assert(single.shopping[20] == 3 and single.owned[20] == 2)
assert(single.writCost == 0 and single.itemCost == 300 and single.ownedSavings == 300)
assert(single.costPerRep == 7.5)

local function uncertain(id)
  if id == 20 then return 5, true end
end
local unavailable, reason = Writ.calculate(prototype, uncertain)
assert(reason == "Missing prices")
assert(unavailable.missingPrices[1] == 10 and unavailable.stalePrices[1] == 20)
assert(unavailable.total == nil and unavailable.costPerRep == nil)
unavailable, reason = Writ.calculate(prototype, uncertain, function() return 5 end)
assert(reason == nil and unavailable.total == 0 and unavailable.costPerRep == 0)
assert(unavailable.ownedSavings == nil and table.concat(unavailable.unpricedSavings, ",") == "10,20")
assert(#unavailable.stalePrices == 0 and #unavailable.missingPrices == 0)
unavailable, reason = Writ.calculate(prototype, function() return 10, true end)
assert(reason == "Stale prices" and table.concat(unavailable.stalePrices, ",") == "10,20")

for _, invalid in ipairs({false, "5", 0, -1, 2.5, math.huge, 0/0}) do
  local result = Writ.calculate(prototype, function() return invalid end, function() return -2 end)
  assert(#result.missingPrices == 2 and result.shopping[20] == 5 and result.ownedSavings == 0)
end
assert(Writ.calculate(nil, constant) == nil)
assert(Writ.calculate({id = 10, reputation = 1, items = {{id = 10, qty = 1}}}, constant) == nil)
local empty = assert(Writ.calculateSelection({}, "Alliance", constant))
assert(empty.total == 0 and empty.reputation == 0 and empty.costPerRep == nil)

-- Fixture models a future faction-restricted record with a shared objective.
local last = #MFO_WritData + 1
MFO_WritData[last] = {
  id = 999, reputation = 75, faction = "Alliance", professions = {"Alchemy", "Engineering"},
  items = {{id = 9061, qty = 2}},
}
assert(contains(Writ.available("Alliance"), 999) == 1)
assert(contains(Writ.available("Horde"), 999) == 0)
assert(contains(Writ.available(nil), 999) == 0)
rejected({999}, "Horde", "Faction restricted", 999)
rejected({999}, nil, "Faction restricted", 999)
local function aggregate(ids)
  local reads, quotes = {}, {}
  local result = assert(Writ.calculateSelection(ids, "Alliance", function(id)
    assert(not quotes[id])
    quotes[id] = true
    return 10
  end, function(id)
    assert(not reads[id])
    reads[id] = true
    if id == 9061 then return 2 end
  end))
  assert(result.owned[9061] == 2 and result.shopping[9061] == 1)
  assert(result.writCost == 20 and result.itemCost == 10 and result.ownedSavings == 20)
  assert(result.total == 30 and result.costPerRep == 30 / 200)
end
aggregate({264065, 999})
aggregate({999, 264065})
MFO_WritData[last] = nil

-- Price freshness uses the item timestamp and preserves the legacy price reader.
GetRealmName = function() return "Test" end
UnitFactionGroup = function() return "Alliance" end
CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end
MFO_DB = {prices = {[264065] = {price = 100, updated = 60}, [9061] = {price = 25}}, lastAHScan = 100}
dofile(addon .. "StandaloneAH.lua")
local function quote(id) return MFO_AH.PriceQuote(id, 40, 100) end
local price, stale = quote(264065)
assert(price == 100 and stale == false)
assert(select(2, MFO_AH.PriceQuote(264065, 39, 100)) == true)
assert(select(2, MFO_AH.PriceQuote(264065, 40, 59)) == true)
assert(MFO_AH.Price(9061) == 25 and quote(999) == nil)
local legacy, legacyReason = Writ.calculateSelection({264065}, "Alliance", quote)
assert(legacyReason == "Stale prices" and legacy.stalePrices[1] == 9061)
assert(MFO_DB.legacyAHData.prices[9061].updated == nil)
print("PASS: Writ costs, freshness, eligibility and shared inventory")
