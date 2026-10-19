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
    (effectiveCrateCost + bundleCost - (crate.turnInCopper or 0)) / crate.favour or nil
  return rate, effectiveCrateCost, bundleName, bundleCost, missingQty, ownedQty, crateOwned
end

-- Unbounded minimum-cost combination, with the last reward allowed to exceed
-- the target. Each option must have a fully priced crate and bundle.
-- An optional forced first option lets callers compare owned-stock scenarios.
function MFO_Calculations.plan(target, options, forced)
  if type(target)~="number" or target<1 or target~=math.floor(target) or target>1000 then
    return nil, "Enter a Favour Target Between 1 and 1000."
  end
  local maxReward=0
  for _,o in ipairs(options) do
    if type(o.favour)=="number" and o.favour>0 and o.favour==math.floor(o.favour)
      and type(o.cost)=="number" then
      maxReward=math.max(maxReward,o.favour)
    end
  end
  if maxReward==0 then return nil,"No Fully Priced Crates Available." end
  local limit=target+maxReward-1
  local dp={[0]={cost=0,items={}}}
  if forced then
    if not forced.favour or forced.favour>limit then return nil,"Invalid Starting Crate." end
    dp={[forced.favour]={cost=forced.cost,items={[forced.key]=1}}}
  end
  for favour=0,limit do
    local state=dp[favour]
    if state and favour<target then
      for _,o in ipairs(options) do
        if type(o.cost)=="number" and type(o.favour)=="number" and o.favour>0 then
          local nextFavour=favour+o.favour
          if nextFavour<=limit then
            local nextCost=state.cost+o.cost
            if not dp[nextFavour] or nextCost<dp[nextFavour].cost then
              local items={}
              for k,n in pairs(state.items) do items[k]=n end
              items[o.key]=(items[o.key] or 0)+1
              dp[nextFavour]={cost=nextCost,items=items}
            end
          end
        end
      end
    end
  end
  local best
  for favour=target,limit do
    local candidate=dp[favour]
    if candidate and (not best or candidate.cost<best.cost or
      (candidate.cost==best.cost and favour<best.favour)) then
      best={cost=candidate.cost,items=candidate.items,favour=favour}
    end
  end
  return best
end
