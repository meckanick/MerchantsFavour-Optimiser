-- Standalone Auction House price storage and queued legacy AH scanner.
-- WoW Forever uses a Classic-derived client; all optional auction APIs are guarded.
MFO_AH = {}
local AH=MFO_AH
local queue,position,busy,waiting,started={},1,false,false,0
local function db()
  MFO_DB=MFO_DB or {}
  MFO_DB.prices=MFO_DB.prices or {}
  MFO_DB.shopping=MFO_DB.shopping or {}
  return MFO_DB
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
function AH.Status()
  if busy then return "Scanning "..math.min(position,#queue).."/"..#queue end
  return AH.message or "Ready"
end
local function auctionOpen()
  return (AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown()) or
    (AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown())
end
local function nextQuery()
  if not busy or waiting then return end
  if position>#queue then
    busy=false
    db().lastAHScan=time()
    AH.message="AH scan complete: "..#queue.." items checked"
    if AH.onUpdate then AH.onUpdate() end
    return
  end
  if type(CanSendAuctionQuery)=="function" then
    local ok,can=pcall(CanSendAuctionQuery)
    if not ok or not can then return end
  end
  local entry=queue[position]
  if not entry then busy=false;return end
  local ok=pcall(QueryAuctionItems,entry.name,nil,nil,0,0,0,0,0,nil,false)
  if not ok then busy=false;AH.message="AH query failed; scan not saved";return end
  waiting=true
  started=GetTime and GetTime() or 0
end
function AH.Scan(items)
  if busy then return false,"Scan already running" end
  if not auctionOpen() then return false,"Open the Auction House first" end
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
  position=1;busy=true;waiting=false
  AH.message="Scanning "..#queue.." items"
  nextQuery()
  return true,AH.message
end
local events=CreateFrame("Frame")
events:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
events:SetScript("OnEvent",function()
  if not busy or not waiting then return end
  local entry=queue[position]
  if not entry then return end
  local ok,count=pcall(GetNumAuctionItems,"list")
  if not ok or type(count)~="number" then
    busy=false;waiting=false;AH.message="Scan stopped: auction results unavailable";return
  end
  local lowest=nil
  for i=1,count do
    local good,name,texture,stack,quality,usable,level,minBid,minIncrement,buyout=pcall(GetAuctionItemInfo,"list",i)
    if good and name==entry.name and type(stack)=="number" and stack>0 and
      type(buyout)=="number" and buyout>0 then
      local unit=math.ceil(buyout/stack)
      if not lowest or unit<lowest then lowest=unit end
    end
  end
  if lowest then db().prices[entry.id]={price=lowest,updated=time()} end
  waiting=false;position=position+1
  if AH.onUpdate then AH.onUpdate() end
end)
events:SetScript("OnUpdate",function(_,elapsed)
  if not busy then return end
  if waiting then
    if GetTime and GetTime()-started>15 then
      busy=false;waiting=false;AH.message="Scan timed out; completion time unchanged"
    end
  else
    nextQuery()
  end
end)
