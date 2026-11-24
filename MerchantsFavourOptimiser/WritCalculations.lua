-- Pure Lua 5.1 calculations. Prices are copper per unit.
MFO_WritCalculations = {}
local function integer(n, minimum)
  return type(n) == "number" and n >= minimum and n < math.huge and n == math.floor(n)
end

-- Requirements are item IDs and quantities, including the Writ itself.
-- Unknown prices are never treated as free. Owned stock is optional.
function MFO_WritCalculations.calculate(writ, getPrice, getOwned)
  if type(writ) ~= "table" or not integer(writ.id, 1)
    or not integer(writ.reputation, 1) or type(writ.items) ~= "table"
    or #writ.items == 0 then return nil, "Invalid Writ" end
  local quantities = {[writ.id] = 1}
  for _, item in ipairs(writ.items) do
    if type(item) ~= "table" or not integer(item.id, 1)
      or not integer(item.qty, 1) or item.id == writ.id then
      return nil, "Invalid requirement"
    end
    quantities[item.id] = (quantities[item.id] or 0) + item.qty
  end
  local result = {writCost = 0, itemCost = 0, shopping = {}, missingPrices = {}}
  for id, qty in pairs(quantities) do
    local owned = getOwned and getOwned(id) or 0
    if not integer(owned, 0) then owned = 0 end
    local missing = math.max(0, qty - owned)
    if missing > 0 then
      result.shopping[id] = missing
      local price = getPrice(id)
      if not integer(price, 1) then
        result.missingPrices[#result.missingPrices + 1] = id
      elseif id == writ.id then
        result.writCost = price * missing
      else
        result.itemCost = result.itemCost + price * missing
      end
    end
  end
  table.sort(result.missingPrices)
  if #result.missingPrices > 0 then
    result.writCost = nil
    result.itemCost = nil
    return result, "Missing prices"
  end
  result.total = result.writCost + result.itemCost
  result.costPerRep = result.total / writ.reputation
  return result
end
