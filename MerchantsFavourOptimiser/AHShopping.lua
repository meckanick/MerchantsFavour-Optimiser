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
-- Read-only live search. Do not buy, reserve, or modify shopping quantities.
local live={id=nil,waiting=false,offers={},message="Select an item to search."}
local refreshOffers
local selectedOffer
local function startLiveSearch(id)
 live.id=id;live.offers={};live.waiting=false;selectedOffer=nil
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
    offers[#offers+1]={price=math.ceil(buyout/math.max(1,qty or 1)),qty=qty or 1,legacyIndex=i,buyout=buyout}
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
    if entry and entry.unitPrice then offers[#offers+1]={price=entry.unitPrice,qty=entry.quantity or 1,commodity=true} end
   end
  elseif event=="ITEM_SEARCH_RESULTS_UPDATED" and api.GetNumItemSearchResults and api.GetItemSearchResultInfo then
   local key=api.MakeItemKey and api.MakeItemKey(id) or {itemID=id}
   for i=1,math.min(api.GetNumItemSearchResults(key) or 0,100) do
    local entry=api.GetItemSearchResultInfo(key,i)
    if entry and entry.buyoutAmount and entry.buyoutAmount>0 then
     offers[#offers+1]={price=math.ceil(entry.buyoutAmount/math.max(1,entry.quantity or 1)),qty=entry.quantity or 1,auctionID=entry.auctionID,buyout=entry.buyoutAmount}
    end
   end
  else return end
 end
 table.sort(offers,function(a,b)return a.price<b.price end)
 live.offers=offers;live.waiting=false;selectedOffer=nil
 live.message=#offers>0 and (#offers.." listings found"..(#offers>6 and " (showing 6 lowest)" or "")) or "No live buyout listings found."
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
 -- Always list Waylaid Crates before their required materials.
 -- Prefer the addon crate IDs; the name prefix also covers future crates.
 local crateIDs={}
 for _,crate in ipairs(MFO_DATA or {}) do
  if type(crate.id)=="number" then crateIDs[crate.id]=true end
 end
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
 for _,v in ipairs(items) do
  local price=AH.Price(v.id)
  if price then total=total+price*v.qty end
 end
 panel.total:SetText(#items.." items  |  Estimated total: "..gold(total))
 local current=selected and AH.Shopping()[selected]
 if panel.detail then
  panel.detail:SetText(current and (current.name.."\nRequired quantity: "..current.qty.."\nCached unit price: "..gold(AH.Price(selected)).."\nEstimated total: "..gold((AH.Price(selected) or 0)*current.qty)) or "")
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
   local price=AH.Price(item.id)
   row.cost:SetText(price and gold(price*item.qty) or "No price")
   row:Show()
  else row.highlight:Hide();row:Hide() end
 end
end
local function close()
 if panel then panel:Hide() end
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
 liveHeader:SetPoint("TOPLEFT",right,"TOPLEFT",16,-153)
 liveHeader:SetText("Auction House Listings  |  Unit Price                  Available")
 local liveRows={}
 for i=1,6 do
  local row=CreateFrame("Button",nil,right)
  row:SetHeight(25)
  row:SetPoint("TOPLEFT",right,"TOPLEFT",16,-176-(i-1)*28)
  row:SetPoint("RIGHT",right,"RIGHT",-16,0)
  local label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  label:SetAllPoints(row)
  label:SetJustifyH("LEFT")
  row.label=label
  local highlight=row:CreateTexture(nil,"BACKGROUND")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(.63,.41,.08,.32)
  row.highlight=highlight
  highlight:Hide()
  row:SetScript("OnClick",function()
   if live.offers[i] then selectedOffer=i;refreshOffers() end
  end)
  liveRows[i]=row
 end
 local liveStatus=right:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 liveStatus:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",16,18)
 liveStatus:SetPoint("RIGHT",right,"RIGHT",-16,0)
 liveStatus:SetJustifyH("LEFT")
 liveStatus:SetWordWrap(false)
 refreshOffers=function()
  if not panel or not panel:IsShown() then return end
  liveStatus:SetText(live.message or "")
  for i,row in ipairs(liveRows) do
   local offer=live.offers[i]
   row.label:SetText(offer and (gold(offer.price).."                         x"..offer.qty) or "")
   if offer then row:Show() else row:Hide() end
   if selectedOffer==i then row.highlight:Show() else row.highlight:Hide() end
  end
  if panel.buyOffer then
   panel.buyOffer:SetEnabled(selectedOffer~=nil and live.offers[selectedOffer]~=nil and not live.waiting)
  end
 end
 -- Purchasing always requires selecting a live auction and confirming the
 -- exact quantity and total. Never automatically buy on search or row select.
 local pending
 local confirm=CreateFrame("Frame",nil,panel,"BackdropTemplate")
 confirm:SetSize(360,145)
 confirm:SetPoint("CENTER",panel,"CENTER")
 confirm:SetFrameStrata("DIALOG")
 confirm:SetFrameLevel(panel:GetFrameLevel()+30)
 confirm:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=22,
  insets={left=8,right=8,top=8,bottom=8}})
 local confirmText=confirm:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 confirmText:SetPoint("TOP",confirm,"TOP",0,-22)
 confirmText:SetWidth(320)
 local accept=button(confirm,"Confirm Purchase",135)
 accept:SetPoint("BOTTOMLEFT",confirm,"BOTTOMLEFT",32,20)
 local cancel=button(confirm,"Cancel",85)
 cancel:SetPoint("BOTTOMRIGHT",confirm,"BOTTOMRIGHT",-32,20)
 cancel:SetScript("OnClick",function()pending=nil;confirm:Hide()end)
 accept:SetScript("OnClick",function()
  if not pending then return end
  local order=pending
  pending=nil;confirm:Hide()
  local api=C_AuctionHouse
  local ok=false
  if order.commodity and api and type(api.StartCommoditiesPurchase)=="function" then
   ok=pcall(api.StartCommoditiesPurchase,order.id,order.qty)
   if ok then
    live.message="Purchase started. Confirm the final price in the Auction House if prompted."
   end
  elseif order.auctionID and api and type(api.PlaceBid)=="function" then
   ok=pcall(api.PlaceBid,order.auctionID,order.buyout)
  elseif order.legacyIndex and type(PlaceAuctionBid)=="function" then
   ok=pcall(PlaceAuctionBid,"list",order.legacyIndex,order.buyout)
  end
  if not ok then live.message="Purchase API unavailable or rejected this listing. Please use the native Buy tab." end
  refreshOffers()
 end)
 confirm:Hide()
 panel.buyOffer=button(right,"Buy Selected",110)
 panel.buyOffer:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-14,12)
 panel.buyOffer:SetEnabled(false)
 panel.buyOffer:SetScript("OnClick",function()
  local offer=selectedOffer and live.offers[selectedOffer]
  local item=selected and AH.Shopping()[selected]
  if not offer or not item or live.id~=selected or live.waiting then return end
  local qty=math.min(item.qty,offer.qty)
  if qty<1 then return end
  -- Non-commodity auctions are indivisible stacks.
  if not offer.commodity then qty=offer.qty end
  if not offer.commodity and not offer.auctionID and not offer.legacyIndex then
   live.message="This listing cannot be purchased through the available API."
   refreshOffers();return
  end
  pending={id=selected,qty=qty,commodity=offer.commodity,
   auctionID=offer.auctionID,legacyIndex=offer.legacyIndex,
   buyout=offer.buyout or offer.price*offer.qty}
  confirmText:SetText("Buy "..item.name.." x"..qty.."\nTotal: "..gold(offer.commodity and offer.price*qty or pending.buyout).."\nConfirm this purchase?")
  confirm:Show()
 end)
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
  live.offers={};live.waiting=false;live.id=nil
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
 if panel and panel:IsShown() then update() end
end)
