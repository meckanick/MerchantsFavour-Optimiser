-- Pure calculation logic kept separate from WoW UI/API calls so CI can test it.
MFO_Calculations = {}

function MFO_Calculations.calculate(crate, getPrice, getOwnedCount, resolveItemID)
  local function ownedCount(id)
    if not id then return 0 end
    return getOwnedCount(id) or 0
  end
  local id = crate.id or resolveItemID(crate.name)
  local cratePrice = getPrice(id)
  local crateOwned = ownedCount(id) > 0
  local effectiveCrateCost = crateOwned and 0 or cratePrice
  local best, bundleCost, bundleName, missingQty, ownedQty

  for _, bundle in ipairs(crate.bundles) do
    local itemID = resolveItemID(bundle.name)
    local have = math.min(bundle.qty, ownedCount(itemID))
    local missing = bundle.qty - have
    local unitPrice = getPrice(itemID)
    local cost = (missing == 0 and 0) or (unitPrice and unitPrice * missing)
    if cost and (not best or cost < bundleCost) then
      best = true
      bundleCost = cost
      bundleName = bundle
      missingQty = missing
      ownedQty = have
    end
  end

  local rate = effectiveCrateCost and best and bundleCost and
    (type(crate.favour) == "number" and crate.favour > 0) and
    (effectiveCrateCost + bundleCost) / crate.favour or nil
  return rate, effectiveCrateCost, bundleName, bundleCost, missingQty, ownedQty, crateOwned
end
