-- Standalone Auction House price storage and queued legacy AH scanner.
-- WoW Forever uses a Classic-derived client; all optional auction APIs are guarded.
MFO_AH = {}
local AH=MFO_AH
local queue,position,busy,waiting,started,page,lowest={},1,false,false,0,0,nil
local priced,attempts,scanTotal=0,0,0
local missing={}
local function recordMissing(entry)
  if entry then missing[#missing+1]={id=entry.id,name=entry.name} end
end
function AH.Missing() return missing end
-- Market-scoped prices and shopping lists; settings and character-owned inventory stay account-wide.
local function marketIdentity()
  local realm=(type(GetRealmName)=="function" and GetRealmName()) or
    (type(GetNormalizedRealmName)=="function" and GetNormalizedRealmName()) or "Unknown"
  local faction=(type(UnitFactionGroup)=="function" and UnitFactionGroup("player")) or "Unknown"
  realm=tostring(realm):gsub("^%s+",""):gsub("%s+$","")
  faction=tostring(faction)
  return realm,faction
end
function AH.Market()
  local realm,faction=marketIdentity()
  return realm.." - "..faction
end
local function db()
  MFO_DB=MFO_DB or {}
  local root=MFO_DB
  root.markets=root.markets or {}
  local realm,faction=marketIdentity()
  -- Use two levels so punctuation in realm names cannot collide with faction names.
  root.markets[realm]=root.markets[realm] or {}
  local market=root.markets[realm][faction]
  if not market then
    market={prices={},shopping={}}
    root.markets[realm][faction]=market
  end
  market.prices=market.prices or {}
  market.shopping=market.shopping or {}
  -- Legacy account-wide prices have no reliable realm/faction provenance.
  -- Keep a recoverable backup and import into the first active market only.\n  -- The original market is unknowable, so users should rescan on that market.
  if not root.legacyMarketArchived and
      (root.prices~=nil or root.shopping~=nil or root.lastAHScan~=nil) then
    root.legacyMarketArchived=true
    root.legacyAHData={
      prices=root.prices,shopping=root.shopping,lastAHScan=root.lastAHScan
    }
    market.prices=root.prices or {}\n    market.shopping=root.shopping or {}\n    market.lastAHScan=root.lastAHScan\n    root.legacyMarketImportedTo=realm.." - "..faction\n    root.prices=nil;root.shopping=nil;root.lastAHScan=nil
  end
  return market
end
function AH.Price(id)
  local record=db().prices[id]
  return record and record.price or nil
end
function AH.LastScan()
  return db().lastAHScan
end
function AH.Shop(items)
  local shopping=db().shopping
  for id,entry in pairs(items) do
    if type(id)=="number" and type(entry)=="table" and (entry.qty or 0)>0 then
      shopping[id]={name=entry.name or tostring(id),qty=math.floor(entry.qty)}
    end
  end
  return true
end
function AH.Shopping()
  return db().shopping
end
function AH.ClearShopping()
  db().shopping={}
end
function AH.Progress()
  return math.floor(math.min(100,(position-1)/math.max(1,scanTotal)*100)),busy,priced,scanTotal
end
function AH.Status()
  if busy then return "Scanning "..math.min(position,#queue).."/"..#queue end
  return AH.message or "Ready"
end
local function auctionOpen()
  return (AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown()) or
    (AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown())
end
local function nextQuery()
  if modern then return end
  if not busy or waiting then return end
  if position>#queue then
    busy=false
    db().lastAHScan=time()
    AH.message="AH scan complete: "..priced.."/"..#queue.." prices found"
    if AH.onUpdate then AH.onUpdate() end
    return
  end
  if type(CanSendAuctionQuery)=="function" then
    local ok,can=pcall(CanSendAuctionQuery)
    if not ok or not can then return end
  end
  local entry=queue[position]
  if not entry then busy=false;return end
  local ok=pcall(QueryAuctionItems,entry.name,nil,nil,page,0,0,0,0,nil,false)
  if not ok then busy=false;AH.message="AH query failed; scan not saved";return end
  waiting=true
  started=GetTime and GetTime() or 0
end
function AH.Scan(items)
  if busy then return false,"Scan already running" end
  if not auctionOpen() then return false,"Open the Auction House first" end
  if not eventOK then return false,"Auction list update event unavailable" end
  if type(QueryAuctionItems)~="function" or type(GetAuctionItemInfo)~="function" or
    type(GetNumAuctionItems)~="function" then
    return false,"Legacy Auction House query API unavailable in this client"
  end
  queue={}
  local seen={}
  for id,name in pairs(items) do
    if type(id)=="number" and type(name)=="string" and name~="" and not seen[id] then
      queue[#queue+1]={id=id,name=name}
      seen[id]=true
    end
  end
  table.sort(queue,function(a,b)return a.name<b.name end)
  if #queue==0 then return false,"No resolved items to scan" end
  position=1;page=0;lowest=nil;busy=true;waiting=false;priced=0;scanTotal=#queue;missing={}
  AH.message="Scanning "..#queue.." items"
  nextQuery()
  return true,AH.message
end
-- WoW Forever uses the modern C_AuctionHouse API, unlike legacy Classic.
local modern = C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery)=="function"
local function modernNext()
  if not busy or waiting then return end
  if position>#queue then
    busy=false;db().lastAHScan=time()
    AH.message="AH scan complete: "..priced.."/"..#queue.." priced"
    if AH.onUpdate then AH.onUpdate() end
    return
  end
  local entry=queue[position]
  local key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(entry.id) or {itemID=entry.id}
  if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(key) then
    if type(GetItemInfo)=="function" then GetItemInfo(entry.id) end
    return
  end
  local ok=pcall(C_AuctionHouse.SendSearchQuery,key,{},false)
  if not ok then busy=false;AH.message="Modern AH query failed";return end
  waiting=true;started=GetTime and GetTime() or 0
end
local modernEvents=CreateFrame("Frame")
local modernOK=pcall(modernEvents.RegisterEvent,modernEvents,"ITEM_SEARCH_RESULTS_UPDATED")
local commodityOK=pcall(modernEvents.RegisterEvent,modernEvents,"COMMODITY_SEARCH_RESULTS_UPDATED")
modernEvents:SetScript("OnEvent",function(_,event,arg)
  if not busy or not waiting or not modern then return end
  local entry=queue[position]
  local id=type(arg)=="table" and arg.itemID or arg
  if id~=entry.id then return end
  local key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(entry.id) or {itemID=entry.id}
  local price=nil
  local isCommodity=event=="COMMODITY_SEARCH_RESULTS_UPDATED"
  local has=C_AuctionHouse.HasSearchResults and C_AuctionHouse.HasSearchResults(key)
  local full=isCommodity and C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(entry.id)
    or (not isCommodity and C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.HasFullItemSearchResults(key))
  local count=0
  if isCommodity and C_AuctionHouse.GetCommoditySearchResultsQuantity then
    count=C_AuctionHouse.GetCommoditySearchResultsQuantity(entry.id) or 0
  elseif not isCommodity and C_AuctionHouse.GetItemSearchResultsQuantity then
    count=C_AuctionHouse.GetItemSearchResultsQuantity(key) or 0
  end
  if (not has or (not full and count==0)) and attempts<2 then
    waiting=false;attempts=attempts+1
    if AH.onUpdate then AH.onUpdate() end
    return
  end
  if isCommodity and C_AuctionHouse.GetCommoditySearchResultInfo then
    for i=1,(C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetNumCommoditySearchResults(entry.id) or 0) do
      local item=C_AuctionHouse.GetCommoditySearchResultInfo(entry.id,i)
      local p=item and item.unitPrice
      if type(p)=="number" and p>0 and (not price or p<price) then price=p end
    end
  elseif not isCommodity and C_AuctionHouse.GetItemSearchResultInfo then
    for i=1,(C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(key) or 0) do
      local item=C_AuctionHouse.GetItemSearchResultInfo(key,i)
      local p=item and item.buyoutAmount
      if type(p)=="number" and p>0 then
        p=math.ceil(p/math.max(1,item.quantity or 1))
        if not price or p<price then price=p end
      end
    end
  end
  if price then
    db().prices[entry.id]={price=price,updated=time()}
    priced=priced+1
  else
    recordMissing(entry)
  end
  attempts=0
  waiting=false;position=position+1
  if AH.onUpdate then AH.onUpdate() end
end)
local legacyScan=AH.Scan
AH.Scan=function(items)
  if not modern then return legacyScan(items) end
  if busy then return false,"Scan already running" end
  if not auctionOpen() then return false,"Open the Auction House first" end
  if not modernOK and not commodityOK then return false,"Modern AH result events unavailable" end
  queue={}
  for id,name in pairs(items) do
    if type(id)=="number" and type(name)=="string" then queue[#queue+1]={id=id,name=name} end
  end
  table.sort(queue,function(a,b)return a.name<b.name end)
  if #queue==0 then return false,"No resolved items to scan" end
  position=1;busy=true;waiting=false;priced=0;scanTotal=#queue;attempts=0;missing={}
  AH.message="Scanning "..#queue.." items"
  modernNext()
  return true,AH.message
end
local events=CreateFrame("Frame")
local eventOK=pcall(events.RegisterEvent,events,"AUCTION_ITEM_LIST_UPDATE")
if not eventOK then
  AH.message="AH scan event unavailable in this client"
end
events:SetScript("OnEvent",function()
  if not busy or not waiting then return end
  local entry=queue[position]
  if not entry then return end
  local ok,count,total=pcall(GetNumAuctionItems,"list")
  if not ok or type(count)~="number" then
    busy=false;waiting=false;AH.message="Scan stopped: auction results unavailable";return
  end
  for i=1,count do
    local good,name,texture,stack,quality,usable,level,minBid,minIncrement,buyout=pcall(GetAuctionItemInfo,"list",i)
    if good and name==entry.name and type(stack)=="number" and stack>0 and
      type(buyout)=="number" and buyout>0 then
      local unit=math.ceil(buyout/stack)
      if not lowest or unit<lowest then lowest=unit end
    end
  end
  waiting=false
  if type(total)=="number" and (page+1)*50<total then
    page=page+1
  else
    if lowest then db().prices[entry.id]={price=lowest,updated=time()};priced=priced+1
    else recordMissing(entry) end
    position=position+1;page=0;lowest=nil
  end
  if AH.onUpdate then AH.onUpdate() end
end)
events:SetScript("OnUpdate",function(_,elapsed)
  if not busy then return end
  if modern and not waiting then modernNext();return end
  if waiting then
    if GetTime and GetTime()-started>15 then
      busy=false;waiting=false;AH.message="Scan timed out; completion time unchanged"
    end
  else
    nextQuery()
  end
end)
