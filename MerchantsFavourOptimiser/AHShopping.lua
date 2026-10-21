-- MFO shopping tab: integrates with the native Auction House without automating purchases.
local AH=MFO_AH
local ART="Interface\\AddOns\\MerchantsFavourOptimiser\\"
local host,tab,panel,selected
local tabIndex
local setTabSelected
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
 b:SetSize(width,23);b:SetText(label)
 local texture=ART.."WTP_FooterButton"
 b:SetNormalTexture(texture);b:SetPushedTexture(texture)
 b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
 local font=b:GetFontString()
 if font then font:SetFontObject(GameFontNormalSmall);font:SetTextColor(1,.82,.05) end
 return b
end
local function activeAH()
 if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return AuctionHouseFrame end
 if AuctionFrame and AuctionFrame:IsShown() then return AuctionFrame end
end
-- Live auction search; purchases require a separate explicit hardware click.
local live={id=nil,waiting=false,offers={},message="Select an item to search.",elapsed=0}
local refreshOffers
local selectedOffer
local commodityOrder
local confirmCommodity
local resetPurchaseDialogs
local awaitingPurchase=false
local purchaseElapsed=0
local purchaseWarningShown=false
local function startLiveSearch(id)
 if commodityOrder or awaitingPurchase then
  live.message="Purchase pending. Wait for the Auction House result before searching again."
  if refreshOffers then refreshOffers() end
  return
 end
 if resetPurchaseDialogs then resetPurchaseDialogs() end
 if panel and panel.offerScroll then panel.offerScroll:SetValue(select(2,panel.offerScroll:GetMinMaxValues()) or 0) end
 live.id=id;live.offers={};live.waiting=false;live.elapsed=0;selectedOffer=nil
 if not id then live.message="Select an item to search.";return end
 if select(2,AH.Progress()) then live.message="Wait for the MFO price scan to finish.";return end
 local item=AH.Shopping()[id]
 if not item then live.message="Item no longer in shopping list.";return end
 -- Mark the request as waiting BEFORE dispatch: some AH clients deliver
 -- results during SendSearchQuery, before the call returns.
 live.waiting=true;live.message="Searching live auctions..."
 if C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery)=="function" then
  local key=C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id) or {itemID=id}
  local ok=pcall(C_AuctionHouse.SendSearchQuery,key,{},false)
  if ok then return end
 end
 if type(QueryAuctionItems)=="function" then
  local ok=pcall(QueryAuctionItems,item.name,nil,nil,0,0,0,0,0,nil,false)
  if ok then return end
 end
 live.waiting=false
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
  for i=1,count do
   local name,_,qty,_,_,_,_,_,_,buyout=GetAuctionItemInfo("list",i)
   if wanted and name==wanted.name and type(buyout)=="number" and buyout>0 then
    offers[#offers+1]={price=math.ceil(buyout/math.max(1,qty or 1)),qty=qty or 1,legacyIndex=i,buyout=buyout}
   end
  end
 else
  local returned=type(arg)=="table" and arg.itemID or arg
  if returned~=id then return end
  local api=C_AuctionHouse
  if not api then return end
  if event=="COMMODITY_SEARCH_RESULTS_UPDATED" and api.GetNumCommoditySearchResults and api.GetCommoditySearchResultInfo then
   for i=1,(api.GetNumCommoditySearchResults(id) or 0) do
    local entry=api.GetCommoditySearchResultInfo(id,i)
    if entry and entry.unitPrice then offers[#offers+1]={price=entry.unitPrice,qty=entry.quantity or 1,commodity=true} end
   end
  elseif event=="ITEM_SEARCH_RESULTS_UPDATED" and api.GetNumItemSearchResults and api.GetItemSearchResultInfo then
   local key=api.MakeItemKey and api.MakeItemKey(id) or {itemID=id}
   for i=1,(api.GetNumItemSearchResults(key) or 0) do
    local entry=api.GetItemSearchResultInfo(key,i)
    if entry and entry.buyoutAmount and entry.buyoutAmount>0 then
     offers[#offers+1]={price=math.ceil(entry.buyoutAmount/math.max(1,entry.quantity or 1)),qty=entry.quantity or 1,auctionID=entry.auctionID,buyout=entry.buyoutAmount}
    end
   end
  else return end
 end
 table.sort(offers,function(a,b)return a.price<b.price end)
 live.offers=offers;live.waiting=false;live.elapsed=0;selectedOffer=nil
 live.message=#offers>0 and (#offers.." listings found - scroll to see all") or "No live buyout listings found."
 if refreshOffers then refreshOffers() end
end
local liveEvents=CreateFrame("Frame")
for _,name in ipairs({"ITEM_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_UPDATED","AUCTION_ITEM_LIST_UPDATE","COMMODITY_PRICE_UPDATED","COMMODITY_PRICE_UNAVAILABLE","COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASE_FAILED","AUCTION_HOUSE_THROTTLED_SYSTEM_READY"}) do
 pcall(liveEvents.RegisterEvent,liveEvents,name)
end
liveEvents:SetScript("OnEvent",function(_,event,arg)
 if event=="AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
  return -- Throttle notifications are not auction result payloads.
 elseif event=="COMMODITY_PRICE_UPDATED" then
  if commodityOrder and not awaitingPurchase and confirmCommodity then confirmCommodity() end
 elseif event=="COMMODITY_PRICE_UNAVAILABLE" or event=="COMMODITY_PURCHASE_FAILED" then
  if not commodityOrder and not awaitingPurchase then return end
  commodityOrder=nil;awaitingPurchase=false;purchaseElapsed=0;purchaseWarningShown=false
  if resetPurchaseDialogs then resetPurchaseDialogs() end
  live.offers={};live.waiting=false;selectedOffer=nil
  live.message="Commodity price changed or purchase failed. Search again before buying."
  if refreshOffers then refreshOffers() end
 elseif event=="COMMODITY_PURCHASE_SUCCEEDED" then
  if not awaitingPurchase then return end
  commodityOrder=nil;awaitingPurchase=false;purchaseElapsed=0;purchaseWarningShown=false
  if resetPurchaseDialogs then resetPurchaseDialogs() end
  live.offers={};live.waiting=false;selectedOffer=nil
  live.message="Commodity purchase succeeded. Refresh your shopping list quantities."
  if refreshOffers then refreshOffers() end
 else collectLive(event,arg) end
end)
-- Crate membership is static; avoid rebuilding it on each UI refresh.
local crateIDs={}
for _,crate in ipairs(MFO_DATA or {}) do
 if type(crate.id)=="number" then crateIDs[crate.id]=true end
end
local function update()
 if not panel or not panel:IsShown() then return end
 local shopping=AH.Shopping()
 local items={}
 for id,v in pairs(shopping) do
  if type(id)=="number" and type(v)=="table" and (v.qty or 0)>0 then
   items[#items+1]={id=id,name=v.name or tostring(id),qty=v.qty}
  end
 end
 -- Always list Waylaid Crates before their required materials.
 -- Prefer the addon crate IDs; the name prefix also covers future crates.
 -- Reuse the static crate membership table.
 local function isCrate(item)
  return crateIDs[item.id] or item.name:find("^Waylaid Crate:")~=nil
 end
 table.sort(items,function(a,b)
  local aCrate,bCrate=isCrate(a),isCrate(b)
  if aCrate~=bCrate then return aCrate end
  if a.name~=b.name then return a.name<b.name end
  return a.id<b.id
 end)
 panel.items=items
 panel.offset=math.min(panel.offset,math.max(0,#items-#rows))
 local total=0
 local prices={}
 for _,v in ipairs(items) do
  local price=AH.Price(v.id)
  prices[v.id]=price
  if price then total=total+price*v.qty end
 end
 panel.total:SetText(#items.." items  |  Estimated total: "..gold(total))
 local current=selected and shopping[selected]
 if panel.detail then
  local selectedPrice=current and prices[selected]
  panel.detail:SetText(current and (current.name.."\nRequired quantity: "..current.qty.."\nCached unit price: "..gold(selectedPrice).."\nEstimated total: "..gold((selectedPrice or 0)*current.qty)) or "")
 end
 if panel.itemIcon then
  if current then
   local texture=type(GetItemIcon)=="function" and GetItemIcon(selected)
   if not texture and C_Item and C_Item.GetItemIconByID then texture=C_Item.GetItemIconByID(selected) end
   panel.itemIcon:SetNormalTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
   panel.itemIcon:Show()
  else panel.itemIcon:Hide() end
 end
 for i,row in ipairs(rows) do
  local item=items[i+panel.offset]
  row.item=item
  if item then
   row.label:SetText((selected==item.id and "|cffffd45a> |r" or "")..item.name.." x"..item.qty)
   if selected==item.id then row.highlight:Show() else row.highlight:Hide() end
   local price=prices[item.id]
   row.cost:SetText(price and gold(price*item.qty) or "No price")
   row:Show()
  else row.highlight:Hide();row:Hide() end
 end
end
local function close()
 if resetPurchaseDialogs then resetPurchaseDialogs() end
 commodityOrder=nil
 if panel then panel:Hide() end
 -- Discard results and selections from the previous AH session.
 live.id=nil;live.offers={};live.waiting=false;live.elapsed=0
 selectedOffer=nil;selected=nil
 if refreshOffers then refreshOffers() end
 restoreNative()
 restoreNativeTitle()
 if tab then setTabSelected(false) end
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
 -- Forever's modern AH uses display-mode tabs, not AuctionTabTemplate.
 -- Only create the native template when the client exposes its controller;
 -- otherwise retain the tested Forever-safe custom tab.
 local modern=parent.Tabs and #parent.Tabs>0
  and type(PanelTemplates_SelectTab)=="function"
  and type(PanelTemplates_DeselectTab)=="function"
 local reference=modern and parent.Tabs[#parent.Tabs] or nil
 if modern then
  local ok,created=pcall(CreateFrame,"Button",nil,parent,"AuctionHouseFrameDisplayModeTabTemplate")
  if ok and created then tab=created else modern=false end
 end
 if modern then
  tab:SetText("MFO Shop")
  if type(PanelTemplates_TabResize)=="function" then
   PanelTemplates_TabResize(tab,20,nil,70)
  else
   tab:SetWidth(108)
  end
  tab:SetPoint("TOPLEFT",reference,"TOPRIGHT",3,0)
  PanelTemplates_DeselectTab(tab)
  setTabSelected=function(active)
   if active then
    for _,native in ipairs(parent.Tabs) do PanelTemplates_DeselectTab(native) end
    PanelTemplates_SelectTab(tab)
   else
    PanelTemplates_DeselectTab(tab)
   end
  end
 else
  tab=CreateFrame("Button",nil,parent,"BackdropTemplate")
  tab:SetSize(108,29)
  tab:SetBackdrop({
   bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
   edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
   tile=false,edgeSize=12,
   insets={left=3,right=3,top=3,bottom=3}
  })
  local tabText=tab:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  tabText:SetPoint("CENTER",tab,"CENTER",0,0)
  tabText:SetText("MFO Shop")
  tab:SetFontString(tabText)
  local face={}
  for i=1,12 do
   local strip=tab:CreateTexture(nil,"BACKGROUND",nil,1)
   strip:SetPoint("TOPLEFT",tab,"TOPLEFT",4,-3-(i-1)*2)
   strip:SetPoint("TOPRIGHT",tab,"TOPRIGHT",-4,-3-(i-1)*2)
   strip:SetHeight(3)
   face[i]=strip
  end
  local selectedGlow=CreateFrame("Frame",nil,tab,"BackdropTemplate")
  selectedGlow:SetPoint("TOPLEFT",tab,"TOPLEFT",-2,2)
  selectedGlow:SetPoint("BOTTOMRIGHT",tab,"BOTTOMRIGHT",2,-2)
  selectedGlow:SetBackdrop({
   edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
   edgeSize=12,insets={left=0,right=0,top=0,bottom=0}
  })
  selectedGlow:SetBackdropBorderColor(1,.79,.07,1)
  selectedGlow:Hide()
  setTabSelected=function(active)
   tab:SetHeight(active and 35 or 29)
   if active then
    tab:SetBackdropColor(.20,.15,.085,1)
    tab:SetBackdropBorderColor(.90,.67,.10,1)
    tabText:SetTextColor(1,1,.91,1)
    for i,strip in ipairs(face) do
     local t=(i-1)/11
     strip:SetColorTexture(.22+.40*t,.16+.23*t,.09+.025*t,1)
    end
    selectedGlow:Show()
   else
    tab:SetBackdropColor(.10,.10,.10,1)
    tab:SetBackdropBorderColor(.27,.26,.24,1)
    tabText:SetTextColor(1,.79,.18,1)
    for i,strip in ipairs(face) do
     local t=(i-1)/11
     local grey=.24-.10*t
     strip:SetColorTexture(grey,grey,grey,1)
    end
    selectedGlow:Hide()
   end
  end
  setTabSelected(false)
  if last then
   tab:SetPoint("TOPLEFT",last,"TOPRIGHT",-7,0)
  else
   tab:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",338,-16)
  end
 end
 tab:SetFrameLevel(parent:GetFrameLevel()+12)
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
 background:SetTexture(ART.."MFO_WoodBackground")
 local tint=panel:CreateTexture(nil,"BORDER")
 tint:SetAllPoints(panel)
 tint:SetTexture(ART.."MFO_CoinBackground")
 tint:SetVertexColor(.78,.68,.54,1)
 tint:SetAlpha(.40)
 local function inset(left,top,right,bottom)
  local f=CreateFrame("Frame",nil,panel,"BackdropTemplate")
  f:SetPoint("TOPLEFT",panel,"TOPLEFT",left,top)
  f:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",right,bottom)
  f:SetBackdrop({bgFile=ART.."MFO_WoodBackground",
   edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",edgeSize=18,
   insets={left=7,right=7,top=7,bottom=7}})
  f:SetBackdropColor(.75,.65,.54,1)
  f:SetBackdropBorderColor(1,.84,.48,1)
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
 -- Both inset panels use the same clean wood background.
 left:SetFrameLevel(panel:GetFrameLevel()+1)
 right:SetFrameLevel(panel:GetFrameLevel()+1)
 -- The main addon uses a recessed profession-row texture for section headings.
 local function sectionHeader(parent,label)
  local bar=CreateFrame("Frame",nil,parent,"BackdropTemplate")
  bar:SetPoint("TOPLEFT",parent,"TOPLEFT",9,-8)
  bar:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-9,-8)
  bar:SetHeight(29)
  bar:SetBackdrop({bgFile=ART.."WTP_ProfessionRow"})
  local caption=bar:CreateFontString(nil,"OVERLAY","GameFontNormal")
  caption:SetPoint("LEFT",bar,"LEFT",13,0)
  caption:SetText(label)
  caption:SetTextColor(1,.76,.13)
  return bar
 end
 sectionHeader(left,"Shopping Lists")
 sectionHeader(right,"Selected Item")

 local topbar=panel:CreateTexture(nil,"ARTWORK")
 topbar:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-35)
 topbar:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-35)
 topbar:SetHeight(2)
 topbar:SetColorTexture(.53,.43,.24,.9)
 local header=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
 header:SetPoint("TOP",panel,"TOP",0,-14)
 header:SetText("")

 local line=right:CreateTexture(nil,"ARTWORK")
 line:SetPoint("TOPLEFT",right,"TOPLEFT",10,-40)
 line:SetPoint("TOPRIGHT",right,"TOPRIGHT",-10,-40)
 line:SetHeight(1)
 line:SetColorTexture(.43,.41,.37,1)
 local market=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 market:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-24,-65)
 market:SetText(AH.Market())
 panel.total=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 panel.total:SetPoint("TOPLEFT",panel,"TOPLEFT",30,-65)
 panel.detail=right:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 panel.detail:SetPoint("TOPLEFT",right,"TOPLEFT",64,-54)
 panel.detail:SetPoint("RIGHT",right,"RIGHT",-16,0)
 panel.detail:SetJustifyH("LEFT")
 panel.detail:SetTextColor(1,.9,.65)
 panel.itemIcon=CreateFrame("Button",nil,right)
 panel.itemIcon:SetSize(40,40)
 panel.itemIcon:SetPoint("TOPLEFT",right,"TOPLEFT",16,-54)
 panel.itemIcon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
 panel.itemIcon:SetScript("OnEnter",function(self)
  if not selected then return end
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  if type(GameTooltip.SetItemByID)=="function" then
   GameTooltip:SetItemByID(selected)
  elseif type(GameTooltip.SetHyperlink)=="function" then
   GameTooltip:SetHyperlink("item:"..selected)
  end
  GameTooltip:Show()
 end)
 panel.itemIcon:SetScript("OnLeave",function()GameTooltip:Hide()end)
 panel.itemIcon:Hide()
 local liveHeader=right:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 liveHeader:SetPoint("TOPLEFT",right,"TOPLEFT",18,-135)
 liveHeader:SetText("Auction House Listings")
 local priceHeader=right:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 priceHeader:SetPoint("TOPLEFT",right,"TOPLEFT",18,-158)
 priceHeader:SetText("Unit Price")
 local quantityHeader=right:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 quantityHeader:SetPoint("TOPRIGHT",right,"TOPRIGHT",-28,-158)
 quantityHeader:SetText("Available")
 local liveRows={}
 local offerOffset=0
 local visibleOffers=4
 local offerScroll=CreateFrame("Slider",nil,right)
 panel.offerScroll=offerScroll
 offerScroll:SetPoint("TOPRIGHT",right,"TOPRIGHT",-9,-184)
 offerScroll:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-9,47)
 offerScroll:SetWidth(16)
 offerScroll:SetOrientation("VERTICAL")
 offerScroll:SetMinMaxValues(0,0)
 offerScroll:SetValueStep(1)
 offerScroll:SetObeyStepOnDrag(true)
 offerScroll:SetThumbTexture(ART.."WTP_ScrollThumb")
 offerScroll:SetValue(0)
 offerScroll:SetScript("OnValueChanged",function(_,value)
  local maximum=math.max(0,#live.offers-visibleOffers)
  local nextOffset=math.max(0,math.min(maximum,math.floor(maximum-value+.5)))
  if nextOffset~=offerOffset then
   offerOffset=nextOffset
   if refreshOffers then refreshOffers() end
  end
 end)
 -- Match the MFO main window scrollbar artwork and interaction states.
 local up=CreateFrame("Button",nil,right)
 up:SetSize(14,14)
 up:SetPoint("BOTTOM",offerScroll,"TOP",0,1)
 local down=CreateFrame("Button",nil,right)
 down:SetSize(14,14)
 down:SetPoint("TOP",offerScroll,"BOTTOM",0,-1)
 up:SetScript("OnClick",function() offerScroll:SetValue(math.min(math.max(0,#live.offers-visibleOffers),math.max(0,#live.offers-visibleOffers)-offerOffset+1)) end)
 down:SetScript("OnClick",function() offerScroll:SetValue(math.max(0,math.max(0,#live.offers-visibleOffers)-offerOffset-1)) end)
 local thumb=offerScroll.GetThumbTexture and offerScroll:GetThumbTexture()
 if up then
  up:SetSize(14,14)
  up:SetNormalTexture(ART.."WTP_ScrollUp")
  up:SetPushedTexture(ART.."WTP_ScrollUp")
  up:SetDisabledTexture(ART.."WTP_ScrollUp")
 end
 if down then
  down:SetSize(14,14)
  down:SetNormalTexture(ART.."WTP_ScrollDown")
  down:SetPushedTexture(ART.."WTP_ScrollDown")
  down:SetDisabledTexture(ART.."WTP_ScrollDown")
 end
 local track=offerScroll:CreateTexture(nil,"BACKGROUND")
 track:SetTexture(ART.."WTP_ScrollTrack")
 track:SetWidth(10)
 track:SetPoint("TOP",up or offerScroll,"BOTTOM",0,-1)
 track:SetPoint("BOTTOM",down or offerScroll,"TOP",0,1)
 local grip,gripGlow
 if thumb then
  thumb:SetTexture(ART.."WTP_ScrollThumb")
  thumb:SetWidth(10)
  grip=offerScroll:CreateTexture(nil,"ARTWORK")
  grip:SetTexture(ART.."WTP_ScrollThumb")
  grip:SetWidth(10)
  grip:SetHeight(90)
  thumb:SetAlpha(0)
 end
 local function glow(target,texture)
  if not target then return end
  local owner=(target==up or target==down) and target or offerScroll
  local g=owner:CreateTexture(nil,"OVERLAY")
  g:SetAllPoints(target)
  g:SetTexture(ART..texture)
  g:SetBlendMode("ADD")
  g:SetAlpha(.22)
  g:Hide()
  return g
 end
 local upGlow=glow(up,"WTP_ScrollUp")
 local downGlow=glow(down,"WTP_ScrollDown")
 if grip then gripGlow=glow(grip,"WTP_ScrollThumb") end
 local function toggle(g,active)
  if g then if active then g:Show() else g:Hide() end end
 end
 local function grey(button,disabled)
  if not button then return end
  for _,method in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture"}) do
   local t=button[method] and button[method](button)
   if t and t.SetDesaturated then t:SetDesaturated(disabled) end
  end
 end
 local dragging=false
 offerScroll:HookScript("OnMouseDown",function(_,button)
  if button=="LeftButton" then dragging=true end
 end)
 offerScroll:HookScript("OnMouseUp",function(_,button)
  if button=="LeftButton" then dragging=false end
 end)
 local function updateScrollSkin()
  if dragging and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then dragging=false end
  local low,high=offerScroll:GetMinMaxValues()
  low,high=low or 0,high or 0
  local value=offerScroll:GetValue() or 0
  local canUp=offerOffset>0
  local canDown=offerOffset<high
  grey(up,not canUp)
  grey(down,not canDown)
  toggle(upGlow,canUp and up and up:IsMouseOver())
  toggle(downGlow,canDown and down and down:IsMouseOver())
  if grip and thumb then
   local topEdge=up and up:GetBottom()
   local bottomEdge=down and down:GetTop()
   local barBottom=offerScroll:GetBottom()
   if topEdge and bottomEdge and barBottom then
    topEdge,bottomEdge=topEdge-2,bottomEdge+2
    local height=topEdge-bottomEdge
    if height>0 then
     local gripHeight=math.min(90,height)
     local fraction=high>low and math.max(0,math.min(1,offerOffset/(high-low))) or 0
     local centerY=topEdge-gripHeight/2-fraction*(height-gripHeight)
     if grip:GetHeight()~=gripHeight then grip:SetHeight(gripHeight) end
     grip:ClearAllPoints()
     grip:SetPoint("CENTER",offerScroll,"BOTTOM",0,centerY-barBottom)
     if thumb:IsShown() then grip:Show() else grip:Hide() end
    else grip:Hide() end
   else grip:Hide() end
   local hovering=false
   if grip:IsShown() and GetCursorPosition then
    local x,y=GetCursorPosition()
    local scale=offerScroll:GetEffectiveScale()
    if scale and scale>0 then
     x,y=x/scale,y/scale
     local l,r,b,t=grip:GetLeft(),grip:GetRight(),grip:GetBottom(),grip:GetTop()
     hovering=l and r and b and t and x>=l and x<=r and y>=b and y<=t or false
    end
   end
   toggle(gripGlow,thumb:IsShown() and high>low and (hovering or thumb:IsMouseOver() or dragging))
  end
 end
 offerScroll:HookScript("OnUpdate",updateScrollSkin)
 updateScrollSkin()
 local offerViewport=CreateFrame("Frame",nil,right)
 offerViewport:SetPoint("TOPLEFT",right,"TOPLEFT",16,-182)
 offerViewport:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-34,80)
 offerViewport:EnableMouseWheel(true)
 offerViewport:SetScript("OnMouseWheel",function(_,delta)
  offerScroll:SetValue(math.max(0,math.min(math.max(0,#live.offers-visibleOffers),math.max(0,#live.offers-visibleOffers)-offerOffset+delta)))
 end)
 for i=1,visibleOffers do
  local row=CreateFrame("Button",nil,offerViewport)
  row:SetHeight(31)
  row:SetPoint("TOPLEFT",offerViewport,"TOPLEFT",0,-(i-1)*34)
  row:SetPoint("RIGHT",offerViewport,"RIGHT",0,0)
  local price=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  price:SetPoint("LEFT",row,"LEFT",4,0)
  price:SetWidth(170)
  price:SetJustifyH("LEFT")
  row.price=price
  local quantity=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  quantity:SetPoint("RIGHT",row,"RIGHT",-12,0)
  quantity:SetWidth(70)
  quantity:SetJustifyH("RIGHT")
  row.quantity=quantity
  local highlight=row:CreateTexture(nil,"BACKGROUND")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(.63,.41,.08,.32)
  row.highlight=highlight
  highlight:Hide()
  row:SetScript("OnClick",function()
   if live.offers[offerOffset+i] then selectedOffer=offerOffset+i;refreshOffers() end
  end)
  liveRows[i]=row
 end
 local liveStatus=right:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 liveStatus:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",16,16)
 liveStatus:SetWidth(285)
 liveStatus:SetJustifyH("LEFT")
 liveStatus:SetWordWrap(false)
 refreshOffers=function()
  if not panel or not panel:IsShown() then return end
  local msg=live.message or ""
  if msg:find("Checking Auction House price",1,true) then msg="Checking AH price..." end
  liveStatus:SetText(msg)
  offerScroll:SetMinMaxValues(0,math.max(0,#live.offers-visibleOffers))
  offerScroll:SetValue(math.max(0,#live.offers-visibleOffers)-offerOffset)
  if #live.offers>visibleOffers then offerScroll:Show();up:Show();down:Show() else offerScroll:Hide();up:Hide();down:Hide() end
  for i,row in ipairs(liveRows) do
   local offer=live.offers[offerOffset+i]
   row.price:SetText(offer and gold(offer.price) or "")
   row.quantity:SetText(offer and ("x"..offer.qty) or "")
   if offer then row:Show() else row:Hide() end
   if selectedOffer==offerOffset+i then row.highlight:Show() else row.highlight:Hide() end
  end
  if panel.buyOffer then
   panel.buyOffer:SetEnabled(selectedOffer~=nil and live.offers[selectedOffer]~=nil and not live.waiting)
  end
 end
 -- Original MFO transaction UI: protected calls are made directly from
 -- genuine button clicks, never via pcall, timers or programmatic clicks.
 local pending
 local function skinPurchaseDialog(frame,title)
  frame:SetBackdrop({bgFile=ART.."MFO_WoodBackground",
   edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",edgeSize=22,
   insets={left=8,right=8,top=8,bottom=8}})
  frame:SetBackdropColor(.72,.60,.43,1)
  frame:SetBackdropBorderColor(1,.83,.44,1)
  local heading=frame:CreateTexture(nil,"ARTWORK")
  heading:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-12)
  heading:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-12,-12)
  heading:SetHeight(29)
  heading:SetTexture(ART.."WTP_ProfessionRow")
  local label=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
  label:SetPoint("CENTER",heading,"CENTER",0,0)
  label:SetText(title)
  label:SetTextColor(1,.78,.24)
 end
 local confirm=CreateFrame("Frame",nil,panel,"BackdropTemplate")
 confirm:SetSize(390,190)
 confirm:SetPoint("CENTER",panel,"CENTER")
 confirm:SetFrameStrata("DIALOG")
 confirm:SetFrameLevel(panel:GetFrameLevel()+30)
 confirm:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=22,
  insets={left=8,right=8,top=8,bottom=8}})
 local confirmText=confirm:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 confirmText:SetPoint("TOP",confirm,"TOP",0,-60)
 confirmText:SetWidth(350)
 local accept=button(confirm,"Buy",105)
 accept:SetPoint("BOTTOMLEFT",confirm,"BOTTOMLEFT",42,22)
 local cancel=button(confirm,"Cancel",90)
 cancel:SetPoint("BOTTOMRIGHT",confirm,"BOTTOMRIGHT",-42,22)
 local function dismiss()
  pending=nil
  confirm:Hide()
 end
 cancel:SetScript("OnClick",function()
  if commodityOrder and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
   C_AuctionHouse.CancelCommoditiesPurchase()
  end
  commodityOrder=nil
  dismiss()
 end)
 accept:SetScript("OnClick",function()
   local order=pending
  if not order or order.stage~="commodity-confirm" or not commodityOrder then return end
  if selected~=order.id or commodityOrder.id~=order.id then dismiss();return end
  dismiss()
  commodityOrder=nil
  if C_AuctionHouse and type(C_AuctionHouse.ConfirmCommoditiesPurchase)=="function" then
   awaitingPurchase=true;purchaseElapsed=0;purchaseWarningShown=false
   C_AuctionHouse.ConfirmCommoditiesPurchase(order.id,order.qty)
   live.message="Commodity confirmation submitted. Check Auction House result."
  else
   live.message="Commodity confirmation API unavailable."
  end
  refreshOffers()
 end)
 confirm:Hide()
 confirmCommodity=function()
  local order=commodityOrder
  local api=C_AuctionHouse
  if not order or not api then return end
  local total=order.estimated
  if type(api.GetCommodityPrice)=="function" then
   local info=api.GetCommodityPrice(order.id)
   if type(info)=="table" then total=info.totalPrice or total
   elseif type(info)=="number" then total=info end
  end
  pending={id=order.id,qty=order.qty,total=total,stage="commodity-confirm"}
  confirmText:SetText("Confirm commodity purchase\nQuantity: "..order.qty.."\nAuction House total: "..gold(total))
  accept:SetText("Confirm Buy")
  confirm:Show()
 end
 -- Pre-purchase dialog: Chain Buy is selected here, before the
 -- player's explicit purchase click. Keep the working API call first.
 local chainBuy=false
 local preflight=CreateFrame("Frame",nil,panel,"BackdropTemplate")
 preflight:SetSize(390,215)
 preflight:SetPoint("CENTER",panel,"CENTER")
 preflight:SetFrameStrata("DIALOG")
 preflight:SetFrameLevel(panel:GetFrameLevel()+31)
 preflight:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=22,
  insets={left=8,right=8,top=8,bottom=8}})
 preflight:SetBackdropColor(.055,.035,.015,1)
 local dialogFill=preflight:CreateTexture(nil,"BACKGROUND")
 dialogFill:SetPoint("TOPLEFT",preflight,"TOPLEFT",12,-12)
 dialogFill:SetPoint("BOTTOMRIGHT",preflight,"BOTTOMRIGHT",-12,12)
 dialogFill:SetColorTexture(.065,.042,.02,1)
 local preflightText=preflight:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 preflightText:SetPoint("TOP",preflight,"TOP",0,-61)
 preflightText:SetWidth(350)
 local chainToggle=CreateFrame("CheckButton",nil,preflight,"UICheckButtonTemplate")
 chainToggle:SetSize(24,24)
 chainToggle:SetPoint("TOPLEFT",preflight,"TOPLEFT",38,-130)
 chainToggle:SetChecked(false)
 local chainLabel=preflight:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 chainLabel:SetPoint("LEFT",chainToggle,"RIGHT",4,0)
 chainLabel:SetText("Chain Buy - full required quantity")
 chainToggle:SetScript("OnClick",function(self)
  chainBuy=self:GetChecked() and true or false
  local offer=selectedOffer and live.offers[selectedOffer]
  local item=selected and AH.Shopping()[selected]
  if offer and item then
   local qty=chainBuy and item.qty or math.min(item.qty,offer.qty)
   preflightText:SetText(item.name.."\nBuy quantity: "..qty.."    Needed: "..item.qty)
  end
 end)
 local proceed=button(preflight,"Buy",100)
 proceed:SetPoint("BOTTOMLEFT",preflight,"BOTTOMLEFT",35,22)
 local back=button(preflight,"Cancel",100)
 back:SetPoint("BOTTOMRIGHT",preflight,"BOTTOMRIGHT",-35,22)
 back:SetScript("OnClick",function()preflight:Hide()end)
 proceed:SetScript("OnClick",function()
  local offer=selectedOffer and live.offers[selectedOffer]
  local item=selected and AH.Shopping()[selected]
  if not offer or not item or live.id~=selected or live.waiting then return end
  if commodityOrder or awaitingPurchase then
   live.message="Purchase already pending. Wait for the Auction House result."
   preflight:Hide();refreshOffers();return
  end
  if not offer.commodity then
   live.message="Regular auction buyouts remain disabled."
   preflight:Hide();refreshOffers();return
  end
  local needed=math.floor(tonumber(item.qty) or 0)
  local available=math.floor(tonumber(offer.qty) or 0)
  local qty=chainBuy and needed or math.min(needed,available)
  if qty<1 then return end
  local api=C_AuctionHouse
  if not api or type(api.StartCommoditiesPurchase)~="function" then
   live.message="Commodity purchase API unavailable."
   preflight:Hide();refreshOffers();return
  end
  commodityOrder={id=selected,qty=qty,estimated=offer.price*qty}
  api.StartCommoditiesPurchase(selected,qty)
  preflight:Hide()
  live.message="Checking AH price..."
  refreshOffers()
 end)
 preflight:Hide()
 panel.buyOffer=button(right,"Buy Selected",115)
 panel.buyOffer:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-14,12)
 panel.buyOffer:SetEnabled(false)
 panel.buyOffer:SetScript("OnClick",function()
  local offer=selectedOffer and live.offers[selectedOffer]
  local item=selected and AH.Shopping()[selected]
  if not offer or not item or live.id~=selected or live.waiting or commodityOrder or awaitingPurchase then return end
  local qty=chainBuy and item.qty or math.min(item.qty,offer.qty)
  preflightText:SetText(item.name.."\nBuy quantity: "..qty.." / Needed: "..item.qty)
  preflight:Show()
 end)

 resetPurchaseDialogs=function()
  pending=nil
  confirm:Hide()
  preflight:Hide()
 end
 skinPurchaseDialog(confirm,"Confirm Purchase")
 skinPurchaseDialog(preflight,"Purchase Item")
 panel:Hide()
 panel.offset=0
 for i=1,9 do
  local row=CreateFrame("Button",nil,left)
  row:SetHeight(25)
  local highlight=row:CreateTexture(nil,"BACKGROUND")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(.60,.39,.08,.32)
  row.highlight=highlight
  highlight:Hide()
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
 -- Mouse-wheel scrolling keeps larger shopping plans accessible without
 -- the redundant footer page counter and arrow controls.
 left:EnableMouseWheel(true)
 left:SetScript("OnMouseWheel",function(_,delta)
  local maximum=math.max(0,#(panel.items or {})-#rows)
  panel.offset=math.max(0,math.min(maximum,panel.offset-delta))
  update()
 end)
 local function activate()
  hideNative(parent)
  setNativeTitle(parent)
  panel:Show()
  live.message="Select a shopping-list item."
  if not awaitingPurchase then commodityOrder=nil end
  if resetPurchaseDialogs then resetPurchaseDialogs() end
  live.offers={};live.waiting=false;live.elapsed=0;live.id=nil
  selectedOffer=nil;selected=nil
  setTabSelected(true)
  update()
  refreshOffers()
 end
 -- Match the native AH tab click sound, using the client sound kit when
 -- available and the legacy WoW tab-switch sound ID as a fallback.
 local function playTabClick()
  if type(PlaySound)~="function" then return end
  local sound=(SOUNDKIT and (SOUNDKIT.IG_CHARACTER_INFO_TAB or SOUNDKIT.IG_MAINMENU_OPTION)) or 841
  pcall(PlaySound,sound)
 end
 tab:SetScript("OnClick",function()
  playTabClick()
  activate()
 end)
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
 if awaitingPurchase and not purchaseWarningShown then
  purchaseElapsed=purchaseElapsed+.5
  if purchaseElapsed>=20 then
   purchaseWarningShown=true
   live.message="Purchase result delayed. Check your inventory or AH before trying again."
   if refreshOffers then refreshOffers() end
  end
 end
 if live.waiting then
  live.elapsed=live.elapsed+.5
  if live.elapsed>=15 then
   live.waiting=false;live.offers={};selectedOffer=nil
   live.message="Auction search timed out. Select the item again to retry."
   if refreshOffers then refreshOffers() end
  end
 end
 -- Rebuild the shopping list once per second while visible, rather than twice.
 if panel and panel:IsShown() then
  watcher.uiElapsed=(watcher.uiElapsed or 0)+.5
  if watcher.uiElapsed>=1 then watcher.uiElapsed=0;update() end
 else watcher.uiElapsed=0 end
end)

