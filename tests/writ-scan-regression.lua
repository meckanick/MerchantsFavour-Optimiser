local addon="MerchantsFavourOptimiser/"
dofile(addon.."WritData.lua")
dofile(addon.."WritCalculations.lua")
dofile(addon.."WritRecipes.lua")
dofile(addon.."WritCrafting.lua")

local writIDs={}
for _,writ in ipairs(MFO_WritData) do
  writIDs[writ.id]=true
  for _,item in ipairs(writ.items) do writIDs[item.id]=true end
end
local shared=MFO_WritData[1].items[1].id
local missingID=MFO_WritData[1].id
local coldID=MFO_WritData[2].id
local crateID=1
local function name(id) return "Item "..id end
local crates={[crateID]=name(crateID),[shared]=name(shared)}
local function expected(includeCrates,includeWrits)
  local ids={}
  if includeCrates then for id in pairs(crates) do ids[id]=true end end
  if includeWrits then for id in pairs(writIDs) do ids[id]=true end end
  return ids
end

local function runScanner(modern)
  local handlers,queries={},{}
  local pending,ready,throttle
  local open,clock,now,realm,faction=true,0,10,"Forever","Alliance"
  MFO_DB={lastAHScan=5,prices={[shared]={price=99,updated=5},[missingID]={price=55,updated=5}}}
  function CreateFrame()
    return {
      RegisterEvent=function() end,
      SetScript=function(_,kind,fn)
        handlers[kind]=handlers[kind] or {}
        table.insert(handlers[kind],fn)
      end,
    }
  end
  function GetRealmName() return realm end
  function UnitFactionGroup() return faction end
  function GetTime() return clock end
  function time() return now end
  function GetItemInfo(id) if id~=coldID or ready then return name(id) end end
  AuctionFrame={IsShown=function() return open end}
  local function dispatch(id)
    assert(not pending,"overlapping auction queries")
    assert(not queries[id],"duplicate auction query for "..id)
    pending,queries[id]=id,true
  end
  function CanSendAuctionQuery() return not throttle end
  function QueryAuctionItems(itemName) dispatch(tonumber(itemName:match("%d+$"))) end
  function GetNumAuctionItems() return pending==missingID and 0 or 1,1 end
  function GetAuctionItemInfo() return name(pending),nil,1,nil,nil,nil,nil,nil,42 end
  C_AuctionHouse=modern and {
    IsThrottledMessageSystemReady=function() return not throttle end,
    GetItemKeyInfo=function(key) return key.itemID~=coldID or ready end,
    SendSearchQuery=function(key) dispatch(key.itemID) end,
    HasSearchResults=function() return true end,
    HasFullItemSearchResults=function() return true end,
    GetNumItemSearchResults=function(key) return key.itemID==missingID and 0 or 1 end,
    GetItemSearchResultInfo=function() return {buyoutAmount=42,quantity=1} end,
  } or nil
  dofile(addon.."StandaloneAH.lua")
  local ah=MFO_AH
  local function tick(elapsed)
    clock=clock+elapsed
    for _,handler in ipairs(handlers.OnUpdate) do handler(nil,elapsed) end
  end
  local function result()
    for _,handler in ipairs(handlers.OnEvent) do handler(nil,"ITEM_SEARCH_RESULTS_UPDATED",pending) end
    pending=nil
  end
  local function scan(mode,ids)
    queries={}
    assert(ah.Scan(crates,mode))
    assert(not ah.Scan(crates,mode),"second scan must be refused")
    for _=1,500 do
      if pending then result() end
      tick(.2)
      local percent,busy,_,total,complete=ah.Progress()
      if not busy then
        assert(percent==100 and complete)
        local count=0
        for id in pairs(ids) do
          count=count+1
          assert(queries[id],"expected query for "..id)
        end
        for id in pairs(queries) do assert(ids[id],"unexpected query for "..id) end
        assert(total==count)
        return
      end
    end
    error("scan did not finish")
  end

  assert(ah.LastScan()==5 and ah.Price(shared)==99)
  ready=true
  scan(nil,expected(true,false))
  assert(ah.LastScan()==10 and ah.LastScan("Writs")==nil and ah.LastScan("Full")==nil)
  now=20
  scan("Writs",expected(false,true))
  assert(ah.LastScan()==10 and ah.LastScan("Writs")==20 and ah.LastScan("Full")==nil)
  local lastPrice, unavailable=ah.PriceQuote(missingID,30,20)
  assert(lastPrice==55 and unavailable,"a new empty search must invalidate an otherwise fresh quote")
  assert(ah.Price(missingID)==55,"legacy ranking retains the last observed unit price")
  assert(#ah.Missing()==1 and ah.Missing()[1].id==missingID)
  local price,stale=ah.PriceQuote(shared,5,20)
  assert(price==42 and not stale,"Writ scan must refresh the shared cache")
  now=30
  scan("Full",expected(true,true))
  assert(ah.LastScan()==30 and ah.LastScan("Writs")==30 and ah.LastScan("Full")==30)

  MFO_DB.writCrafting=true
  local withReagents=expected(false,true)
  local visited={}
  for _,writ in ipairs(MFO_WritData) do
    for _,item in ipairs(writ.items) do
      MFO_WritCrafting.AddScanMaterials(item.id,function(id) withReagents[id]=true end,visited)
    end
  end
  assert(withReagents[2775] and not writIDs[2775],"include a recursive reagent")
  scan("Writs",withReagents)
  scan("Crates",expected(true,false))
  MFO_DB.writCrafting=false

  now=40
  queries={}
  ready=false
  assert(ah.Scan(crates,"Writs") and not pending,"cold item should wait for its data")
  tick(.1)
  assert(not pending,"polling must remain throttled")
  ready=true
  tick(.2)
  assert(pending==coldID)
  result()
  tick(.2)
  assert(pending)
  open=false
  result()
  tick(.2)
  local _,busy,priced,_,complete=ah.Progress()
  assert(not busy and not complete and priced==1 and ah.Status():find("cancelled"))
  assert(ah.LastScan()==30 and ah.LastScan("Writs")==30 and ah.LastScan("Full")==30)
  local partialPrice,partialStale=ah.PriceQuote(coldID,0,40)
  assert(partialPrice==42 and not partialStale,"completed item prices should survive interruption")

  queries={}
  open=true
  throttle=true
  assert(ah.Scan(crates,"Full"))
  assert(not pending,"throttle must block the query")
  throttle=false
  tick(.2)
  assert(pending)
  faction="Horde"
  result()
  tick(.2)
  assert(ah.LastScan("Full")==nil and ah.Price(shared)==nil)
  assert(ah.Status():find("market changed"))
  faction="Alliance"
  realm="Other"
  assert(ah.LastScan("Writs")==nil and ah.Price(shared)==nil)
  realm="Forever"
  assert(ah.LastScan("Full")==30 and ah.Price(shared)==42)

  queries={}
  assert(ah.Scan(crates,"Full"))
  tick(16)
  assert(ah.Status():find("timed out") and ah.LastScan("Full")==30)
  if modern then
    pending=nil
    throttle=true
    assert(ah.Scan(crates,"Full"))
    tick(16)
    assert(ah.Status():find("throttle timed out") and ah.LastScan("Full")==30)
  end
end

runScanner(false)
runScanner(true)

local function runBrowseScanner()
  local frames,keys,results={},{},{}
  local full,open,throttle=true,true,true
  local clock,now,pages,searches=0,10,0,0
  local pendingID
  local function result(id,price)
    return {itemKey={itemID=id},minPrice=price}
  end
  local function emit(event,...)
    for _,frame in ipairs(frames) do
      if frame[event] then frame.OnEvent(frame,event,...) end
    end
  end
  local function tick(elapsed)
    elapsed=elapsed or .2
    clock=clock+elapsed
    for _,frame in ipairs(frames) do
      if frame.OnUpdate then frame:OnUpdate(elapsed) end
    end
  end
  function CreateFrame()
    local frame={
      RegisterEvent=function(self,event) self[event]=true end,
      SetScript=function(self,script,fn) self[script]=fn end,
    }
    frames[#frames+1]=frame
    return frame
  end
  function hooksecurefunc(target,name,hook)
    local original=target[name]
    target[name]=function(...)
      original(...)
      hook(...)
    end
  end
  function GetTime() return clock end
  function time() return now end
  AuctionFrame={IsShown=function() return open end}
  MFO_DB={lastAHScan=5,prices={[2]={price=55,updated=5}}}
  C_AuctionHouse={
    SearchForItemKeys=function(batch)
      assert(not throttle and #batch<=50)
      keys[#keys+1]=batch
      results={}
      for _,key in ipairs(batch) do
        if key.itemID~=2 then results[#results+1]=result(key.itemID,42) end
      end
      full=#keys~=1
      emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end,
    HasFullBrowseResults=function() return full end,
    GetBrowseResults=function() return results end,
    RequestMoreBrowseResults=function()
      assert(not throttle)
      pages=pages+1
      results[#results+1]=result(1,23)
      full=true
      emit("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
    end,
    IsThrottledMessageSystemReady=function() return not throttle end,
    SendBrowseQuery=function()
      results={};full=true
      emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end,
    SendSearchQuery=function(key)
      searches=searches+1
      pendingID=key.itemID
    end,
    HasSearchResults=function() return true end,
    HasFullItemSearchResults=function() return true end,
    GetNumItemSearchResults=function() return 1 end,
    GetItemSearchResultInfo=function() return {buyoutAmount=81,quantity=2} end,
  }
  dofile(addon.."StandaloneAH.lua")
  local ah=MFO_AH
  local items={}
  for id=1,54 do items[id]=name(id) end
  assert(ah.Scan(items,"Crates"))
  assert(#keys==0,"throttle must block the initial batch")
  throttle=false
  tick()
  assert(#keys==1 and #keys[1]==50 and ah.Price(1)==nil)
  throttle=true
  tick()
  assert(pages==0 and ah.LastScan()==5,"partial browse results must wait for pagination")
  throttle=false
  tick()
  assert(pages==1)
  tick()
  local _,busy,priced,total,complete=ah.Progress()
  assert(busy and priced==49 and total==54 and not complete)
  assert(ah.Price(1)==23 and ah.LastScan()==5,"a later page can carry a lower unit price")
  tick()
  tick()
  local percent
  percent,busy,priced,total,complete=ah.Progress()
  assert(percent==100 and not busy and priced==53 and total==54 and complete)
  assert(#keys==2 and #keys[2]==4 and searches==0,"54 items should use two batches")
  local oldPrice,unavailable=ah.PriceQuote(2,10,now)
  assert(oldPrice==55 and unavailable and #ah.Missing()==1 and ah.LastScan()==now)

  now=20
  local oneItem={[1]=name(1)}
  assert(ah.Scan(oneItem,"Crates"))
  C_AuctionHouse.SendBrowseQuery()
  tick()
  assert(ah.LastScan()==10 and ah.Price(1)==23 and ah.Status():find("search changed"))

  assert(ah.Scan(oneItem,"Crates"))
  open=false
  tick()
  assert(ah.LastScan()==10 and ah.Price(1)==23 and ah.Status():find("AH closed"))
  open=true

  assert(ah.Scan(oneItem,"Crates"))
  emit("AUCTION_HOUSE_BROWSE_FAILURE")
  tick()
  tick()
  assert(searches==1 and pendingID==1,"browse failure must fall back to per-item search")
  emit("ITEM_SEARCH_RESULTS_UPDATED",{itemID=pendingID})
  tick()
  assert(ah.LastScan()==20 and ah.Price(1)==41)
end

runBrowseScanner()
print("PASS: legacy and modern scan modes, deduplication, missing prices, cancellation, and batched browse scans")
