local root="MerchantsFavourOptimiser/"
dofile(root.."WritCalculations.lua")
dofile(root.."WritTracking.lua")
dofile(root.."CrateTracking.lua")
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
GetRealmName=function() return "Test" end
UnitName=function() return "Tester" end
local faction="Alliance"
UnitFactionGroup=function() return faction end
MFO_WritData={
 {id=10,questID=910,daily=true,reputation=75,faction="Both",items={{id=100,qty=2},{id=100,qty=1}}},
 {id=11,questID=911,daily=true,reputation=75,faction="Alliance",items={{id=100,qty=2},{id=101,qty=1}}},
 {id=12,questID=912,daily=true,reputation=75,faction="Horde",items={{id=100,qty=20}}},
}
local completed,active={},true
C_QuestLog={
 GetLogIndexForQuestID=function(id) return active and id or nil end,
 IsComplete=function() return true end,
 IsQuestFlaggedCompleted=function(id) return completed[id]==true end,
}
MFO_DB={useOwned=true}
dofile(root.."StandaloneAH.lua")
local AH=MFO_AH
local bags,bank={[1]=1,[10]=1,[11]=1,[100]=5},{}
local bankStamp=10
AH.ShoppingItemStock=function(id) return bags[id] or 0,bank[id] or 0,bankStamp end
AH.SetOwnedReader(function(id) return (bags[id] or 0)+(bank[id] or 0) end)
local function name(id) return "Item "..id end
assert(AH.ReplaceShopping({[1]={qty=0,requiredQty=1},[100]={qty=0,requiredQty=3}}))
local crates={{crateID=1,quantity=1,materialID=100,materialQty=3}}
assert(AH.SetShoppingCratePlan(crates))
assert(AH.AddShoppingWrits({10,11},name))
local items=AH.Shopping()
assert(items[100].requiredQty==8 and items[100].qty==3,"aggregate repeated IDs with crate demand")
assert(items[10].requiredQty==1 and items[10].qty==0,"owned Writ still has acquisition demand")
assert(items[101].qty==1 and AH.Price(101)==nil,"missing quotes must not prevent shopping")
assert(not AH.AddShoppingWrits({10},name) and items[100].requiredQty==8)
assert(not AH.AddShoppingWrits({12},name) and not items[12],"reject restricted selection")
assert(AH.ShoppingCratePlan()[1].crateID==1)
local function readiness()
 return AH.ShoppingWritReadiness(MFO_CrateTracking.Evaluate(crates,bags,bank,bankStamp))
end
assert(readiness()[10].missing==1,"crate consumes stock before Writs")
assert(readiness()[11].missing==3,"first Writ consumes remaining shared stock")
assert(AH.RecordShoppingPurchase(100,2))
assert(AH.RecordShoppingPurchase(101,1))
AH.RecalculateShopping()
assert(items[100].qty==1 and items[101].qty==0)
assert(readiness()[11].missing==3,"purchase records cannot satisfy readiness")
bags[100]=6
AH.RecalculateShopping()
assert(items[100].qty==1 and items[100].pendingPurchaseQty==1)
assert(readiness()[10].missing==0 and readiness()[11].missing==3)
bags[100]=7
bank[100],bank[101]=1,1
AH.RecalculateShopping()
assert(items[100].qty==0 and items[100].purchasedQty==2 and items[100].pendingPurchaseQty==0)
assert(readiness()[11].missing==0 and readiness()[11].withdraw==2)
assert(not readiness()[11].ready,"bank stock cannot make a Writ deliverable")
bankStamp=nil
assert(readiness()[11].missing==2,"unverified cached bank cannot satisfy readiness")
bags[100],bags[101],bank[100],bank[101]=8,1,0,0
AH.RecalculateShopping()
assert(readiness()[11].missing==0 and readiness()[11].withdraw==0)
assert(readiness()[11].ready,"the quest is complete and allocated supplies are in bags")
bags[100]=7
AH.RecalculateShopping()
assert(items[100].qty==1 and readiness()[11].missing==1)
assert(AH.RemoveShoppingItem(10) and AH.ShoppingCratePlan() and not items[10])
assert(items[100].requiredQty==5 and readiness()[11].missing==0)
assert(AH.AddShoppingWrits({10},name) and items[100].requiredQty==8,"re-adding restores demand once")
faction="Horde"
assert(next(AH.Shopping())==nil and not AH.AddShoppingWrits({10,11},name))
assert(AH.AddShoppingWrits({12},name))
faction="Alliance"
assert(items==AH.Shopping() and not items[12])
AH.ClearShopping()
assert(not next(AH.Shopping()) and not next(readiness()))

-- Older market rows contain only a net quantity. Existing stock only offsets new demand.
MFO_DB={useOwned=true,shopping={[100]={name="Old listing",qty=4}}}
assert(AH.AddShoppingWrits({10},name))
assert(AH.Shopping()[100].qty==4)
assert(AH.RemoveShoppingItem(10))
assert(AH.Shopping()[100].qty==4,"removing a Writ preserves legacy net demand")
assert(AH.ReplaceShopping({[100]={qty=1,requiredQty=1}}))
assert(not next(readiness()),"crate replacement clears Writ metadata")
-- A complete planner transfer replaces quantities and retains both kinds of readiness.
local replacement={[1]={qty=0,requiredQty=1},[10]={qty=0,requiredQty=1},
 [100]={qty=0,requiredQty=6}}
assert(not AH.ReplaceShopping(replacement,{12}),"restricted plan cannot erase the previous list")
assert(AH.Shopping()[100].requiredQty==1)
assert(not AH.ReplaceShopping({[10]={qty=1}},{10}),"partial demand cannot erase the previous list")
assert(AH.Shopping()[100].requiredQty==1)
local selection={10}
assert(AH.ReplaceShopping(replacement,selection))
selection[1]=12
assert(AH.SetShoppingCratePlan(crates))
assert(AH.Shopping()[100].requiredQty==6 and AH.Shopping()[100].qty==0)
assert(readiness()[10] and AH.ShoppingCratePlan()[1].materialQty==3)
assert(AH.RemoveShoppingItem(10) and AH.Shopping()[100].requiredQty==3)
completed[910]=true
assert(not AH.AddShoppingWrits({10},name))
assert(not AH.ReplaceShopping(replacement,{10}) and AH.Shopping()[100].requiredQty==3)
completed[910]=nil
active=false
assert(not AH.AddShoppingWrits({10},name),"unknown Writ cannot be newly added")
active=true
assert(AH.AddShoppingWrits({10},name))
completed[910]=true
assert(readiness()[10].state=="completed" and not readiness()[10].ready)
assert(AH.Shopping()[10],"existing plan can be kept or removed by the player")
print("PASS: mixed Writ shopping, aggregation, shared readiness, partial purchases and faction isolation")
