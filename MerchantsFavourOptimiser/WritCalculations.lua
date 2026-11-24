-- Pure Lua 5.1 calculations. Prices are copper per unit.
MFO_WritCalculations = {}
local Writ = MFO_WritCalculations

local function integer(n, minimum)
  return type(n) == "number" and n >= minimum and n < math.huge and n == math.floor(n)
end

local function addRequirements(writ, requirements)
  if type(writ) ~= "table" or not integer(writ.id, 1)
    or not integer(writ.reputation, 1) or type(writ.items) ~= "table"
    or #writ.items == 0 then return nil, "Invalid Writ" end

  requirements[writ.id] = (requirements[writ.id] or 0) + 1
  for _, item in ipairs(writ.items) do
    if type(item) ~= "table" or not integer(item.id, 1)
      or not integer(item.qty, 1) or item.id == writ.id then
      return nil, "Invalid requirement"
    end
    requirements[item.id] = (requirements[item.id] or 0) + item.qty
  end
  return true
end

-- getPrice returns a unit price and optionally a true stale flag.
-- Unpriced owned stock still reduces the shopping quantity.
local function cost(requirements, acquisitions, reputation, getPrice, getOwned)
  local result = {
    writCost = 0, itemCost = 0, ownedSavings = 0, reputation = reputation,
    shopping = {}, owned = {}, missingPrices = {}, stalePrices = {},
    unpricedSavings = {},
  }
  for id, qty in pairs(requirements) do
    local stock = getOwned and getOwned(id) or 0
    local owned = integer(stock, 0) and math.min(stock, qty) or 0
    local buy = qty - owned
    local buyWrit = math.max(0, (acquisitions[id] or 0) - owned)
    local buyItem = buy - buyWrit
    local price, stale = getPrice(id)
    local priced = integer(price, 1) and not stale

    if owned > 0 then
      result.owned[id] = owned
      if priced then
        result.ownedSavings = result.ownedSavings + owned * price
      else
        result.unpricedSavings[#result.unpricedSavings + 1] = id
      end
    end
    if buy > 0 then
      result.shopping[id] = buy
      if priced then
        result.writCost = result.writCost + buyWrit * price
        result.itemCost = result.itemCost + buyItem * price
      else
        local unavailable = integer(price, 1) and result.stalePrices or result.missingPrices
        unavailable[#unavailable + 1] = id
      end
    end
  end

  table.sort(result.missingPrices)
  table.sort(result.stalePrices)
  table.sort(result.unpricedSavings)
  if #result.unpricedSavings > 0 then result.ownedSavings = nil end
  if #result.missingPrices > 0 or #result.stalePrices > 0 then
    result.writCost, result.itemCost = nil, nil
    return result, #result.missingPrices > 0 and "Missing prices" or "Stale prices"
  end
  result.total = result.writCost + result.itemCost
  if reputation > 0 then result.costPerRep = result.total / reputation end
  return result
end

function Writ.calculate(writ, getPrice, getOwned)
  local requirements = {}
  local valid, reason = addRequirements(writ, requirements)
  if not valid then return nil, reason end
  return cost(requirements, {[writ.id] = 1}, writ.reputation, getPrice, getOwned)
end

local function eligible(writ, faction)
  return writ.faction == "Both" or
    ((faction == "Alliance" or faction == "Horde") and writ.faction == faction)
end

-- Profession tags filter crafting and recipe supply. They are not turn-in requirements.
-- professions is an optional set keyed by profession name.
function Writ.available(faction, professions)
  local available = {}
  for _, writ in ipairs(MFO_WritData) do
    if eligible(writ, faction) then
      if not professions then
        available[#available + 1] = writ
      else
        for _, profession in ipairs(writ.professions) do
          if professions[profession] then
            available[#available + 1] = writ
            break
          end
        end
      end
    end
  end
  return available
end

-- Price a selection of distinct verified Writ IDs against one stock snapshot.
function Writ.calculateSelection(writIDs, faction, getPrice, getOwned)
  local byID, requirements, acquisitions = {}, {}, {}
  local reputation = 0
  for _, writ in ipairs(MFO_WritData) do byID[writ.id] = writ end
  for _, id in ipairs(writIDs) do
    local writ = byID[id]
    if not writ then return nil, "Unknown Writ", id end
    if not eligible(writ, faction) then return nil, "Faction restricted", id end
    if acquisitions[id] then return nil, "Duplicate Writ", id end
    local valid, reason = addRequirements(writ, requirements)
    if not valid then return nil, reason, id end
    acquisitions[id] = 1
    reputation = reputation + writ.reputation
  end
  return cost(requirements, acquisitions, reputation, getPrice, getOwned)
end
