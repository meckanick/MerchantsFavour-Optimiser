-- MFO shopping tab: integrates with the native Auction House without automating purchases.
local AH=MFO_AH
local host,tab,panel,selected
local tabIndex
local nativeTabsHooked=false
local tabSwitchHooked=false
local rows={}
local hiddenPanels={}
local switching=false
-- Hide native AH content instead of trying to paint over active widgets.
-- Keep the parent frame, its portrait, outer border, close control and bottom tabs.
local function isBottomTab(child,parent)
 if not child or not child.GetText or not child.GetBottom or not parent.GetBottom then return false end
 local ok,label=pcall(child.GetText,child)
 if not ok or (label~="Buy" and label~="Sell" and label~="Auctions" and label~="MFO Shop") then return false end
 local cb,pb=child:GetBottom(),parent:GetBottom()
 return cb and pb and cb<=pb+32
end
local function hideNative(parent)
 wipe(hiddenPanels)
 local seen={}
 local function hide(f)
  if not f or f==panel or f==tab or seen[f] then return end
  if not f.IsShown or not f:IsShown() then return end
  seen[f]=true
  hiddenPanels[#hiddenPanels+1]=f
  f:Hide()
 end
 -- Native auction content roots, where exposed by the client.
 for _,f in pairs({_G.AuctionFrameBrowse,_G.AuctionFrameBid,_G.AuctionFrameAuctions,
  _G.AuctionHouseFrameBrowse,_G.AuctionHouseFrameBuy,_G.AuctionHouseFrameSell,
  _G.AuctionHouseFrameAuctions,_G.AuctionHouseFrameBrowseFrame,
  parent.BrowseFrame,parent.BuyFrame,parent.SellFrame,parent.AuctionsFrame}) do hide(f) end
 -- WoW Forever uses different native child names: identify content by geometry.
 -- Preserve outer chrome, currency, bottom tabs and the window close button.
 if parent.GetChildren then
  local px,py=parent:GetCenter()
  local pw,ph=parent:GetWidth(),parent:GetHeight()
  if px and py and pw and ph then
   for _,child in ipairs({parent:GetChildren()}) do
    if child~=panel and child~=tab and not isBottomTab(child,parent)
     and child.GetCenter and child.GetWidth and child.GetHeight then
     local x,y=child:GetCenter()
     local w,h=child:GetWidth(),child:GetHeight()
     if x and y and w and h and w>60 and h>20
      and w<pw*.97 and h<ph*.92
      and y>py-ph*.42 and y<py+ph*.40 then
      hide(child)
     end
    end
   end
  end
 end
end
local function restoreNative()
 for i=#hiddenPanels,1,-1 do
  local f=hiddenPanels[i]
  if f and f.Show then f:Show() end
 end
 wipe(hiddenPanels)
end
-- Temporarily replace the native Auction House title; restore it on tab exit.
local originalTitles={}
local function setNativeTitle(parent)
 wipe(originalTitles)
 local seen={}
 local function inspect(region)
  if not region or seen[region] or not region.GetObjectType or region:GetObjectType()~="FontString" then return end
  seen[region]=true
  local value=region:GetText()
  if value=="Auctions" or value=="Browse Auctions" or value=="Auction House" then
   local _,y=region:GetCenter()
   local _,py=parent:GetCenter()
   if y and py and y>py+parent:GetHeight()*.32 then
    originalTitles[#originalTitles+1]={region,value}
    region:SetText("MFO - Shopping")
   end
  end
 end
 local function scan(frame,depth)
  if not frame or depth>3 then return end
  if frame.GetRegions then
   for _,region in ipairs({frame:GetRegions()}) do inspect(region) end
  end
  if frame.GetChildren then
   for _,child in ipairs({frame:GetChildren()}) do
    if child~=panel and child~=tab then scan(child,depth+1) end
   end
  end
 end
 scan(parent,0)
end
local function restoreNativeTitle()
 for _,entry in ipairs(originalTitles) do
  if entry[1] and entry[1].SetText then entry[1]:SetText(entry[2]) end
 end
 wipe(originalTitles)
end
local function gold(c)
 if not c then return "No price" end
 return string.format("%dg %ds %dc",math.floor(c/10000),math.floor(c/100)%100,c%100)
end
local function button(parent,label,width)
 local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
 b:SetSize(width,23);b:SetText(label);return b
end
local function activeAH()
 if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return AuctionHouseFrame end
 if AuctionFrame and AuctionFrame:IsShown() then return AuctionFrame end
end
-- Read-only live search. Do not buy, reserve, or modify shopping quantities.
local live={id=nil,waiting=false,offers={},message="Select an item to search."}
local refreshOffers
local function startLiveSearch(id)
 live.id=id;live.offers={};live.waiting=false
 if not id then live.message="Select an item to search.";return end
 if select(2,AH.Progress()) then live.message="Wait for the MFO price scan to finish.";return end
 local item=AH.Shopping()[id]
 if not item then live.message="Item no longer in shopping list.";return end
 if C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery)=="function" then
  local key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id) or {itemID=id}
  local ok=pcall(C_AuctionHouse.SendSearchQuery,key,{},false)
  if ok then live.waiting=true;live.message="Searching live auctions...";return end
 end
 if type(QueryAuctionItems)=="function" then
  local ok=pcall(QueryAuctionItems,item.name,nil,nil,0,0,0,0,0,nil,false)
  if ok then live.waiting=true;live.message="Searching live auctions...";return end
 end
 live.message="Live search unavailable in this client."
end
local function collectLive(event,arg)
 if not live.waiting or not live.id or not panel or not panel:IsShown() then return end
 local id=live.id
 local offers={}
 if event=="AUCTION_ITEM_LIST_UPDATE" then
  if type(GetNumAuctionItems)~="function" or type(GetAuctionItemInfo)~="function" then return end
  local count=GetNumAuctionItems("list") or 0
  local wanted=AH.Shopping()[id]
  for i=1,math.min(count,100) do
   local name,_,qty,_,_,_,_,_,buyout=GetAuctionItemInfo("list",i)
   if wanted and name==wanted.name and type(buyout)=="number" and buyout>0 then
    offers[#offers+1]={price=math.ceil(buyout/math.max(1,qty or 1)),qty=qty or 1}
   end
  end
 else
  local returned=type(arg)=="table" and arg.itemID or arg
  if returned~=id then return end
  local api=C_AuctionHouse
  if not api then return end
  if event=="COMMODITY_SEARCH_RESULTS_UPDATED" and api.GetNumCommoditySearchResults and api.GetCommoditySearchResultInfo then
   for i=1,math.min(api.GetNumCommoditySearchResults(id) or 0,100) do
    local entry=api.GetCommoditySearchResultInfo(id,i)
    if entry and entry.unitPrice then offers[#offers+1]={price=entry.unitPrice,qty=entry.quantity or 1} end
   end
  elseif event=="ITEM_SEARCH_RESULTS_UPDATED" and api.GetNumItemSearchResults and api.GetItemSearchResultInfo then
   local key=api.MakeItemKey and api.MakeItemKey(id) or {itemID=id}
   for i=1,math.min(api.GetNumItemSearchResults(key) or 0,100) do
    local entry=api.GetItemSearchResultInfo(key,i)
    if entry and entry.buyoutAmount and entry.buyoutAmount>0 then
     offers[#offers+1]={price=math.ceil(entry.buyoutAmount/math.max(1,entry.quantity or 1)),qty=entry.quantity or 1}
    end
   end
  else return end
 end
 table.sort(offers,function(a,b)return a.price<b.price end)
 live.offers=offers;live.waiting=false
 live.message=#offers>0 and (#offers.." live price tiers/listings found") or "No live buyout listings found."
 if refreshOffers then refreshOffers() end
end
local liveEvents=CreateFrame("Frame")
for _,name in ipairs({"ITEM_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_UPDATED","AUCTION_ITEM_LIST_UPDATE"}) do
 pcall(liveEvents.RegisterEvent,liveEvents,name)
end
liveEvents:SetScript("OnEvent",function(_,event,arg) collectLive(event,arg) end)
local function update()
 if not panel or not panel:IsShown() then return end
 local items={}
 for id,v in pairs(AH.Shopping()) do
  if type(id)=="number" and type(v)=="table" and (v.qty or 0)>0 then
   items[#items+1]={id=id,name=v.name or tostring(id),qty=v.qty}
  end
 end
 table.sort(items,function(a,b)return a.name<b.name end)
 panel.items=items
 panel.offset=math.min(panel.offset,math.max(0,#items-#rows))
 local total=0
 for _,v in ipairs(items) do
  local price=AH.Price(v.id)
  if price then total=total+price*v.qty end
 end
 panel.total:SetText(#items.." items  |  Estimated total: "..gold(total))
 local current=selected and AH.Shopping()[selected]
 if panel.detail then
  panel.detail:SetText(current and (current.name.."\nRequired quantity: "..current.qty.."\nCached unit price: "..gold(AH.Price(selected)).."\nEstimated total: "..gold((AH.Price(selected) or 0)*current.qty)) or "")
 end
 for i,row in ipairs(rows) do
  local item=items[i+panel.offset]
  row.item=item
  if item then
   row.label:SetText((selected==item.id and "|cffffd45a> |r" or "")..item.name.." x"..item.qty)
   local price=AH.Price(item.id)
   row.cost:SetText(price and gold(price*item.qty) or "No price")
   row:Show()
  else row:Hide() end
 end
 panel.page:SetText((#items==0 and 0 or panel.offset+1).."-"..math.min(#items,panel.offset+#rows).." / "..#items)
end
local function search()
 local item=selected and AH.Shopping()[selected]
 if not item then return false,"Select an item first." end
 if select(2,AH.Progress()) then return false,"Wait for MFO scan to finish." end
 local name=item.name
 local edit=_G.BrowseName or _G.AuctionFrameBrowseName
 if edit and edit.SetText then edit:SetText(name) end
 if C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery)=="function" then
  local key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(selected) or {itemID=selected}
  if pcall(C_AuctionHouse.SendSearchQuery,key,{},false) then
   return true,"Search submitted for "..name..". Purchase using the normal AH controls."
  end
 end
 if type(QueryAuctionItems)=="function" and pcall(QueryAuctionItems,name,nil,nil,0,0,0,0,0,nil,false) then
  return true,"Search submitted for "..name..". Purchase using the normal AH controls."
 end
 return false,"Search unavailable; use the AH search box for "..name.."."
end
local function close()
 if panel then panel:Hide() end
 restoreNative()
 restoreNativeTitle()
 if tab then tab:SetButtonState("NORMAL",false) end
end
local function attach(parent)
 if parent==host then return end
 host=parent
 -- WoW Forever exposes AuctionHouseFrame (not AuctionFrame), so the old
 -- AuctionFrame-only path always fell back to a top-right button.
 -- Anchor a real bottom-row tab to the existing last native AH tab.
 local last
 for i=1,20 do
  local candidate=_G["AuctionFrameTab"..i] or _G["AuctionHouseFrameTab"..i]
  if candidate and candidate.IsShown and candidate:IsShown() then last=candidate end
 end
 if not last and parent.GetChildren then
  for _,child in ipairs({parent:GetChildren()}) do
   if child.GetText and child.IsShown and child:IsShown() then
    local label=child:GetText()
    if label=="Auctions" or label=="Sell" then last=child end
   end
  end
 end
 local template="AuctionTabTemplate"
 if not _G.AuctionTabTemplate and not _G.AuctionFrameTab1 then template="UIPanelButtonTemplate" end
 tab=CreateFrame("Button",nil,parent,template)
 tab:SetText("MFO Shop")
 tab:SetSize(108,29)
 tab:SetFrameLevel(parent:GetFrameLevel()+12)
 if last then
  tab:SetPoint("LEFT",last,"RIGHT",-7,0)
 else
  tab:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",338,-16)
 end
 tab:Show()
 panel=CreateFrame("Frame",nil,parent,"BackdropTemplate")
 panel:SetPoint("TOPLEFT",parent,"TOPLEFT",8,-8)
 panel:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-8,34)
 panel:SetFrameLevel(parent:GetFrameLevel()+60)
 panel:EnableMouse(true)
 -- Native Auction House art: reuse the client's installed interface textures.
 -- The parent retains its native border, portrait and close button.
 local background=panel:CreateTexture(nil,"BACKGROUND")
 background:SetAllPoints(panel)
 background:SetColorTexture(.105,.089,.071,1)
 local tint=panel:CreateTexture(nil,"BORDER")
 tint:SetAllPoints(panel)
 tint:SetColorTexture(.11,.09,.075,1)
 local function inset(left,top,right,bottom)
  local f=CreateFrame("Frame",nil,panel,"BackdropTemplate")
  f:SetPoint("TOPLEFT",panel,"TOPLEFT",left,top)
  f:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",right,bottom)
  f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
   edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=15,
   insets={left=3,right=3,top=3,bottom=3}})
  f:SetBackdropColor(.12,.105,.085,.94)
  f:SetBackdropBorderColor(.52,.48,.39,1)
  f:EnableMouse(false)
  return f
 end
 -- Auctionator-like split: shopping lists on the left, search/details on the right.
 local left=inset(16,-100,-350,30)
 local right=inset(366,-100,-16,30)
 -- Anchor panels to each other, never to overlapping parent offsets.
 left:ClearAllPoints()
 left:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-100)
 left:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",16,30)
 left:SetWidth(340)
 right:ClearAllPoints()
 right:SetPoint("TOPLEFT",left,"TOPRIGHT",8,0)
 right:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-16,30)
 left:SetFrameLevel(panel:GetFrameLevel()+1)
 right:SetFrameLevel(panel:GetFrameLevel()+1)
 local topbar=panel:CreateTexture(nil,"ARTWORK")
 topbar:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-35)
 topbar:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-35)
 topbar:SetHeight(2)
 topbar:SetColorTexture(.53,.43,.24,.9)
 local header=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
 header:SetPoint("TOP",panel,"TOP",0,-14)
 header:SetText("")
 local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 title:SetPoint("TOPLEFT",left,"TOPLEFT",14,-14)
 title:SetText("Shopping Lists")
 local resultsTitle=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 resultsTitle:SetPoint("TOPLEFT",right,"TOPLEFT",14,-14)
 resultsTitle:SetText("Selected Item")
 local priceTitle=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 priceTitle:SetPoint("TOPRIGHT",right,"TOPRIGHT",-16,-14)
 priceTitle:SetText("")
 local line=panel:CreateTexture(nil,"ARTWORK")
 line:SetPoint("TOPLEFT",right,"TOPLEFT",8,-37)
 line:SetPoint("TOPRIGHT",right,"TOPRIGHT",-8,-37)
 line:SetHeight(1)
 line:SetColorTexture(.43,.41,.37,1)
 local market=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 market:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-24,-65)
 market:SetText(AH.Market())
 panel.total=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 panel.total:SetPoint("TOPLEFT",panel,"TOPLEFT",30,-65)
 local hint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
 hint:SetPoint("TOPLEFT",right,"TOPLEFT",16,-49)
 hint:SetText("Select an item to search live listings")
 panel.detail=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 panel.detail:SetPoint("TOPLEFT",right,"TOPLEFT",16,-67)
 panel.detail:SetPoint("RIGHT",right,"RIGHT",-16,0)
 panel.detail:SetJustifyH("LEFT")
 panel.detail:SetTextColor(.95,.84,.57)
 local liveHeader=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 liveHeader:SetPoint("TOPLEFT",right,"TOPLEFT",16,-155)
 liveHeader:SetText("Unit Price                 Available")
 local liveRows={}
 for i=1,8 do
  local row=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  row:SetPoint("TOPLEFT",right,"TOPLEFT",18,-177-(i-1)*25)
  row:SetPoint("RIGHT",right,"RIGHT",-18,0)
  row:SetJustifyH("LEFT")
  liveRows[i]=row
 end
 local liveStatus=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 liveStatus:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",16,88)
 liveStatus:SetPoint("RIGHT",right,"RIGHT",-16,0)
 liveStatus:SetJustifyH("LEFT")
 refreshOffers=function()
  if not panel or not panel:IsShown() then return end
  liveStatus:SetText(live.message or "")
  for i,row in ipairs(liveRows) do
   local offer=live.offers[i]
   row:SetText(offer and (gold(offer.price).."                         x"..offer.qty) or "")
  end
 end
 panel:Hide()
 panel.offset=0
 for i=1,9 do
  local row=CreateFrame("Button",nil,panel)
  row:SetHeight(23)
  row:SetPoint("TOPLEFT",left,"TOPLEFT",10,-52-(i-1)*26)
  row:SetPoint("RIGHT",left,"RIGHT",-10,0)
  row.label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  row.label:SetPoint("LEFT",4,0);row.label:SetPoint("RIGHT",row,"RIGHT",-78,0);row.label:SetJustifyH("LEFT");row.label:SetWordWrap(false)
  row.cost=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  row.cost:SetPoint("RIGHT",-4,0);row.cost:SetWidth(72);row.cost:SetJustifyH("RIGHT")
  row:SetScript("OnClick",function(self)if self.item then selected=self.item.id;startLiveSearch(selected);update();if refreshOffers then refreshOffers() end end end)
  row:SetScript("OnEnter",function(self)
   if self.item then
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:AddLine(self.item.name,1,.82,.2)
    GameTooltip:AddLine("Required: "..self.item.qty,1,1,1)
    GameTooltip:AddLine("Cached unit price: "..gold(AH.Price(self.item.id)),1,1,1)
    GameTooltip:Show()
   end
  end)
  row:SetScript("OnLeave",function()GameTooltip:Hide()end)
  rows[i]=row
 end
 panel.page=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 panel.page:SetPoint("BOTTOMLEFT",left,"BOTTOMLEFT",14,20)
 local prev=button(panel,"<",27)
 prev:SetPoint("LEFT",panel.page,"RIGHT",10,0)
 prev:SetScript("OnClick",function()panel.offset=math.max(0,panel.offset-9);update()end)
 local nextPage=button(panel,">",27)
 nextPage:SetPoint("LEFT",prev,"RIGHT",4,0)
 nextPage:SetScript("OnClick",function()panel.offset=math.min(math.max(0,#panel.items-9),panel.offset+9);update()end)
 local find=button(panel,"Search AH",100)
 find:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-108,10)
 local message=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 message:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",14,53)
 message:SetPoint("RIGHT",right,"RIGHT",-14,0)
 message:SetJustifyH("LEFT")
 message:SetWordWrap(true)
 find:SetScript("OnClick",function()
  local ok,info=search()
  message:SetText((ok and "|cff66ff66" or "|cffff7777")..info.."|r")
 end)
 local done=button(panel,"Close",75)
 done:SetPoint("LEFT",find,"RIGHT",8,0)
 done:SetScript("OnClick",close)
 local function activate()
  hideNative(parent)
  setNativeTitle(parent)
  panel:Show()
  live.message="Select an item to search live listings."
  live.offers={};live.waiting=false;live.id=nil
  tab:SetButtonState("PUSHED",true)
  update()
  refreshOffers()
 end
 tab:SetScript("OnClick",activate)
 -- Restore native panes whenever a different bottom tab is selected.
 if parent.GetChildren then
  for _,child in ipairs({parent:GetChildren()}) do
   if child~=tab and child.GetText and child.HookScript then
    local ok,label=pcall(child.GetText,child)
    if ok and (label=="Buy" or label=="Sell" or label=="Auctions") then
     child:HookScript("OnClick",function()
      if panel and panel:IsShown() then close() end
     end)
    end
   end
  end
 end
 parent:HookScript("OnHide",close)
end
local watcher=CreateFrame("Frame")
pcall(watcher.RegisterEvent,watcher,"ADDON_LOADED")
pcall(watcher.RegisterEvent,watcher,"AUCTION_HOUSE_SHOW")
watcher:SetScript("OnEvent",function(_,event,addon)
 if event=="ADDON_LOADED" and addon=="Blizzard_AuctionUI" and AuctionFrame then
  attach(AuctionFrame)
 elseif event=="AUCTION_HOUSE_SHOW" then
  local current=activeAH()
  if current and current~=host then attach(current) end
 end
end)
local timer=0
watcher:SetScript("OnUpdate",function(_,dt)
 timer=timer+dt
 if timer<.5 then return end
 timer=0
 local current=activeAH()
 if current and current~=host then attach(current) end
 if panel and panel:IsShown() then update() end
end)
