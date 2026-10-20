-- MFO shopping tab: integrates with the native Auction House without automating purchases.
local AH=MFO_AH
local host,tab,panel,selected
local tabIndex
local nativeTabsHooked=false
local tabSwitchHooked=false
local rows={}
local hiddenPanels={}
local switching=false
local function hideNative(parent)
 wipe(hiddenPanels)
 local candidates={_G.AuctionFrameBrowse,_G.AuctionFrameBid,_G.AuctionFrameAuctions,
  _G.AuctionHouseFrameBrowse,_G.AuctionHouseFrameBuy,_G.AuctionHouseFrameSell,
  _G.AuctionHouseFrameAuctions,_G.AuctionHouseFrameBrowseFrame,
  parent.BrowseFrame,parent.BuyFrame,parent.SellFrame,parent.AuctionsFrame}
 for _,f in pairs(candidates) do
  if f and f~=panel and f.IsShown and f:IsShown() then
   hiddenPanels[#hiddenPanels+1]=f;f:Hide()
  end
 end
end
local function restoreNative()
 for _,f in ipairs(hiddenPanels) do
  if f and f.Show then f:Show() end
 end
 wipe(hiddenPanels)
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
  panel.detail:SetText(current and (current.name.."\\n\\nRequired quantity: "..current.qty.."\\n\\nCached unit price: "..gold(AH.Price(selected)).."\\n\\nEstimated total: "..gold((AH.Price(selected) or 0)*current.qty)) or "Select an item from the shopping list.")
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
 background:SetTexture("Interface\\AuctionFrame\\AuctionHouse")
 background:SetTexCoord(0.02,0.98,0.04,0.95)
 background:SetVertexColor(.48,.43,.36,1)
 local tint=panel:CreateTexture(nil,"BORDER")
 tint:SetAllPoints(panel)
 tint:SetColorTexture(.11,.09,.075,.86)
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
 local left=inset(16,-100,-345,38)
 local right=inset(355,-100,-16,38)
 left:SetFrameLevel(panel:GetFrameLevel()+1)
 right:SetFrameLevel(panel:GetFrameLevel()+1)
 local topbar=panel:CreateTexture(nil,"ARTWORK")
 topbar:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-35)
 topbar:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-35)
 topbar:SetHeight(2)
 topbar:SetColorTexture(.53,.43,.24,.9)
 local header=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
 header:SetPoint("TOP",panel,"TOP",0,-14)
 header:SetText("Merchant's Favour Optimiser - Shopping")
 local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 title:SetPoint("TOPLEFT",left,"TOPLEFT",14,-14)
 title:SetText("Shopping Lists")
 local resultsTitle=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 resultsTitle:SetPoint("TOPLEFT",right,"TOPLEFT",14,-14)
 resultsTitle:SetText("Name")
 local priceTitle=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
 priceTitle:SetPoint("TOPRIGHT",right,"TOPRIGHT",-16,-14)
 priceTitle:SetText("Cached Price")
 local line=panel:CreateTexture(nil,"ARTWORK")
 line:SetPoint("TOPLEFT",right,"TOPLEFT",8,-37)
 line:SetPoint("TOPRIGHT",right,"TOPRIGHT",-8,-37)
 line:SetHeight(1)
 line:SetColorTexture(.43,.41,.37,1)
 local market=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 market:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-24,-53)
 market:SetText(AH.Market())
 panel.total=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 panel.total:SetPoint("TOPLEFT",panel,"TOPLEFT",30,-61)
 local hint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
 hint:SetPoint("TOPLEFT",right,"TOPLEFT",14,-43)
 hint:SetText("Select a material to view its details")
 panel.detail=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 panel.detail:SetPoint("TOPLEFT",right,"TOPLEFT",16,-83)
 panel.detail:SetWidth(430)
 panel.detail:SetJustifyH("LEFT")
 panel:Hide()
 panel.offset=0
 for i=1,9 do
  local row=CreateFrame("Button",nil,panel)
  row:SetHeight(23)
  row:SetPoint("TOPLEFT",left,"TOPLEFT",10,-52-(i-1)*26)
  row:SetPoint("RIGHT",left,"RIGHT",-10,0)
  row.label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  row.label:SetPoint("LEFT",4,0);row.label:SetWidth(240);row.label:SetJustifyH("LEFT")
  row.cost=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  row.cost:SetPoint("RIGHT",-4,0)
  row:SetScript("OnClick",function(self)if self.item then selected=self.item.id;update()end end)
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
 message:SetPoint("BOTTOM",right,"BOTTOM",0,47);message:SetWidth(390)
 find:SetScript("OnClick",function()
  local ok,info=search()
  message:SetText((ok and "|cff66ff66" or "|cffff7777")..info.."|r")
 end)
 local done=button(panel,"Close",75)
 done:SetPoint("LEFT",find,"RIGHT",8,0)
 done:SetScript("OnClick",close)
 local function activate()
  panel:Show()
  tab:SetButtonState("PUSHED",true)
  update()
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
