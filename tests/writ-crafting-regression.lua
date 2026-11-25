local root="MerchantsFavourOptimiser/"
for _, file in ipairs({"Calculations","WritData","WritCalculations","WritRecipes","WritTracking","WritCrafting","ReputationPlanner"}) do
  dofile(root..file..".lua")
end
local Craft=MFO_WritCrafting
local bySpell, covered={},0
for id, recipe in pairs(MFO_WritRecipes) do bySpell[recipe.spell]={id=id,recipe=recipe} end
for _, writ in ipairs(MFO_WritData) do
  if MFO_WritRecipes[writ.items[1].id] then covered=covered+1 end
end
assert(covered==129 and not MFO_WritRecipes[18258],"exclude the ambiguous Gordok Ogre Suit recipes")

local rank,activeLine,learned,linked,unusable,needsTool=300,164,{},false,false,false
local ready, wrongOutput, extraReagent, requiredArea=true,false,false,false
local remainingCooldown,onGCD=0,false
local playerName="Tester"
UnitName=function() return playerName end
GetRealmName=function() return "Forever" end
UnitFactionGroup=function() return "Alliance" end
ProfessionsFrame={IsShown=function() return activeLine~=nil end}
C_TradeSkillUI={
  IsTradeSkillLinked=function() return linked end,
  IsDataSourceChanging=function() return not ready end,
  GetBaseProfessionInfo=function() return activeLine and {professionID=activeLine} end,
  GetRecipeInfo=function(spell)
    local recipe=bySpell[spell].recipe
    if activeLine==recipe.line then
      return {recipeID=spell,learned=learned[spell]==true,disabled=unusable}
    end
  end,
  GetProfessionInfoByRecipeID=function(spell)
    return {professionID=bySpell[spell].recipe.line,skillLevel=rank}
  end,
  IsRecipeProfessionLearned=function() return rank>0 end,
  GetRecipeSchematic=function(spell)
    local entry=bySpell[spell]
    local slots={}
    for id,qty in pairs(entry.recipe.reagents) do
      slots[#slots+1]={reagentType=1,quantityRequired=qty,reagents={{itemID=id}}}
    end
    if extraReagent then slots[#slots+1]={reagentType=1,quantityRequired=1,reagents={{itemID=42}}} end
    return {outputItemID=entry.id,quantityMin=entry.recipe.output,recipeType=1,
      quantityMax=entry.recipe.output+(wrongOutput and 1 or 0),reagentSlotSchematics=slots}
  end,
  GetRecipeRequirements=function(spell)
    local recipe=bySpell[spell].recipe
    local result={}
    if recipe.station then result[1]={type=0,met=false,name=recipe.station} end
    for _=1,recipe.tools or 0 do result[#result+1]={type=1,met=not needsTool,name="Tool"} end
    if requiredArea then result[#result+1]={type=2,met=false,name="Area"} end
    return result
  end,
}
C_Spell={GetSpellCooldown=function() return {isEnabled=true,duration=remainingCooldown,isOnGCD=onGCD} end}
MFO_DB={}
assert(not Craft.Recipes(),"default preserves buy-only behavior")
MFO_DB.writCrafting=true
assert(not Craft.Recipes(),"unknown recipe")
learned[19666]=true
assert(Craft.Recipes()[15869].output==2 and Craft.Recipes()[15869].station=="Anvil")
ready=false
assert(not Craft.Recipes(),"profession data changing")
ready=true
needsTool=true
assert(not Craft.Recipes(),"missing crafting tool")
needsTool=false
requiredArea=true
assert(not Craft.Recipes(),"unmet area restriction")
requiredArea=false
linked=true
assert(not Craft.Recipes(),"linked professions are not character evidence")
linked=false
wrongOutput=true
assert(not Craft.Recipes(),"uncertain output quantity")
wrongOutput=false
extraReagent=true
assert(not Craft.Recipes(),"unexpected reagent")
extraReagent=false
unusable=true
assert(not Craft.Recipes(),"disabled recipe")
unusable=false
assert(Craft.Recipes()[15869])
activeLine,learned[17187]=171,true
local verified=Craft.Recipes()
assert(verified[15869] and verified[12360].maxCasts==1,"remember verified professions for this session")
rank=274
assert(not Craft.Recipes()[12360],"required rank")
rank=300
remainingCooldown=20
assert(not Craft.Recipes(),"active cooldown")
remainingCooldown,onGCD=1.5,true
assert(Craft.Recipes()[12360],"temporary global cooldown does not block planning")
remainingCooldown,onGCD=0,false
activeLine=nil
assert(Craft.Recipes()[15869] and Craft.Recipes()[12360],"verified recipes work at the Auction House")
playerName="Other"
assert(not Craft.Recipes(),"never reuse another character's known recipes")
playerName="Tester"
assert(not Craft.Recipes(),"no remembered evidence after switching characters")

local function recipe(output,reagents,maxCasts)
  return {output=output,reagents=reagents,maxCasts=maxCasts,profession="Blacksmithing"}
end
local prices,stock,stale={},{},{}
local function quote(id) return prices[id],stale[id] end
local function owned(id) return stock[id] or 0 end
local function solve(demand,recipes)
  return Craft.Solve(demand,{},100,quote,owned,recipes)
end
local recipes={[20]=recipe(2,{[30]=1,[40]=1}),[30]=recipe(2,{[50]=1}),
  [21]=recipe(1,{[30]=1}),[40]=recipe(1,{[60]=1},1)}
prices={[20]=80,[21]=80,[30]=20,[40]=30,[50]=4,[60]=5}
local result=solve({[20]=3,[21]=1,[30]=1},recipes)
assert(result.total==43 and result.crafting.buy==340 and result.crafting.savings==297)
assert(result.crafting.steps[#result.crafting.steps].id==20 or result.crafting.steps[#result.crafting.steps].id==21)
assert(result.crafting.materials[30]==3 and result.shopping[50]==2 and result.shopping[40]==1)
assert(result.shopping[60]==1 and not result.shopping[30],"one cooldown cast across the whole batch")
assert(result.crafting.materials[40]==2,"ceiling division charges for both batches")
stock={[30]=1,[50]=1}
result=solve({[20]=3,[21]=1,[30]=1},recipes)
assert(result.total==39 and result.owned[50]==1 and result.shopping[50]==1,"share stock and batch surplus")
prices[50],prices[30]=nil,nil
stock[30],stock[50]=0,0
result=solve({[20]=3,[21]=1,[30]=1},recipes)
assert(result.total==nil and #result.missingPrices>0,"exclude unaffordable dependency with missing price")
prices[30]=20
stock[30]=1
result=solve({[20]=1},recipes)
assert(result.total==5 and result.crafting.chosen,"fully owned unpriced reagent is usable")
prices[20],stale[40]=nil,true
assert(solve({[20]=1},recipes).total==5,"fully priced crafting may rescue an unknown buy estimate")
stock[60]=0; prices[60]=nil
result=solve({[20]=1},recipes)
assert(result.total==nil and result.crafting.craft==nil,"stale quote and missing transmute reagent exclude both routes")
prices,stock,stale={[20]=9,[30]=1,[40]=20},{},{}
result=solve({[20]=1},recipes)
assert(result.total==9 and result.crafting.craft==21 and not result.crafting.chosen,"buy wins against costly craft")
prices[40]=8
assert(not solve({[20]=1},recipes).crafting.chosen,"prefer buy on a tie")
assert(solve({[20]=1},nil).total==9,"missing recipe is buy-only")
assert(solve({[20]=1},{[20]=recipe(1,{[30]=1}),[30]=recipe(1,{[20]=1})}).total==9,"reject cycles")
assert(solve({[20]=1},{[20]=recipe(1,{[30]=1}),[30]=recipe(1,{[30]=1})}).total==1,
  "a cyclic intermediate can still be bought")
local deep={}
for id=20,32 do deep[id]=recipe(1,{[id+1]=1}) end
prices[33]=1
assert(solve({[20]=1},deep).total==9,"dependency depth has a finite bound")
prices[28]=1
result=solve({[20]=1},deep)
assert(result.total==1 and result.shopping[28]==1 and result.craftLimited,"buy at the dependency limit")
prices={[20]=3,[50]=1}
assert(solve({[20]=5000},{[20]=recipe(1,{[50]=1})}).craftLimited,"branch bound is disclosed")
prices,stock={[20]=100,[21]=200,[30]=150},{[30]=1}
result=solve({[20]=1,[21]=1},{[20]=recipe(1,{[30]=1}),[21]=recipe(1,{[30]=1})})
assert(result.total==100 and result.shopping[20]==1 and result.crafting.steps[1].id==21,
  "reserve scarce stock for the craft where it saves most")

MFO_WritData={
  {id=10,questID=910,daily=true,reputation=75,faction="Both",items={{id=20,qty=1}}},
  {id=11,questID=911,daily=true,reputation=75,faction="Both",items={{id=21,qty=1}}},
}
local crates={{id=1,materialID=30,bundle={qty=1},favour=20}}
prices={[1]=1,[10]=1,[11]=1,[20]=90,[21]=90,[30]=20}
stock={[30]=2}
recipes={[20]=recipe(2,{[30]=1}),[21]=recipe(1,{[30]=1})}
local states={[10]="objectives_complete",[11]="objectives_complete"}
local plan=MFO_ReputationPlanner.plan("Combined",170,23,2,"Alliance",states,crates,quote,owned,recipes)
assert(plan.reputation==170 and plan.total==23 and plan.shopping[30]==1 and plan.required[30]==1)
assert(plan.procurement[30]==3 and #plan.writIDs==2,"plan budgets the crate and both Writs against the same stock")

-- Exercise the real saved shopping and purchase helpers with a mixed plan.
C_QuestLog={
  GetLogIndexForQuestID=function(id) return id end,
  IsComplete=function() return true end,
  IsQuestFlaggedCompleted=function() return false end,
}
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
GetItemInfo=function(id) return "Item "..id end
time=function() return 100 end
local quotes={}
for id,price in pairs(prices) do quotes[id]={price=price,updated=time()} end
MFO_DB={useOwned=true,writCrafting=true,prices=quotes}
Craft.Recipes=function() return recipes end
dofile(root.."StandaloneAH.lua")
local AH=MFO_AH
local function bags(id) return owned(id),0 end
AH.ShoppingItemStock=bags
AH.SetOwnedReader(owned)
local items={[1]={qty=1},[10]={qty=1},[11]={qty=1},[20]={qty=1},[21]={qty=1},[30]={qty=1}}
assert(AH.ReplaceShopping(items,{10,11}))
assert(AH.SetShoppingCratePlan({{crateID=1,quantity=1,materialID=30,materialQty=1}}))
AH.RecalculateShopping()
assert(AH.Shopping()[30].requiredQty==3 and AH.Shopping()[30].qty==1 and not AH.Shopping()[20])
assert(AH.RecordShoppingPurchase(30,1))
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==0 and AH.Shopping()[30].pendingPurchaseQty==1)
assert(not AH.ShoppingWritReadiness()[10].ready,"purchased inputs never imply Writ readiness")
stock[30]=3
AH.RecalculateShopping()
assert(AH.Shopping()[30].pendingPurchaseQty==0 and AH.Shopping()[30].qty==0)
stock[30],stock[20],stock[21]=1,2,1
AH.RecalculateShopping()
assert(AH.Shopping()[30].requiredQty==1 and AH.Shopping()[30].qty==0,"actual output releases the reagent demand")
MFO_DB.writCrafting=false
AH.RecalculateShopping()
assert(AH.Shopping()[20] and AH.Shopping()[20].requiredQty==1 and not AH.ShoppingCraftEstimate())

-- With Use Owned off, purchased inputs can be spent while actual new outputs
-- reduce only the remaining shopping work. Existing bag stock stays excluded.
MFO_DB.useOwned,MFO_DB.writCrafting=false,true
stock={[30]=4}
assert(AH.ReplaceShopping(items,{10,11}))
assert(AH.SetShoppingCratePlan({{crateID=1,quantity=1,materialID=30,materialQty=1}}))
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==3)
assert(AH.RecordShoppingPurchase(30,1))
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==2 and AH.Shopping()[30].pendingPurchaseQty==1)
stock[30]=5
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==2)
stock[30],stock[20]=4,2
AH.RecalculateShopping()
assert(AH.Shopping()[20].qty==0 and AH.Shopping()[20].availableQty==1 and AH.Shopping()[30].qty==2,
  "crafted output counts as available, spent inputs cannot also fill a crate")
playerName="Other"
assert(AH.Shopping()[20].qty==1,"a character's crafted progress is private")
playerName="Tester"
assert(AH.RemoveShoppingItem(30))
assert(not AH.Shopping()[11] and AH.Shopping()[10] and not AH.ShoppingCratePlan(),
  "removing a reagent removes dependent planned turn-ins")

AH.ClearShopping()
stock={}
assert(AH.AddShoppingWrits({10},GetItemInfo))
assert(AH.Shopping()[30].qty==1 and AH.RecordShoppingPurchase(30,1))
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==0 and AH.Shopping()[30].pendingPurchaseQty==1)
dofile(root.."StandaloneAH.lua")
AH=MFO_AH
AH.ShoppingItemStock=bags
AH.SetOwnedReader(owned)
AH.RecalculateShopping()
assert(AH.Shopping()[30].qty==0 and AH.Shopping()[30].pendingPurchaseQty==1,
  "reagent-only rows preserve confirmed purchases across reload")
stock[30]=1
AH.RecalculateShopping()
assert(AH.Shopping()[30].pendingPurchaseQty==0 and AH.Shopping()[30].qty==0)

print("PASS: verified profession data, bounded recipe costs, shared stock, cooldowns, planner and manual shopping")
