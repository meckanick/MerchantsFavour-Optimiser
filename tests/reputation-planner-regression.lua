local root="MerchantsFavourOptimiser/"
dofile(root.."Calculations.lua")
dofile(root.."WritCalculations.lua")
dofile(root.."ReputationPlanner.lua")
local Planner=MFO_ReputationPlanner
local function equal(actual, expected, message)
  assert(actual==expected,message.." (expected "..tostring(expected)..", got "..tostring(actual)..")")
end
local function writ(id, rep, faction, material, qty, daily)
  return {id=id,reputation=rep,faction=faction,daily=daily,items={{id=material,qty=qty}}}
end
MFO_WritData={
  writ(10,75,"Both",100,3,true),
  writ(11,75,"Alliance",100,2,true),
  writ(12,200,"Horde",100,1,true),
  writ(13,125,"Both",101,1,true),
  writ(14,125,"Both",101,1,false),
}
local crates={
  {id=1,favour=25,materialID=100,bundle={qty=2},turnIn=20},
  {id=1,favour=25,materialID=102,bundle={qty=1},turnIn=20},
}
local prices={[1]=10,[10]=20,[11]=45,[12]=1,[13]=1,[14]=1,[100]=15,[101]=1,[102]=100}
local stale={}
local stock={[100]=4}
local function plan(mode,target,budget,limit,availability)
  return assert(Planner.plan(mode,target,budget,limit,"Alliance",availability,crates,
    function(id) return prices[id],stale[id] end,function(id) return stock[id] or 0 end))
end
equal(Planner.goldBudget("7.0123"),70123,"four decimal places convert to copper")
equal(Planner.goldBudget("0"),0,"zero is a valid budget")
equal(Planner.goldBudget("0.00001"),nil,"fractional copper rejected")
equal(Planner.goldBudget("1e3"),nil,"scientific notation rejected")
equal(Planner.goldBudget("1234567890"),nil,"unbounded gold rejected")

local mixed=plan("Combined",100,nil,1,{[10]=true,[12]=true,[13]=false,[14]=true,[99]=true})
equal(mixed.reputation,100,"mixed plan hits target")
equal(mixed.writIDs[1],10,"only faction-eligible daily Writ can be selected")
equal(#mixed.writIDs,1,"only verified daily Writs can be selected")
equal(mixed.required[100],5,"combine crate and Writ requirements")
equal(mixed.owned[100],4,"count owned stock once")
equal(mixed.shopping[100],1,"buy shared shortfall once")
equal(mixed.writCost,30,"include crate and Writ acquisition costs")
equal(mixed.itemCost,15,"charge required items separately")
equal(mixed.total,45,"budget against gross cost")
equal(mixed.turnIn,20,"display crate reward separately")
equal(mixed.remaining,0,"no target remains")
equal(mixed.overfill,0,"exact plan")
equal(mixed.unknown,1,"unknown completion is explicit")
equal(mixed.confirmed,1,"non-daily and foreign Writs do not count")

local partial=plan("Combined",100,44,1,{[10]=true})
equal(partial.reputation,75,"best affordable partial plan")
equal(partial.remaining,25,"remaining target reported")
equal(partial.total,20,"cheapest among equally useful partial plans")
equal(partial.budgetLeft,24,"remaining budget reported")
local exactBudget=plan("Combined",100,45,1,{[10]=true})
equal(exactBudget.reputation,100,"exact budget permits the mixed plan")
equal(exactBudget.budgetLeft,0,"exact budget fully consumed")
local zero=plan("Combined",100,0,1,{[10]=true})
equal(zero.reputation,0,"future crate rewards cannot fund purchases")
equal(zero.remaining,100,"unaffordable target remains intact")
equal(zero.budgetLeft,0,"zero-budget output is explicit")

local limited=plan("Writs",150,nil,1,{[10]=true,[11]=true})
equal(limited.reputation,75,"daily limit is shared across Writ types")
equal(limited.writIDs[1],10,"cheapest legal partial plan")
local two=plan("Writs",150,nil,2,{[10]=true,[11]=true})
equal(two.reputation,150,"can use two distinct dailies")
equal(two.shopping[100],1,"Writs share the same stock")
equal(plan("Writs",150,nil,2,{[10]=true}).reputation,75,"one quest cannot be repeated")
equal(plan("Writs",75,nil,0,{[10]=true}).reputation,0,"zero daily slots excludes Writs")
equal(plan("Writs",75,nil,2,{[10]=false}).reputation,0,"completed and unknown Writs excluded")
equal(plan("Writs",70,nil,1,{[10]=true}).overfill,5,"report reputation overfill")
equal(plan("Crates",40,nil,nil,{[10]=true}).reputation,50,"Crates mode can repeat crates")

prices[100]=nil
local stockOnly=plan("Combined",100,nil,1,{[10]=true})
equal(stockOnly.reputation,100,"fully owned materials need no quote")
equal(stockOnly.shopping[100],nil,"missing quote cannot enter shopping list")
equal(stockOnly.required[102],1,"choose alternate crate bundle after shared stock is used")
prices[102]=nil
equal(plan("Combined",100,nil,1,{[10]=true}).reputation,75,"exclude unpriced shared demand after stock runs out")
stale[10]=true
equal(plan("Writs",75,nil,1,{[10]=true}).reputation,0,"stale Writ acquisition quote excluded")
stock[10]=1
equal(plan("Writs",75,0,1,{[10]=true}).reputation,75,"owned Writ and materials need no quote")
equal(plan("Writs",100,nil,2,{}).remaining,100,"unreachable target reports full remainder")
assert(not Planner.plan("Writs",100,nil,-1,"Alliance",{},crates))
assert(not Planner.plan("Combined",100,nil,nil,"Alliance",{},crates))
assert(not Planner.plan("Crates",1001,nil,nil,"Alliance",{},crates))
assert(not Planner.plan("Crates",100,-1,nil,"Alliance",{},crates))

-- Gross cost is the primary outcome. Equal-cost complete plans prefer less overfill.
prices[10],prices[13],stale[10]=1,1,nil
stock[10],stock[13],stock[101]=1,1,1
equal(plan("Writs",75,0,1,{[10]=true,[13]=true}).reputation,75,"equal-cost plans avoid overfill")

-- Exercise the supported upper target against the in-addon data and all crate alternatives.
dofile(root.."Data.lua")
dofile(root.."WritData.lua")
local confirmed, fullCrates, materialIDs={}, {}, {}
for _,option in ipairs(MFO_WritData) do confirmed[option.id]=true end
for _,crate in ipairs(MFO_DATA) do
  if not crate.name:find("Artisan",1,true) then
    for _,bundle in ipairs(crate.bundles) do
      materialIDs[bundle.name]=materialIDs[bundle.name] or 1000000+#fullCrates
      fullCrates[#fullCrates+1]={id=crate.id,favour=crate.favour,
        materialID=materialIDs[bundle.name],bundle=bundle}
    end
  end
end
local started=os.clock()
local full=assert(Planner.plan("Combined",1000,100000,#MFO_WritData,"Alliance",confirmed,
  fullCrates,function(id) return 20+id%17 end,function(id) return id%3==0 and 3 or 0 end))
equal(full.remaining,0,"maximum target and complete data finish")
assert(full.total<=100000 and #full.writIDs<=#MFO_WritData)
print(("PASS: reputation modes, budgets, dailies, shared stock, freshness and partial plans (full-data search %.3fs)"):format(os.clock()-started))
