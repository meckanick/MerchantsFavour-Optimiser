-- Run from repository root with Lua 5.1:
-- lua5.1 tests/mfo-regression.lua
dofile("MerchantsFavourOptimiser/Data.lua")
dofile("MerchantsFavourOptimiser/Calculations.lua")

local function check(condition, message)
  if not condition then error("FAIL: " .. message, 2) end
end
local function equal(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected) ..
    ", got " .. tostring(actual) .. ")")
end

equal(#MFO_DATA, 30, "there must be exactly 30 crate definitions")
-- Artisan definitions are retained for future verification but hidden in the UI.
local visibleCount, artisanCount = 0, 0
for _, crate in ipairs(MFO_DATA) do
  if crate.name:find("Artisan", 1, true) then
    artisanCount = artisanCount + 1
    check(crate.favour == nil, crate.name .. " must not invent an Artisan reward")
  else
    visibleCount = visibleCount + 1
  end
end
equal(artisanCount, 8, "eight unconfirmed Artisan definitions must be retained")
equal(visibleCount, 22, "exactly 22 confirmed-tier crates should remain visible")
local ids, names = {}, {}
for _, crate in ipairs(MFO_DATA) do
  check(type(crate.name) == "string" and crate.name ~= "", "crate name must exist")
  check(type(crate.id) == "number" and crate.id > 0, crate.name .. " must have a valid item ID")
  check(not ids[crate.id], "duplicate crate item ID " .. tostring(crate.id))
  check(not names[crate.name], "duplicate crate name " .. crate.name)
  ids[crate.id], names[crate.name] = true, true
  check(crate.favour == nil or (type(crate.favour) == "number" and crate.favour > 0), crate.name .. " must have positive or unverified favour")
  check(type(crate.bundles) == "table" and #crate.bundles > 0, crate.name .. " must have bundles")
  for _, bundle in ipairs(crate.bundles) do
    check(type(bundle.name) == "string" and bundle.name ~= "", crate.name .. " has unnamed material")
    check(type(bundle.qty) == "number" and bundle.qty > 0 and bundle.qty == math.floor(bundle.qty),
      crate.name .. " has invalid quantity for " .. tostring(bundle.name))
  end
end

local textile, unverified
for _, c in ipairs(MFO_DATA) do
  if c.id == 248688 then textile = c end
  if c.id == 248705 then unverified = c end
end
check(textile ~= nil and textile.bundles[1].qty == 20, "Journeyman Textiles must require 20 Wool Cloth")
check(unverified ~= nil and unverified.favour == nil, "Unverified reward must not be invented")

local crate = {
  name = "Test Crate", id = 9001, favour = 10,
  bundles = {
    {name = "Material A", qty = 20},
    {name = "Material B", qty = 2},
  },
}
local prices = {[9001] = 1000, [101] = 100, [102] = 500}
local owned = {}
local idsByName = {["Material A"] = 101, ["Material B"] = 102}
local function getPrice(id) return prices[id] end
local function getOwned(id) return owned[id] or 0 end
local function resolve(name) return idsByName[name] end

local rate, crateCost, bundle, bundleCost, missing, have, crateOwned =
  MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(crateCost, 1000, "crate cost should use the market price")
equal(bundle.name, "Material B", "cheapest complete bundle should be selected")
equal(bundleCost, 1000, "bundle cost should include required quantities")
equal(missing, 2, "missing quantity should be returned")
equal(have, 0, "owned quantity should start at zero")
equal(crateOwned, false, "crate should not be marked owned")
equal(rate, 200, "gold per favour should be total cost divided by favour")

owned[101], owned[102], owned[9001] = 5, 1, 1
rate, crateCost, bundle, bundleCost, missing, have, crateOwned =
  MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(crateCost, 0, "owned crate should have zero purchase cost")
equal(bundle.name, "Material B", "owned quantities should be accounted for")
equal(bundleCost, 500, "only missing material quantity should be costed")
equal(missing, 1, "missing material quantity should reflect owned items")
equal(have, 1, "owned material quantity should be reported")
equal(crateOwned, true, "owned crate should be marked owned")
equal(rate, 50, "owned crate and remaining materials should affect rate")

prices[101], prices[102] = nil, nil
owned[101], owned[102], owned[9001] = 0, 0, 0
rate = MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(rate, nil, "unknown required prices must not be treated as zero")

-- If all required materials are owned, material cost is known to be zero
-- even if their current Auctionator prices are unavailable.
prices[101] = 100
owned[101], owned[102] = 20, 2
rate, crateCost, bundle, bundleCost = MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(bundleCost, 0, "fully owned bundle should cost zero")
equal(rate, 100, "fully owned materials should leave only crate cost")

-- Unknown item IDs must not cause a nil table-index error or invent a price.
local unknownCrate = {name = "Unknown", id = 9002, favour = 5,
  bundles = {{name = "Unresolved Material", qty = 3}}}
local unknownRate = MFO_Calculations.calculate(
  unknownCrate,
  function(id) return prices[id] end,
  function(id) return owned[id] or 0 end,
  function(name) return nil end)
equal(unknownRate, nil, "unresolved material IDs should remain unranked safely")

local noFavourRate, _, noFavourBundle = MFO_Calculations.calculate(
  unverified, function() return 100 end, function() return 0 end,
  function() return 100 end)
equal(noFavourRate, nil, "unverified favour cannot generate gold-per-favour rank")
check(noFavourBundle ~= nil, "unverified favour still allows cheapest bundle selection")

print("PASS: 30 crate definitions and calculation regression scenarios")
