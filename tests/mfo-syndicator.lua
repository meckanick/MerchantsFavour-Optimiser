-- Optional Syndicator v288-compatible inventory provider regressions (Lua 5.1).
-- Does not load Syndicator or require WoW APIs; mocks its documented public API.
local function equal(actual,expected,message)
 if actual~=expected then
  error(message..": expected "..tostring(expected)..", got "..tostring(actual),2)
 end
end
local function check(value,message) if not value then error(message,2) end end
local now=100
time=function() return now end
dofile("MerchantsFavourOptimiser/InventoryProvider.lua")
dofile("MerchantsFavourOptimiser/CrateTracking.lua")
local P=MFO_InventoryProvider
equal(P.Mode({}),"native","default inventory source")
equal(P.Mode({inventorySource="invalid"}),"native","invalid mode must be native")
equal(P.Mode({inventorySource="syndicator"}),"syndicator","explicit Syndicator mode")
local native={[101]=3,[102]=5,[9001]=1}
_G.Syndicator=nil
equal(P.IsAvailable(),false,"absent Syndicator must not be available")
local count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"missing Syndicator must fall back to native")
equal(source,"native","missing Syndicator provider label")
local bagTotal=P.TotalCount(101,{[101]=2},native,"syndicator")
equal(bagTotal,5,"native bag counted once with native bank fallback")
local snap,stamp=P.BankSnapshot(native,{[101]=true},nil,"syndicator")
equal(snap[101],nil,"unverified native bank must not be trusted for readiness")
equal(stamp,nil,"unverified native bank has no snapshot stamp")
snap,stamp=P.BankSnapshot(native,{[101]=true},50,"native")
equal(snap[101],3,"verified native bank retained")
equal(stamp,50,"native snapshot timestamp retained")

local ready=true
local pending=false
local current="Alpha-Forever"
local lookupCalls=0
local entries={
 [101]={
  characters={
   {character="Beta",realmNormalized="Forever",bank=999,bags=999,mail=999},
   {character="Alpha",realmNormalized="Elsewhere",bank=888,bags=999},
   {character="Alpha",realmNormalized="Forever",bank=7,bags=19,mail=50,auctions=40},
  },
  guilds={{bank=111}},warband={222},
 },
 [102]={characters={{character="Beta",realmNormalized="Forever",bank=55}}},
 [103]={characters={{character="Alpha",realmNormalized="Forever",bank=0}}},
}
_G.Syndicator={API={
 IsReady=function() return ready end,
 IsBagEventPending=function() return pending end,
 GetCurrentCharacter=function() return current end,
 GetInventoryInfoByItemID=function(id)
  lookupCalls=lookupCalls+1
  return entries[id]
 end,
}}
P.ResetCache()
equal(P.IsAvailable(),true,"Syndicator v288 mock available")
count,source=P.BankCount(101,native,"native")
equal(count,3,"native mode must ignore installed Syndicator")
equal(source,"native","native selection source")
count,source=P.BankCount(101,native,"syndicator")
equal(count,7,"only the current-character bank may count")
equal(source,"syndicator","Syndicator selection source")
local total,selected=P.TotalCount(101,{[101]=2},native,"syndicator")
equal(total,9,"bag plus Syndicator bank, without duplicate native bank")
equal(selected,"syndicator","effective source returned")
local before=lookupCalls
P.BankCount(101,native,"syndicator")
equal(lookupCalls,before,"repeated lookup cached within same second")
now=now+1
P.BankCount(101,native,"syndicator")
equal(lookupCalls,before+1,"lookup cache expires next second")

P.ResetCache()
count,source=P.BankCount(102,native,"syndicator")
equal(count,5,"other characters must not supply spendable bank stock")
equal(source,"native","other character fallback")
P.ResetCache()
count,source=P.BankCount(103,native,"syndicator")
equal(count,0,"explicit current-character zero is authoritative")
equal(source,"syndicator","explicit zero is external, not fallback")

P.ResetCache()
snap,stamp=P.BankSnapshot(native,{[101]=true,[9001]=true},nil,"syndicator")
equal(snap[101],7,"Syndicator bank present in coherent readiness snapshot")
equal(snap[9001],nil,"unverified native crate not admitted with Syndicator data")
equal(stamp,"syndicator","cached Syndicator source marker")
local sample={{crateID=9001,materialID=101,quantity=1,materialQty=5}}
local evaluation=MFO_CrateTracking.Evaluate(sample,{[9001]=1},snap,stamp)
equal(evaluation[1].status,"bank_stock","Syndicator stock can indicate bank withdrawal")
local texts={}
MFO_CrateTracking.AddTooltip({AddLine=function(_,line) texts[#texts+1]=line end},evaluation[1])
check(table.concat(texts,"|"):find("cached and may be outdated",1,true)~=nil,
 "Syndicator snapshot must never claim fabricated last-scan timestamp")
-- When no Syndicator item matches, retain a verified native snapshot.
P.ResetCache()
snap,stamp=P.BankSnapshot(native,{[102]=true,[9001]=true},70,"syndicator")
equal(snap[102],5,"valid native fallback remains usable for other items")
equal(stamp,70,"valid native timestamp retained when Syndicator has no item")

ready=false
P.ResetCache()
count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"not-ready Syndicator falls back")
equal(source,"native","not-ready source")
ready=true;pending=true
P.ResetCache()
count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"pending bag event falls back")
pending=false
local real=_G.Syndicator.API.GetInventoryInfoByItemID
_G.Syndicator.API.GetInventoryInfoByItemID=function() error("mock query failed") end
P.ResetCache()
count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"throwing API falls back")
_G.Syndicator.API.GetInventoryInfoByItemID=function() return {characters={{character="Alpha",realmNormalized="Forever",bank=0/0}}} end
P.ResetCache()
count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"invalid numeric bank falls back")
_G.Syndicator.API.GetInventoryInfoByItemID=real
_G.Syndicator.API.GetCurrentCharacter=function() return nil end
P.ResetCache()
count,source=P.BankCount(101,native,"syndicator")
equal(count,3,"unidentified current character falls back")
print("PASS: optional Syndicator current-character bank provider, native fallback and readiness")
