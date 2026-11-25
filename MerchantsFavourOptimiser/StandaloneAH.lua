-- Standalone Auction House price storage and queued legacy AH scanner.
-- WoW Forever uses a Classic-derived client; all optional auction APIs are guarded.
MFO_AH = {}
local AH=MFO_AH
local queue,position,busy,waiting,started,page,lowest={},1,false,false,nil,0,nil
local priced,attempts,scanTotal=0,0,0
local missing={}
local scanMode,scanRealm,scanFaction,scanMarket,completed
-- Forward declarations ensure the legacy scanner sees the actual capability
-- flags rather than unrelated globals.
local modern,eventOK
local function recordMissing(entry)
  if entry then missing[#missing+1]={id=entry.id,name=entry.name or "Unknown item"} end
end
function AH.Missing() return missing end
local function getItemName(id)
  local read=GetItemInfo or (C_Item and C_Item.GetItemInfo)
  return read and read(id)
end
-- Market-scoped prices and shopping lists; settings and character-owned inventory stay account-wide.
local lastRawRealm,normalizedRealm
local function marketIdentity()
  local realm=(GetRealmName and GetRealmName()) or
    (GetNormalizedRealmName and GetNormalizedRealmName()) or "Unknown"
  local faction=(UnitFactionGroup and UnitFactionGroup("player")) or "Unknown"
  realm=tostring(realm)
  -- Realm names rarely change during a session. Avoid repeated string
  -- trimming during ranking, while still detecting a changed realm.
  if realm~=lastRawRealm then
    normalizedRealm=realm:gsub("^%s+",""):gsub("%s+$","")
    lastRawRealm=realm
  end
  faction=tostring(faction)
  return normalizedRealm,faction
end
function AH.Market()
  local realm,faction=marketIdentity()
  return realm.." - "..faction
end
local function db(realm,faction)
  if not MFO_DB then MFO_DB={} end
  local root=MFO_DB
  local markets=root.markets
  if not markets then
    markets={}
    root.markets=markets
  end
  if not realm or not faction then realm,faction=marketIdentity() end
  -- Use two levels so punctuation in realm names cannot collide with faction names.
  local realmMarkets=markets[realm]
  if not realmMarkets then
    realmMarkets={}
    markets[realm]=realmMarkets
  end
  local market=realmMarkets[faction]
  if not market then
    market={prices={},shopping={}}
    realmMarkets[faction]=market
  end
  if not market.prices then market.prices={} end
  if not market.shopping then market.shopping={} end
  -- Legacy account-wide prices have no reliable realm/faction provenance.
  -- Keep a recoverable backup and import into the first active market only.
  -- The original market is unknowable, so users should rescan on that market.
  if not root.legacyMarketArchived and
      (root.prices~=nil or root.shopping~=nil or root.lastAHScan~=nil) then
    root.legacyMarketArchived=true
    root.legacyAHData={
      prices=root.prices,shopping=root.shopping,lastAHScan=root.lastAHScan
    }
    market.prices=root.prices or {}
    market.shopping=root.shopping or {}
    market.lastAHScan=root.lastAHScan
    root.legacyMarketImportedTo=realm.." - "..faction
    root.prices=nil;root.shopping=nil;root.lastAHScan=nil
  end
  return market
end
-- Reuse the active market's price table across repeated ranking lookups.
-- Recheck realm/faction so switching characters cannot reuse another market.
local priceRealm,priceFaction,priceRecords
local function priceRecord(id)
  if not id then return nil end
  local realm,faction=marketIdentity()
  -- Compare the two market identifiers directly rather than allocating
  -- a combined realm/faction string on every item price lookup.
  if realm~=priceRealm or faction~=priceFaction or not priceRecords then
    -- The caller already resolved this identity; avoid querying the game
    -- APIs a second time on a market-cache miss.
    priceRecords=db(realm,faction).prices
    priceRealm,priceFaction=realm,faction
  end
  return priceRecords[id]
end
function AH.Price(id)
  local record=priceRecord(id)
  return record and record.price or nil
end
-- Writ estimates use the item's own scan time, including for legacy records.
function AH.PriceQuote(id,maxAge,now)
  local record=priceRecord(id)
  if not record or not record.price then return nil end
  local updated=record.updated
  local fresh=not record.unavailable and type(updated)=="number" and updated>0 and updated<=now and now-updated<=maxAge
  return record.price,not fresh
end
function AH.LastScan(mode)
  local market=db()
  if mode=="Writs" then return market.lastWritScan end
  if mode=="Full" then return market.lastFullScan end
  return market.lastAHScan
end
-- Full requirements are retained separately from the quantity left to purchase.
-- This prevents deducting the same owned stock twice on subsequent refreshes.
local ownedReader
local craftMarket, craftView, craftEstimate, craftOwner
function AH.ShoppingUsesWritStock()
  return db().shoppingWritIDs~=nil
end
local function shoppingOwned(id, writ)
  if AH.ShoppingItemStock and writ then
    local bags,bank=AH.ShoppingItemStock(id,true)
    return bags+bank
  end
  return ownedReader(id)
end
function AH.SetOwnedReader(reader)
  ownedReader=type(reader)=="function" and reader or nil
end
local function shoppingEntry(id,entry)
  if type(id)~="number" or type(entry)~="table" then return nil end
  local qty=tonumber(entry.qty)
  if not qty or qty<0 then return nil end
  qty=math.floor(qty)
  local required=tonumber(entry.requiredQty)
  required=required and math.floor(required) or qty
  if required<qty then required=qty end
  -- Keep fully-owned items only when their original demand is known.
  if required<1 then return nil end
  return {name=entry.name or tostring(id),qty=qty,requiredQty=required}
end
function AH.Shop(items)
  if type(items)~="table" then return false,"Invalid shopping items" end
  local shopping=db().shopping
  for id,entry in pairs(items) do
    local item=shoppingEntry(id,entry)
    if item then
      shopping[id]=item
      db().shoppingCratePlan=nil
      db().shoppingWritIDs=nil
      db().shoppingCraft=nil
      db().shoppingCraftPlan=nil
      craftMarket,craftView,craftEstimate=nil,nil,nil
    end
  end
  return true
end
local function writFaction()
  return UnitFactionGroup and UnitFactionGroup("player")
end

local function checkWritEligibility(ids)
  local states=MFO_WritTracking.Snapshot()
  for _,id in ipairs(ids) do
    local state=states[id]
    if not MFO_WritTracking.Eligible(state) then
      return false,state=="completed" and "Writ completed today." or "Writ eligibility is unknown."
    end
  end
  return true
end

-- Replace atomically; an invalid or empty request must not erase a valid list.
function AH.ReplaceShopping(items, writIDs, crafting)
  if type(items)~="table" then return false,"Invalid shopping items" end
  local replacement={}
  for id,entry in pairs(items) do
    local item=shoppingEntry(id,entry)
    if item then replacement[id]=item end
  end
  if not next(replacement) then return false,"No valid items to shop for" end
  local selection
  if writIDs and #writIDs>0 then
    local demand,reason=MFO_WritCalculations.selectionRequirements(writIDs,writFaction())
    if not demand then return false,reason end
    local eligible,why=checkWritEligibility(writIDs)
    if not eligible then return false,why end
    for id,qty in pairs(demand) do
      if not replacement[id] or replacement[id].requiredQty<qty then
        return false,"Incomplete Writ shopping requirements"
      end
    end
    selection={}
    for i,id in ipairs(writIDs) do selection[i]=id end
  end
  local market=db()
  market.shopping=replacement
  market.shoppingCratePlan=nil
  market.shoppingWritIDs=selection
  market.shoppingCraftPlan=crafting and true or nil
  market.shoppingCraft=nil
  craftMarket,craftView,craftEstimate=nil,nil,nil
  return true
end
-- Confirmed purchases are credited immediately, even before the bag update.
-- Once inventory reflects delivery, remove only the temporary stock credit.
function AH.RecordShoppingPurchase(id,qty)
  local market=db()
  local owner=market.shoppingCraft and MFO_WritTracking.CharacterKey()
  local saved=owner and market.shoppingCraft[owner]
  local item=market.shopping[id] or (saved and saved.materials[id])
  local crafting=saved and MFO_WritCrafting.Enabled() and craftMarket==market and craftView and craftOwner==owner
  qty=math.floor(tonumber(qty) or 0)
  if not item or not item.requiredQty or qty<1 then return false end
  item.purchasedQty=(item.purchasedQty or 0)+qty
  if ownedReader then
    if not item.pendingPurchaseQty or item.pendingPurchaseQty==0 then
      item.purchaseBagsOnly=crafting and AH.ShoppingItemStock and true or nil
      local observed=item.purchaseBagsOnly and AH.ShoppingItemStock(id,true)
        or shoppingOwned(id,market.shoppingWritIDs)
      item.purchaseBaseline=math.max(0,math.floor(tonumber(observed) or 0))
    end
    item.pendingPurchaseQty=(item.pendingPurchaseQty or 0)+qty
  end
  return true
end

local function refreshCraftShopping(market, owned)
  craftMarket,craftView,craftEstimate,craftOwner=market,nil,nil,nil
  if (not market.shoppingWritIDs and not market.shoppingCraftPlan)
    or not MFO_WritCrafting or not MFO_WritCrafting.Enabled() then return end
  local recipes=MFO_WritCrafting.Recipes()
  local owner=MFO_WritTracking.CharacterKey()
  if not owner then return end
  local saved=market.shoppingCraft and market.shoppingCraft[owner]
  if not recipes and not saved then return end
  market.shoppingCraft=market.shoppingCraft or {}
  saved=saved or {materials={},bagBaseline={},outputs={}}
  market.shoppingCraft[owner]=saved
  craftOwner=owner
  local demand, acquisitions, reserve={}, {}, {}
  for id, entry in pairs(market.shopping) do
    demand[id]=entry.requiredQty or entry.qty
    reserve[id]=entry.legacyStockReserve or (not entry.requiredQty and owned(id)) or 0
  end
  for _, id in ipairs(market.shoppingWritIDs or {}) do acquisitions[id]=1 end
  for _, entry in ipairs(market.shoppingCratePlan or {}) do
    acquisitions[entry.crateID]=(acquisitions[entry.crateID] or 0)+entry.quantity
  end
  local function available(id)
    local entry=market.shopping[id] or saved.materials[id] or {}
    local bags,bank=0,0
    if AH.ShoppingItemStock then bags,bank=AH.ShoppingItemStock(id,true) else bags=owned(id) end
    local baseline=saved.bagBaseline[id]
    if baseline==nil then
      baseline=math.max(0,bags-((entry.purchasedQty or 0)-(entry.pendingPurchaseQty or 0)))
    end
    baseline=math.min(baseline,bags)
    saved.bagBaseline[id]=baseline
    local pending=entry.pendingPurchaseQty or 0
    if MFO_DB.useOwned then
      local physical=bags+bank-(reserve[id] or 0)
      return math.max(0,physical+pending),math.max(0,physical)
    end
    local received=bags-baseline
    if not saved.outputs[id] then received=math.min(received,(entry.purchasedQty or 0)-pending) end
    return math.max(0,received)+pending,math.max(0,received)
  end
  local now=time()
  craftEstimate=MFO_WritCalculations.estimate(demand,acquisitions,0,
    function(id) return AH.PriceQuote(id,7*86400-1,now) end,available,recipes)
  if craftEstimate.procurement then
    for _, step in ipairs(craftEstimate.crafting.steps) do saved.outputs[step.id]=true end
  end
  craftView={}
  for id, qty in pairs(craftEstimate.procurement or demand) do
    local record=market.shopping[id] or saved.materials[id]
    if not record then
      record={}
      saved.materials[id]=record
    end
    if not market.shopping[id] then
      record.requiredQty=qty
      record.name=getItemName(id) or record.name or ("Item #"..id)
    end
    local remaining=craftEstimate.shopping[id] or 0
    local _,physical=available(id)
    local entry={name=record.name,qty=remaining,requiredQty=qty,availableQty=math.min(qty-remaining,physical),
      legacyStockReserve=reserve[id], pendingPurchaseQty=record.pendingPurchaseQty, purchasedQty=record.purchasedQty}
    craftView[id]=entry
  end
end
-- Recompute from original demand, never from an already reduced purchase qty.
-- Old lists without requiredQty retain their current quantities as baseline.
function AH.RecalculateShopping()
  local market=db()
  if not ownedReader then return false end
  local function owned(id)
    return math.max(0,math.floor(tonumber(shoppingOwned(id,market.shoppingWritIDs)) or 0))
  end
  local function recalculate(shopping)
    for id,item in pairs(shopping) do
      -- Legacy lists may already contain net quantities; their original
      -- requirements are unknown, so never subtract inventory again.
      if item.requiredQty then
        local required=math.max(0,math.floor(tonumber(item.requiredQty) or 0))
        local useOwned=MFO_DB and MFO_DB.useOwned
        local physical=owned(id)
        local pending=item.pendingPurchaseQty or 0
        if pending>0 then
          local observed=item.purchaseBagsOnly and AH.ShoppingItemStock and AH.ShoppingItemStock(id,true) or physical
          local baseline=math.min(observed,item.purchaseBaseline or 0)
          -- Lower the baseline when stock is used between partial deliveries.
          local received=math.min(pending,observed-baseline)
          pending=pending-received
          item.pendingPurchaseQty=pending
          item.purchaseBaseline=pending>0 and observed or nil
          if pending==0 then item.purchaseBagsOnly=nil end
        end
        if useOwned then
          item.qty=math.max(0,required-math.max(0,physical+pending-(item.legacyStockReserve or 0)))
        else
          -- Owned stock is intentionally ignored, but purchases made from
          -- this list must still reduce the outstanding shopping quantity.
          item.qty=math.max(0,required-(item.purchasedQty or 0))
        end
      end
    end
  end
  recalculate(market.shopping)
  local saved=market.shoppingCraft and market.shoppingCraft[MFO_WritTracking.CharacterKey()]
  if saved then recalculate(saved.materials) end
  refreshCraftShopping(market,owned)
  return true
end
function AH.AddShoppingWrits(ids, itemName)
  local market=db()
  local selection, added={},{}
  for _,id in ipairs(market.shoppingWritIDs or {}) do
    selection[#selection+1]=id
    added[id]=true
  end
  local newIDs={}
  for _,id in ipairs(ids) do
    if type(id)~="number" or id~=id then return false,"Unknown Writ" end
    if not added[id] then
      selection[#selection+1]=id
      newIDs[#newIDs+1]=id
      added[id]=true
    end
  end
  if #newIDs==0 then return false,"Selected Writs are already on the shopping list." end
  local requirements,reason=MFO_WritCalculations.selectionRequirements(newIDs,writFaction())
  if not requirements then return false,reason end
  local eligible,why=checkWritEligibility(newIDs)
  if not eligible then return false,why end

  for id,qty in pairs(requirements) do
    local entry=market.shopping[id]
    if entry then
      if not entry.requiredQty then
        -- Legacy rows store net demand. Reserve stock already implied by that demand.
        entry.legacyNetQty=entry.qty
        entry.legacyStockBaseline=ownedReader and tonumber(shoppingOwned(id,true)) or 0
      end
      entry.requiredQty=(entry.requiredQty or entry.qty)+qty
      if entry.legacyNetQty then
        entry.legacyStockReserve=math.max(0,entry.legacyStockBaseline-(entry.requiredQty-entry.legacyNetQty))
      end
      entry.qty=entry.qty+qty
    else
      local saved=market.shoppingCraft and market.shoppingCraft[MFO_WritTracking.CharacterKey()]
      local material=saved and saved.materials[id]
      if material then saved.materials[id]=nil end
      entry=material or {name=itemName(id) or ("Item #"..id)}
      entry.qty,entry.requiredQty=qty,qty
      market.shopping[id]=entry
    end
  end
  market.shoppingWritIDs=selection
  AH.RecalculateShopping()
  return true
end

-- Crates retain their existing allocation priority. Use the remaining physical
-- stock once across the selected Writs, in the order they were added.
function AH.ShoppingWritReadiness(crateAllocations)
  local output={}
  local ids=db().shoppingWritIDs
  if not ids or not AH.ShoppingItemStock then return output end
  local _,_,_,writs=MFO_WritCalculations.selectionRequirements(ids,writFaction())
  if not writs then return output end
  local states=MFO_WritTracking.Snapshot()
  local bags,bank={},{}
  local function loadStock(id)
    if bags[id]==nil then
      local inBags,inBank,stamp,source=AH.ShoppingItemStock(id,true)
      bags[id]=inBags
      bank[id]=(source=="syndicator" or (stamp and stamp>0)) and inBank or 0
    end
  end
  local function take(id,qty)
    loadStock(id)
    local bagUsed=math.min(qty,bags[id])
    local bankUsed=math.min(qty-bagUsed,bank[id])
    bags[id]=bags[id]-bagUsed
    bank[id]=bank[id]-bankUsed
    return bagUsed,bankUsed
  end
  for _,allocation in ipairs(crateAllocations or {}) do
    for _,stock in ipairs({
      {allocation.crateID,allocation.crateInBags,allocation.crateInBank},
      {allocation.materialID,allocation.materialsInBags,allocation.materialsInBank},
    }) do
      loadStock(stock[1])
      bags[stock[1]]=math.max(0,bags[stock[1]]-stock[2])
      bank[stock[1]]=math.max(0,bank[stock[1]]-stock[3])
    end
  end
  for _,writ in ipairs(writs) do
    local state=states[writ.id]
    local record={state=state}
    if MFO_WritTracking.Eligible(state) then
      local bagWrit,bankWrit=take(writ.id,1)
      record.missing,record.withdraw=1-bagWrit-bankWrit,bankWrit
      for _,item in ipairs(writ.items) do
        local bagUsed,bankUsed=take(item.id,item.qty)
        record.missing=record.missing+item.qty-bagUsed-bankUsed
        record.withdraw=record.withdraw+bankUsed
      end
    end
    record.ready=state=="objectives_complete" and record.missing==0 and record.withdraw==0
    output[writ.id]=record
  end
  return output
end

function AH.SetShoppingCratePlan(entries)
  local copy={}
  for _,entry in ipairs(entries or {}) do
    if type(entry)=="table" then
      local id,material=tonumber(entry.crateID),tonumber(entry.materialID)
      local qty,per=tonumber(entry.quantity),tonumber(entry.materialQty)
      if id and id>0 and id<math.huge and id==math.floor(id)
         and material and material>0 and material<math.huge
         and material==math.floor(material) and material~=id
         and qty and qty>=1 and qty<math.huge and qty==math.floor(qty)
         and per and per>=1 and per<math.huge and per==math.floor(per) then
        copy[#copy+1]={crateID=id,materialID=material,quantity=qty,materialQty=per}
      end
    end
  end
  db().shoppingCratePlan=#copy>0 and copy or nil
  return #copy>0
end
function AH.ShoppingCratePlan()
  return db().shoppingCratePlan
end
function AH.Shopping()
  local market=db()
  return MFO_WritCrafting and MFO_WritCrafting.Enabled() and craftMarket==market and craftView
    and craftOwner==MFO_WritTracking.CharacterKey() and craftView or market.shopping
end
function AH.ShoppingCraftEstimate()
  if MFO_WritCrafting and MFO_WritCrafting.Enabled() and craftMarket==db()
    and craftOwner==MFO_WritTracking.CharacterKey() then return craftEstimate end
end
function AH.RemoveShoppingItem(id)
  if type(id)~="number" or not AH.Shopping()[id] then return false end
  local market=db()
  local ingredients={}
  local estimate=AH.ShoppingCraftEstimate()
  local optimised=estimate and estimate.procurement
  if optimised then
    for _, step in ipairs(estimate.crafting.steps) do ingredients[step.id]=step.recipe.reagents end
  end
  local function requires(itemID)
    if itemID==id then return true end
    for reagent in pairs(ingredients[itemID] or {}) do
      if requires(reagent) then return true end
    end
    return false
  end
  local function subtract(itemID,qty)
    local entry=market.shopping[itemID]
    if entry and entry.requiredQty then
      entry.requiredQty=entry.requiredQty-qty
      entry.qty=math.max(0,entry.qty-qty)
      if entry.legacyNetQty then
        entry.legacyStockReserve=math.max(0,entry.legacyStockBaseline-(entry.requiredQty-entry.legacyNetQty))
      end
      if entry.requiredQty<=0 then market.shopping[itemID]=nil end
    end
  end
  market.shopping[id]=nil
  local crates={}
  for _,entry in ipairs(market.shoppingCratePlan or {}) do
    if requires(entry.crateID) or requires(entry.materialID) then
      if optimised or market.shoppingWritIDs then
        subtract(entry.crateID,entry.quantity)
        subtract(entry.materialID,entry.quantity*entry.materialQty)
      else
        crates={}
        break
      end
    else
      crates[#crates+1]=entry
    end
  end
  market.shoppingCratePlan=#crates>0 and crates or nil
  if not market.shoppingCratePlan then market.shoppingCraftPlan=nil end
  if market.shoppingWritIDs then
    local _,_,_,writs=MFO_WritCalculations.selectionRequirements(market.shoppingWritIDs,writFaction())
    local remaining,removed={},{}
    for _,writ in ipairs(writs or {}) do
      local affected=requires(writ.id)
      for _,item in ipairs(writ.items) do
        if requires(item.id) then affected=true;break end
      end
      local list=affected and removed or remaining
      list[#list+1]=writ.id
    end
    local requirements=MFO_WritCalculations.selectionRequirements(removed,writFaction())
    for itemID,qty in pairs(requirements or {}) do subtract(itemID,qty) end
    market.shoppingWritIDs=#remaining>0 and remaining or nil
  end
  AH.RecalculateShopping()
  return true
end
function AH.ClearShopping()
  db().shopping={}
  db().shoppingCratePlan=nil
  db().shoppingWritIDs=nil
  db().shoppingCraft=nil
  db().shoppingCraftPlan=nil
  craftMarket,craftView,craftEstimate=nil,nil,nil
end
function AH.Progress()
  return math.floor(math.min(100,(position-1)/math.max(1,scanTotal)*100)),busy,priced,scanTotal,completed
end
function AH.Status()
  if busy then return "Scanning "..math.min(position,#queue).."/"..#queue end
  return AH.message or "Ready"
end
local function auctionOpen()
  return (AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown()) or
    (AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown())
end
local function stopScan(message)
  busy=false;waiting=false
  AH.message=message
  if AH.onUpdate then AH.onUpdate() end
end
local function scanMarketMatches()
  local realm,faction=marketIdentity()
  return realm==scanRealm and faction==scanFaction
end
local function recordUnpriced(entry)
  local record=scanMarket.prices[entry.id]
  if record then record.unavailable=true end
  recordMissing(entry)
end
local function finishScan()
  completed=true
  local now=time()
  if scanMode~="Writs" then scanMarket.lastAHScan=now end
  if scanMode~="Crates" then scanMarket.lastWritScan=now end
  if scanMode=="Full" then scanMarket.lastFullScan=now end
  stopScan("AH scan complete: "..priced.."/"..#queue.." priced")
end
local function waitForItem(entry)
  local now=GetTime and GetTime() or 0
  started=started or now
  if now-started<=15 then return true end
  recordMissing(entry)
  position=position+1
  started=nil
  return false
end
local function nextQuery()
  if modern then return end
  if not busy or waiting then return end
  if position>#queue then
    finishScan()
    return
  end
  local entry=queue[position]
  if not entry.name then
    entry.name=getItemName(entry.id)
    if not entry.name then waitForItem(entry);return end
  end
  if type(CanSendAuctionQuery)=="function" then
    local ok,can=pcall(CanSendAuctionQuery)
    if not ok or not can then return end
  end
  local ok=pcall(QueryAuctionItems,entry.name,nil,nil,page,0,0,0,0,nil,false)
  if not ok then stopScan("AH query failed; scan not saved");return end
  waiting=true
  started=GetTime and GetTime() or 0
end
local function prepareScan(items,mode)
  local realm,faction=marketIdentity()
  local names={}
  if mode~="Writs" then
    for id,name in pairs(items) do
      if type(id)=="number" and type(name)=="string" and name~="" then names[id]=name end
    end
  end
  if mode~="Crates" then
    local function add(id)
      if names[id]==nil then names[id]=getItemName(id) or false end
    end
    local visited, crafting={}, MFO_WritCrafting and MFO_WritCrafting.Enabled()
    for _,writ in ipairs(MFO_WritCalculations.available(faction)) do
      add(writ.id)
      for _,item in ipairs(writ.items) do
        add(item.id)
        if crafting then MFO_WritCrafting.AddScanMaterials(item.id,add,visited) end
      end
    end
  end
  queue={}
  for id,name in pairs(names) do queue[#queue+1]={id=id,name=name or nil} end
  table.sort(queue,function(a,b)
    local first,second=a.name or "",b.name or ""
    if first==second then return a.id<b.id end
    return first<second
  end)
  if #queue==0 then return false,"No resolved items to scan" end
  scanMode,scanRealm,scanFaction,completed=mode,realm,faction,false
  scanMarket=db(realm,faction)
  position=1;busy=true;waiting=false;started=nil;priced=0;scanTotal=#queue;attempts=0;missing={}
  AH.message="Scanning "..#queue.." items"
  return true
end
-- WoW Forever uses the modern C_AuctionHouse API, unlike legacy Classic.
modern = C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery)=="function"
-- Reuse the exact item key used for the active query when reading its results.
local activeItemKey
local function modernNext()
  if not busy or waiting then return end
  if position>#queue then
    finishScan()
    return
  end
  local entry=queue[position]
  local key=activeItemKey
  if not key then
    key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(entry.id) or {itemID=entry.id}
    activeItemKey=key
  end
  if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(key) then
    getItemName(entry.id)
    if not waitForItem(entry) then activeItemKey=nil end
    return
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    started=started or (GetTime and GetTime() or 0)
    if GetTime and GetTime()-started>15 then
      stopScan("AH throttle timed out; completion time unchanged")
    end
    return
  end
  -- Arm result handling before dispatch; a first query may respond synchronously.
  waiting=true;started=GetTime and GetTime() or 0
  local ok=pcall(C_AuctionHouse.SendSearchQuery,key,{},false)
  if not ok then stopScan("Modern AH query failed; scan not saved");return end
end
local modernEvents=CreateFrame("Frame")
local modernOK=pcall(modernEvents.RegisterEvent,modernEvents,"ITEM_SEARCH_RESULTS_UPDATED")
local commodityOK=pcall(modernEvents.RegisterEvent,modernEvents,"COMMODITY_SEARCH_RESULTS_UPDATED")
modernEvents:SetScript("OnEvent",function(_,event,arg)
  if not busy or not waiting or not modern or not auctionOpen() or not scanMarketMatches() then return end
  local entry=queue[position]
  local id=type(arg)=="table" and arg.itemID or arg
  if id~=entry.id then return end
  local key=activeItemKey
  if not key then return end
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
      if type(p)=="number" and p>0 and (not price or p<price) then
        price=p
        -- One copper is the lowest possible valid unit price.
        if price==1 then break end
      end
    end
  elseif not isCommodity and C_AuctionHouse.GetItemSearchResultInfo then
    for i=1,(C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(key) or 0) do
      local item=C_AuctionHouse.GetItemSearchResultInfo(key,i)
      local p=item and item.buyoutAmount
      if type(p)=="number" and p>0 then
        p=math.ceil(p/math.max(1,item.quantity or 1))
        if not price or p<price then
          price=p
          if price==1 then break end
        end
      end
    end
  end
  if price then
    scanMarket.prices[entry.id]={price=price,updated=time()}
    priced=priced+1
  else
    if not entry.name then entry.name=getItemName(entry.id) end
    recordUnpriced(entry)
  end
  attempts=0
  activeItemKey=nil;started=nil
  waiting=false;position=position+1
  if AH.onUpdate then AH.onUpdate() end
end)
function AH.Scan(items,mode)
  mode=mode or "Crates"
  if mode~="Crates" and mode~="Writs" and mode~="Full" then return false,"Unknown scan mode" end
  if busy then return false,"Scan already running" end
  if not auctionOpen() then return false,"Open the Auction House first" end
  if modern then
    if not modernOK and not commodityOK then return false,"Modern AH result events unavailable" end
  else
    if not eventOK then return false,"Auction list update event unavailable" end
    if type(QueryAuctionItems)~="function" or type(GetAuctionItemInfo)~="function" or
      type(GetNumAuctionItems)~="function" then
      return false,"Legacy Auction House query API unavailable in this client"
    end
  end
  local ok,message=prepareScan(items,mode)
  if not ok then return false,message end
  activeItemKey=nil;page=0;lowest=nil
  if AH.onUpdate then AH.onUpdate() end
  if modern then modernNext() else nextQuery() end
  return true,AH.message
end
local events=CreateFrame("Frame")
eventOK=pcall(events.RegisterEvent,events,"AUCTION_ITEM_LIST_UPDATE")
if not eventOK then
  AH.message="AH scan event unavailable in this client"
end
events:SetScript("OnEvent",function()
  if not busy or not waiting or modern or not auctionOpen() or not scanMarketMatches() then return end
  local entry=queue[position]
  if not entry then return end
  local ok,count,total=pcall(GetNumAuctionItems,"list")
  if not ok or type(count)~="number" then
    stopScan("Scan stopped: auction results unavailable");return
  end
  for i=1,count do
    local good,name,texture,stack,quality,usable,level,minBid,minIncrement,buyout=pcall(GetAuctionItemInfo,"list",i)
    if good and name==entry.name and type(stack)=="number" and stack>0 and
      type(buyout)=="number" and buyout>0 then
      local unit=math.ceil(buyout/stack)
      if not lowest or unit<lowest then lowest=unit end
      if lowest==1 then break end
    end
  end
  waiting=false
  if type(total)=="number" and (page+1)*50<total then
    page=page+1
  else
    if lowest then scanMarket.prices[entry.id]={price=lowest,updated=time()};priced=priced+1
    else recordUnpriced(entry) end
    position=position+1;page=0;lowest=nil;started=nil
  end
  if AH.onUpdate then AH.onUpdate() end
end)
local scanTick=0
events:SetScript("OnUpdate",function(_,elapsed)
  if not busy then scanTick=0;return end
  -- Closing the Auction House invalidates outstanding search results.
  if not auctionOpen() then
    stopScan("AH closed; scan cancelled without updating completion time")
    scanTick=0
    return
  end
  -- Avoid polling item-cache readiness on every rendered frame.
  scanTick=scanTick+elapsed
  if scanTick<.2 then return end
  scanTick=0
  if not scanMarketMatches() then
    stopScan("AH market changed; scan cancelled without updating completion time")
    return
  end
  if modern and not waiting then modernNext();return end
  if waiting then
    if GetTime and GetTime()-started>15 then
      stopScan("Scan timed out; completion time unchanged")
    end
  else
    nextQuery()
  end
end)
