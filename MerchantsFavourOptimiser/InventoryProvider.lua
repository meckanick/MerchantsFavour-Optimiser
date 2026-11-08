-- MFO v0.1.179: optional, read-only Syndicator bank counts.
-- Validated against the public API shipped by Syndicator 288 (Forever 16001).
-- Never count other characters, mail, auctions, guilds or warband storage as owned.
MFO_InventoryProvider = {}
local P = MFO_InventoryProvider
local cached,cacheSecond={},nil
local function valid(n)
 return type(n)=="number" and n==n and n>=0 and n<math.huge
   and n==math.floor(n) and n<=2147483647
end
local function verified(stamp)
 return type(stamp)=="number" and stamp==stamp and stamp>0 and stamp<math.huge
end
function P.Mode(settings)
 return settings and settings.inventorySource=="syndicator" and "syndicator" or "native"
end
function P.ResetCache()
 for id in pairs(cached) do cached[id]=nil end
 cacheSecond=nil
end
local function apiReady()
 local s=_G and _G.Syndicator
 local api=s and s.API
 if type(api)~="table" or type(api.IsReady)~="function"
   or type(api.GetCurrentCharacter)~="function"
   or type(api.GetInventoryInfoByItemID)~="function" then return nil end
 local ok,ready=pcall(api.IsReady)
 if not ok or ready~=true then return nil end
 if type(api.IsBagEventPending)=="function" then
  local pendingOK,pending=pcall(api.IsBagEventPending)
  if not pendingOK or pending then return nil end
 end
 local currentOK,current=pcall(api.GetCurrentCharacter)
 if not currentOK or type(current)~="string" or current=="" then return nil end
 return api,current
end
function P.IsAvailable()
 return apiReady()~=nil
end
function P.SyndicatorBank(itemID)
 if not valid(itemID) or itemID==0 then return nil end
 -- Limit the cache to one second; do not return stale data after a new AH or bag event.
 local second=type(time)=="function" and time() or nil
 if second~=cacheSecond then P.ResetCache();cacheSecond=second end
 if cached[itemID]~=nil then
  return cached[itemID].found and cached[itemID].count or nil
 end
 local api,current=apiReady()
 if not api then return nil end
 local ok,info=pcall(api.GetInventoryInfoByItemID,itemID)
 if not ok or type(info)~="table" or type(info.characters)~="table" then return nil end
 for _,entry in ipairs(info.characters) do
  if type(entry)=="table" and type(entry.character)=="string"
    and type(entry.realmNormalized)=="string" then
   local full=entry.character..(entry.realmNormalized~="" and "-"..entry.realmNormalized or "")
   if full==current then
    if not valid(entry.bank) then return nil end
    cached[itemID]={found=true,count=entry.bank}
    return entry.bank
   end
  end
 end
 -- Absent entries can also mean a hidden character or incomplete cache.
 -- Never interpret absence as a trusted zero; let MFO use its native snapshot.
 cached[itemID]={found=false}
 return nil
end
function P.BankCount(itemID,nativeBank,mode)
 if mode=="syndicator" then
  local external=P.SyndicatorBank(itemID)
  if external~=nil then return external,"syndicator" end
 end
 local count=type(nativeBank)=="table" and nativeBank[itemID] or nil
 return valid(count) and count or 0,"native"
end
function P.TotalCount(itemID,bags,nativeBank,mode)
 local bag=type(bags)=="table" and bags[itemID] or nil
 local bank,source=P.BankCount(itemID,nativeBank,mode)
 return (valid(bag) and bag or 0)+bank,source
end
function P.BankSnapshot(nativeBank,itemIDs,nativeStamp,mode)
 local result={}
 local stamp=verified(nativeStamp) and nativeStamp or nil
 -- Never accidentally bless an unverified native bank snapshot just because
 -- a different item was available from Syndicator.
 if stamp and type(nativeBank)=="table" then
  for id,n in pairs(nativeBank) do
   if valid(id) and valid(n) then result[id]=n end
  end
 end
 if mode=="syndicator" and type(itemIDs)=="table" then
  local fromSyndicator=false
  for id in pairs(itemIDs) do
   local n=P.SyndicatorBank(id)
   if n~=nil then result[id]=n;fromSyndicator=true end
  end
  if fromSyndicator then stamp="syndicator" end
 end
 return result,stamp
end
