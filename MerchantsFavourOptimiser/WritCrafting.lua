MFO_WritCrafting = {}
local Craft = MFO_WritCrafting
local cost = MFO_WritCalculations.costRequirements
local MAX_DEPTH, MAX_BRANCHES = 8, 4096
local recipeOwner, verified = nil, {}

function Craft.Enabled()
  return MFO_DB and MFO_DB.writCrafting == true
end

local function verifiedSchematic(id, recipe, schematic, rank)
  if not schematic or schematic.outputItemID ~= id or schematic.quantityMin ~= recipe.output
    or schematic.quantityMax ~= recipe.output or schematic.isRecraft
    or (schematic.recipeType and schematic.recipeType ~= 1)
    or type(schematic.reagentSlotSchematics) ~= "table" then return end
  local reagents = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics) do
    local reagent = slot.reagents and slot.reagents[1]
    if slot.reagentType ~= 1 or not reagent or not reagent.itemID or reagent.currencyID
      or #slot.reagents ~= 1 or (slot.variableQuantities and #slot.variableQuantities > 0)
      or type(slot.quantityRequired) ~= "number" or slot.quantityRequired < 1
      or (slot.slotInfo and (slot.slotInfo.requiredSkillRank or 0) > rank) then return end
    reagents[reagent.itemID] = (reagents[reagent.itemID] or 0) + slot.quantityRequired
  end
  for reagent, qty in pairs(recipe.reagents) do
    if reagents[reagent] ~= qty then return end
    reagents[reagent] = nil
  end
  return not next(reagents)
end

local function readRecipe(id, recipe, api, activeLine)
  local spell = recipe.spell
  local personal = activeLine == recipe.line
  local info = (personal or not activeLine) and api.GetRecipeInfo(spell)
  local learned = info and info.learned == true and info.recipeID == spell
    and not info.disabled and info.craftable ~= false and not info.supportsQualities
  if personal and not learned then verified[id] = nil end
  if not learned and (personal or not verified[id]) then return end
  if api.IsRecipeProfessionLearned(spell) ~= true then
    verified[id] = nil
    return
  end
  local profession = api.GetProfessionInfoByRecipeID(spell)
  if not profession or (profession.professionID ~= recipe.line and profession.parentProfessionID ~= recipe.line)
    or type(profession.skillLevel) ~= "number" or profession.skillLevel < (recipe.skill or 1) then return end
  local name = verified[id]
  if learned then
    if not verifiedSchematic(id, recipe, api.GetRecipeSchematic(spell, false), profession.skillLevel) then
      verified[id] = nil
      return
    end
    name = info.name or true
    if personal and recipeOwner then verified[id] = name end
  end
  local requirements = api.GetRecipeRequirements(spell)
  if type(requirements) ~= "table" then return end
  local toolCount, focusCount, tools = 0, 0, {}
  local station = recipe.station
  for _, requirement in ipairs(requirements) do
    -- A verified workstation can be visited before crafting. Other unmet requirements block the estimate.
    if requirement.type == 0 and recipe.station then
      focusCount = focusCount+1
      if focusCount > 1 then return end
      station = requirement.name or station
    elseif requirement.met ~= true then
      return
    elseif requirement.type == 1 then
      toolCount = toolCount+1
      if requirement.name then tools[#tools+1] = requirement.name end
    end
  end
  if toolCount < (recipe.tools or 0) then return end
  local cooldown = C_Spell.GetSpellCooldown(spell)
  if not cooldown or cooldown.isEnabled ~= true or type(cooldown.duration) ~= "number"
    or (cooldown.duration > 0 and not cooldown.isOnGCD) then return end
  return {
    name=type(name) == "string" and name or nil,
    profession=profession.professionName or recipe.profession, skill=recipe.skill,
    station=station, tools=tools, output=recipe.output, reagents=recipe.reagents,
    maxCasts=recipe.cooldown and 1 or nil,
  }
end

-- Read current-character data only. A missing or incompatible API leaves buying available.
function Craft.Recipes(capture)
  local api = C_TradeSkillUI
  if not Craft.Enabled() or not api or not C_Spell or not C_Spell.GetSpellCooldown
    or not api.GetRecipeInfo or not api.GetProfessionInfoByRecipeID or not api.GetRecipeSchematic
    or not api.IsRecipeProfessionLearned or not api.GetRecipeRequirements
    or (api.IsDataSourceChanging and api.IsDataSourceChanging())
    or (api.IsTradeSkillLinked and api.IsTradeSkillLinked())
    or (api.IsTradeSkillGuild and api.IsTradeSkillGuild())
    or (api.IsNPCCrafting and api.IsNPCCrafting()) then return end
  local owner = MFO_WritTracking and MFO_WritTracking.CharacterKey()
  if owner ~= recipeOwner then recipeOwner, verified = owner, {} end
  local viewing = capture or (ProfessionsFrame and ProfessionsFrame:IsShown())
  local profession = viewing and api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
  local activeLine = profession and profession.professionID
  if activeLine == 0 then activeLine = nil end
  local recipes = {}
  for id, recipe in pairs(MFO_WritRecipes) do
    local ok, current = pcall(readRecipe, id, recipe, api, activeLine)
    if ok and current then recipes[id] = current end
  end
  return next(recipes) and recipes or nil
end

function Craft.AddScanMaterials(id, add, visited)
  if visited[id] then return end
  visited[id] = true
  local recipe = MFO_WritRecipes[id]
  if recipe then
    for reagent in pairs(recipe.reagents) do
      add(reagent)
      Craft.AddScanMaterials(reagent, add, visited)
    end
  end
end

local function sortedIDs(items)
  local ids = {}
  for id in pairs(items) do ids[#ids+1] = id end
  table.sort(ids)
  return ids
end

-- Price all turn-in requirements together. Process outputs before inputs so
-- direct demand and demand from every recipe compete for the same owned stock.
function Craft.Solve(requirements, acquisitions, reputation, getPrice, getOwned, recipes, totalOnly)
  local baseline, reason = cost(requirements, acquisitions, reputation, getPrice, getOwned)
  if not recipes then return baseline, reason end
  local candidate
  for id in pairs(baseline.shopping) do
    if recipes[id] and not acquisitions[id] then candidate = true; break end
  end
  if not candidate then return baseline, reason end
  local order, positions, stack, cyclic, demand, usable = {}, {}, {}, {}, {}, {}
  local depthLimited = false
  local function visit(id, depth)
    local position = positions[id]
    if position then
      if position > 0 then
        for index=position,#stack do cyclic[stack[index]] = true end
      end
      return
    end
    stack[#stack+1] = id
    positions[id] = #stack
    local recipe = not acquisitions[id] and recipes[id]
    if recipe and depth < MAX_DEPTH then
      for _, reagent in ipairs(sortedIDs(recipe.reagents)) do
        visit(reagent, depth+1)
      end
      if not cyclic[id] then usable[id] = recipe end
    elseif recipe then
      depthLimited = true
    end
    positions[id] = 0
    stack[#stack] = nil
    order[#order+1] = id
  end
  for _, id in ipairs(sortedIDs(requirements)) do
    demand[id] = requirements[id]
    visit(id, 0)
  end
  if not next(usable) then
    baseline.craftLimited = depthLimited
    return baseline, reason
  end

  local required, casts, best, prices, stock = {}, {}, nil, {}, {}
  for _, id in ipairs(order) do
    local unit, stale = getPrice(id)
    prices[id] = type(unit) == "number" and unit > 0 and unit < math.huge
      and unit == math.floor(unit) and not stale and unit or nil
    local qty = getOwned and getOwned(id) or 0
    stock[id] = type(qty) == "number" and qty >= 0 and qty < math.huge and qty == math.floor(qty) and qty or 0
  end
  local branches, limited, priceCeiling = 0, depthLimited, baseline.total
  local function search(index, total, usedCraft, remaining)
    -- Walk straight through purchase-only rows to keep recursion proportional to recipe choices.
    while index > 0 and not usable[order[index]] do
      local id = order[index]
      local qty = demand[id] or 0
      required[id] = qty > 0 and qty or nil
      local buy = math.max(0, qty-stock[id])
      if buy > 0 then
        if not prices[id] then return end
        total = total + buy*prices[id]
      end
      index = index-1
    end
    if (best and total >= best.total) or (priceCeiling and total >= priceCeiling) then return end
    if index == 0 then
      if usedCraft then
        if totalOnly then
          best = {total=total}
          return
        end
        local procurement, steps, materials = {}, {}, {}
        for id, qty in pairs(required) do procurement[id] = qty end
        for _, id in ipairs(order) do
          if casts[id] and casts[id] > 0 then
            local recipe = usable[id]
            steps[#steps+1] = {id=id, recipe=recipe, casts=casts[id]}
            for reagent, qty in pairs(recipe.reagents) do
              materials[reagent] = (materials[reagent] or 0) + qty*casts[id]
            end
          end
        end
        best = {total=total, required=procurement, steps=steps, materials=materials}
      end
      return
    end
    local id = order[index]
    local qty, recipe = demand[id] or 0, usable[id]
    local shortage = math.max(0, qty-stock[id])
    local maximum = math.min(math.ceil(shortage/recipe.output), recipe.maxCasts or math.huge)
    local minimum = prices[id] and 0 or math.ceil(shortage/recipe.output)
    for count=maximum,minimum,-1 do
      if branches >= MAX_BRANCHES then limited = true; break end
      branches = branches+1
      local supplied = math.min(shortage, count*recipe.output)
      local buy = shortage-supplied
      required[id] = qty > supplied and qty-supplied or nil
      casts[id] = count
      for reagent, units in pairs(recipe.reagents) do
        demand[reagent] = (demand[reagent] or 0) + units*count
      end
      search(index-1, total+buy*(prices[id] or 0), usedCraft or count > 0)
      for reagent, units in pairs(recipe.reagents) do
        demand[reagent] = demand[reagent] - units*count
      end
    end
  end
  search(#order, 0, false)
  if totalOnly then
    local result = best or baseline
    result.craftLimited = limited
    return result
  end
  -- When buying wins, price a crafting alternative for display without changing
  -- the cost used to rank and budget the same plan in the planner.
  if not best and not limited and priceCeiling then
    branches, priceCeiling = 0, nil
    search(#order, 0, false)
  end
  if not best then
    baseline.craftLimited = limited
    if not limited then baseline.crafting = {buy=baseline.total} end
    return baseline, reason
  end
  local useCraft = not baseline.total or best.total < baseline.total
  local result = useCraft and cost(best.required, acquisitions, reputation, getPrice, getOwned) or baseline
  result.crafting = {
    buy=baseline.total, craft=best.total,
    savings=baseline.total and (baseline.total-result.total) or nil,
    steps=best.steps, materials=best.materials, chosen=useCraft,
  }
  result.craftLimited = limited
  result.procurement = useCraft and best.required or nil
  return result
end

function Craft.Describe(result, money, name, add)
  if not result then return end
  local plan = result.crafting
  if plan then
    local function format(value) return value and money(value) or "Unknown" end
    add("Buy Finished Items: "..format(plan.buy).." | With Crafting: "..format(plan.craft))
    if plan.craft then
      add((plan.chosen and "Recommended: Craft Manually" or "Recommended: Buy Finished Items")..
        " | Estimated Savings: "..format(plan.savings))
      add(plan.chosen and "Craft in this order after getting the materials:" or "Materials for the crafting alternative:")
    end
    for _, step in ipairs(plan.steps or {}) do
      local recipe = step.recipe
      local materials = {}
      for _, id in ipairs(sortedIDs(recipe.reagents)) do
        materials[#materials+1] = (recipe.reagents[id]*step.casts).."x "..(name(id) or ("Item #"..id))
      end
      add(("%dx %s (%s%s%s, makes %d)"):format(step.casts, recipe.name or name(step.id)
        or ("Item #"..step.id), recipe.profession, recipe.skill and (" "..recipe.skill) or "",
        recipe.station and (" at "..recipe.station) or "", step.casts*recipe.output))
      add("  "..table.concat(materials, ", "))
      if recipe.tools and #recipe.tools > 0 then add("  Tools: "..table.concat(recipe.tools, ", ")) end
    end
  end
  if result.craftLimited then add("Crafting search limit reached. Costs are estimates.") end
end
