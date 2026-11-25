-- Bounded planning for Writs and budgeted or mixed turn-ins.
MFO_ReputationPlanner = {}
local Planner = MFO_ReputationPlanner
local Writ = MFO_WritCalculations
local MAX_CRAFT_EXTENSIONS = 512

function Planner.goldBudget(text)
  local whole, decimals = text:match("^(%d+)%.(%d*)$")
  if not whole then whole, decimals = text:match("^(%d+)$"), "" end
  if not whole or #whole > 9 or #decimals > 4 then return nil end
  return tonumber(whole)*10000 + tonumber(decimals..string.rep("0",4-#decimals))
end

function Planner.plan(mode, target, budget, dailyLimit, faction, questStates, crates, getPrice, getOwned, recipes)
  if not MFO_Calculations.validTarget(target) then
    return nil, "Enter a Whole-Number Favour Target Between 1 and 1000."
  end
  if budget ~= nil and (type(budget) ~= "number" or budget < 0 or budget >= math.huge or budget ~= math.floor(budget)) then
    return nil, "Enter a Valid Gold Budget."
  end
  if mode ~= "Crates" and (type(dailyLimit) ~= "number" or dailyLimit < 0 or dailyLimit > #MFO_WritData
    or dailyLimit ~= math.floor(dailyLimit)) then
    return nil, "Enter a Daily Writ Limit From 0 to "..#MFO_WritData.."."
  end

  if mode == "Crates" then recipes = nil end
  local prices, stock = {}, {}
  local function price(id)
    if prices[id] == nil then
      local value, stale = getPrice(id)
      prices[id] = type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value) and not stale and value or false
    end
    return prices[id]
  end
  local function owned(id)
    if stock[id] == nil then stock[id] = math.max(0, math.floor(getOwned(id) or 0)) end
    return stock[id]
  end

  local options, uses, confirmed, unknown, pruned = {}, {}, 0, 0, false
  local function add(option, demand)
    if recipes then
      local estimate = Writ.estimate(demand, {[option.id]=1}, 0, price, owned, recipes, true)
      if estimate.craftLimited then pruned = true end
      if not estimate.total then return end
      option.demand = demand
      options[#options+1] = option
      return
    end
    local paid, tracked = 0, {}
    for id, qty in pairs(demand) do
      local unit, count = price(id), owned(id)
      if not unit and count < qty then return end
      if count > 0 then tracked[id] = qty end
      paid = paid + (unit or 0) * qty
    end
    for id in pairs(tracked) do uses[id] = (uses[id] or 0) + 1 end
    option.demand, option.tracked, option.paid = demand, tracked, paid
    options[#options+1] = option
  end

  if mode ~= "Crates" then
    for _, writ in ipairs(Writ.available(faction)) do
      local state = questStates[writ.id]
      if state == nil then unknown = unknown + 1 end
      if writ.daily == true and MFO_WritTracking.Eligible(state) then
        confirmed = confirmed + 1
        if dailyLimit > 0 then
          local demand = Writ.selectionRequirements({writ.id}, faction)
          if demand then
            add({id=writ.id, favour=writ.reputation, writ=true}, demand)
          end
        end
      end
    end
  end
  if mode ~= "Writs" then
    for _, crate in ipairs(crates) do
      if crate.id and crate.materialID and crate.id ~= crate.materialID
        and MFO_Calculations.validTarget(crate.favour) then
        add(crate, {[crate.id]=1, [crate.materialID]=crate.bundle.qty})
      end
    end
  end

  local stride = 0
  for _, option in ipairs(options) do
    local reward = option.favour
    while reward > 0 do stride, reward = reward, stride % reward end
    -- Stock exclusive to one daily cannot affect any later option's price.
    if option.writ and not recipes then
      for id, qty in pairs(option.tracked) do
        if uses[id] == 1 then
          option.paid = option.paid - (prices[id] or 0) * math.min(stock[id], qty)
          option.tracked[id] = nil
        end
      end
    end
  end
  stride = math.max(1, stride)
  local firstPossible = math.ceil(target/stride)*stride

  -- Process each Writ once (descending reputation), then allow repeatable crates
  -- (ascending). For the same reputation and Writ count, keep a few distinct
  -- remaining-stock states. With identical remaining stock, cheaper dominates.
  local empty = {total=0, used={}, acquisitions={}}
  local noStates = {}
  local states, best = {[0]={[0]={empty}}}, empty
  local bestRep = 0
  local craftExtensions = 0
  local function craftSearchFull()
    return recipes and craftExtensions >= MAX_CRAFT_EXTENSIONS
  end
  local function better(rep, total)
    if rep >= target then
      return bestRep < target or total < best.total or (total == best.total and rep < bestRep)
    end
    return bestRep < target and (rep > bestRep or (rep == bestRep and total < best.total))
  end
  for _, option in ipairs(options) do
    if craftSearchFull() or (bestRep == firstPossible and best.total == 0) then break end
    local step = option.writ and -stride or stride
    local first, last = 0, firstPossible-stride
    if option.writ then first, last = last, first end
    for rep=first,last,step do
      if craftSearchFull() or (bestRep == firstPossible and best.total == 0) then break end
      for count, bucket in pairs(states[rep] or noStates) do
        local nextCount = count + (option.writ and 1 or 0)
        if not option.writ or nextCount <= dailyLimit then
          for _, state in ipairs(bucket) do
            local total, demand, acquired
            if recipes then
              if craftSearchFull() then break end
              craftExtensions = craftExtensions + 1
              demand, acquired = {}, {}
              for id, qty in pairs(state.used) do demand[id] = qty end
              for id, qty in pairs(option.demand) do demand[id] = (demand[id] or 0) + qty end
              for id, qty in pairs(state.acquisitions) do acquired[id] = qty end
              acquired[option.id] = (acquired[option.id] or 0) + 1
              local estimate = Writ.estimate(demand, acquired, 0, price, owned, recipes, true)
              if estimate.craftLimited then pruned = true end
              total = estimate.total or math.huge
            else
              total = state.total + option.paid
              for id, qty in pairs(option.tracked) do
                local used, unit = state.used[id] or 0, prices[id]
                if not unit and used + qty > stock[id] then total = math.huge; break end
                if unit then total = total - math.min(qty, stock[id] - used) * unit end
              end
            end
            if total < math.huge and (not budget or total <= budget) then
              local nextRep = rep + option.favour
              local wins = better(nextRep, total)
              local cell
              if nextRep < target and (bestRep < target or total <= best.total) then
                states[nextRep] = states[nextRep] or {}
                cell = states[nextRep][nextCount] or {}
                states[nextRep][nextCount] = cell
              end
              if wins or (cell and (#cell < 4 or total <= cell[#cell].total)) then
                local used = demand or state.used
                if not recipes and next(option.tracked) then
                  used = {}
                  for id, qty in pairs(state.used) do used[id] = qty end
                  for id, qty in pairs(option.tracked) do
                    used[id] = math.min(stock[id], (used[id] or 0) + qty)
                  end
                end
                local node = {total=total, used=used, acquisitions=acquired, previous=state, option=option}
                if wins then best, bestRep = node, nextRep end
                if cell then
                  local duplicate
                  for i, other in ipairs(cell) do
                    local same = true
                    for id, qty in pairs(used) do
                      if other.used[id] ~= qty then same = false; break end
                    end
                    if same then
                      for id in pairs(other.used) do
                        if not used[id] then same = false; break end
                      end
                    end
                    if same then duplicate = i; break end
                  end
                  if not duplicate or total < cell[duplicate].total then
                    if duplicate then table.remove(cell, duplicate) end
                    local index = #cell+1
                    while index > 1 and total < cell[index-1].total do index = index-1 end
                    table.insert(cell, index, node)
                    if #cell > 4 then cell[5] = nil; pruned = true end
                  end
                end
              elseif cell then
                pruned = true
              end
            end
          end
        end
      end
    end
  end

  if craftSearchFull() then
    pruned = true
    -- Later options may still offer a better buy-only plan.
    local buy = Planner.plan(mode, target, budget, dailyLimit, faction, questStates, crates, getPrice, getOwned)
    if better(buy.reputation, buy.total) then
      buy.pruned = true
      return buy
    end
  end

  local demand, acquisitions, quantities = {}, {}, {}
  local node = best
  while node.option do
    local option = node.option
    quantities[option] = (quantities[option] or 0) + 1
    acquisitions[option.id] = (acquisitions[option.id] or 0) + 1
    for id, qty in pairs(option.demand) do demand[id] = (demand[id] or 0) + qty end
    node = node.previous
  end
  local result = Writ.estimate(demand, acquisitions, bestRep, price, owned, recipes)
  result.required, result.details, result.writIDs, result.turnIn = demand, {}, {}, 0
  for _, option in ipairs(options) do
    local qty = quantities[option]
    if qty then
      result.details[#result.details+1] = {option=option, qty=qty}
      if option.writ then result.writIDs[#result.writIDs+1] = option.id end
      result.turnIn = result.turnIn + qty * (option.turnIn or 0)
    end
  end
  result.remaining, result.overfill = math.max(0, target-bestRep), math.max(0, bestRep-target)
  result.budgetLeft = budget and budget-result.total
  result.confirmed, result.unknown, result.pruned = confirmed, unknown, pruned
  return result
end
