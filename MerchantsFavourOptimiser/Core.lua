local ADDON = ...
local rows = MFO_DATA
local function money(v)
  if not v then return "?" end
  v = math.floor(v + 0.5)
  return string.format("%dg %ds %dc", math.floor(v/10000), math.floor(v/100)%100, v%100)
end
local function price(id)
  if not id or not Auctionator or not Auctionator.API or not Auctionator.API.v1 or type(Auctionator.API.v1.GetAuctionPriceByItemID)~="function" then return nil end
  local ok, value = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, id)
  if ok and type(value)=="number" and value>0 then return value end
end
-- Stable item IDs avoid depending on the local item-name cache.
-- Unknown IDs are never guessed; they can be learned using the binder.
local knownIDs = {
 ['Copper Ore']=2770, ['Tin Ore']=2771, ['Silver Ore']=2775, ['Iron Ore']=2772, ['Gold Ore']=2776, ['Mithril Ore']=3858,
 ['Copper Bar']=2840, ['Tin Bar']=3576, ['Bronze Bar']=2841, ['Silver Bar']=2842, ['Iron Bar']=3575, ['Steel Bar']=3859, ['Gold Bar']=3577, ['Mithril Bar']=3860,
 ['Linen Cloth']=2589, ['Wool Cloth']=2592, ['Silk Cloth']=4306, ['Mageweave Cloth']=4338,
 ['Light Leather']=2318, ['Medium Leather']=2319, ['Heavy Leather']=4234,
 ['Peacebloom']=2447, ['Silverleaf']=765, ['Earthroot']=2449, ['Mageroyal']=785, ['Briarthorn']=2450,
 ['Stranglekelp']=3820, ['Bruiseweed']=2453, ['Wild Steelbloom']=3355, ['Grave Moss']=3369, ['Kingsblood']=3356,
 ['Liferoot']=3357, ['Fadeleaf']=3818, ['Goldthorn']=3821, ["Khadgar's Whisker"]=3358,
 ['Wintersbite']=3819, ['Firebloom']=4625, ['Purple Lotus']=8831, ["Arthas' Tears"]=8836,
 ['Strange Dust']=10940, ['Greater Magic Essence']=10939, ['Small Glimmering Shard']=10978, ['Large Glimmering Shard']=11084,
 ['Soul Dust']=11083, ['Greater Astral Essence']=11082, ['Small Glowing Shard']=11138, ['Large Glowing Shard']=11139,
 ['Vision Dust']=11137, ['Greater Mystic Essence']=11135, ['Small Radiant Shard']=11177, ['Large Radiant Shard']=11178,
 ['Cured Light Hide']=4231, ['Bolt of Linen Cloth']=2996, ['Bolt of Mageweave']=4339,
 ['Handful of Copper Bolts']=4359, ['Copper Tube']=4361, ['Bronze Tube']=4371, ['Whirring Bronze Gizmo']=4375, ['Bronze Framework']=4382,
 ['Mithril Tube']=10559, ['Unstable Trigger']=10560, ['Mithril Casing']=10561,
 ['Cured Heavy Hide']=4236,
}
-- The game's own name lookup remains a fallback for new Forever-specific items.
-- Learn exact Forever item IDs from items visible in the player's bags.
local function learnBagItems()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink) then return end
  for bag=0,4 do
    for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
      local link=C_Container.GetContainerItemLink(bag,slot)
      if link then
        local id=tonumber(link:match("item:(%d+)"))
        local name=link:match("%[([^%]]+)%]")
        if id and name and MFO_DB and MFO_DB.ids then MFO_DB.ids[name]=id end
      end
    end
  end
end
local function resolve(name)
  if MFO_DB and MFO_DB.ids[name] then return MFO_DB.ids[name] end
  if knownIDs[name] then return knownIDs[name] end
  if C_Item and C_Item.GetItemInfo then
    local _,link = C_Item.GetItemInfo(name)
    if link then
      local id=tonumber(link:match("item:(%d+)"))
      if id and MFO_DB then MFO_DB.ids[name]=id; return id end
    end
  end
end
-- Bank quantities are cached on bank visits; the client does not expose remote bank contents.
local bagCounts={}
local function scanBags()
  bagCounts={}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
  for bag=0,4 do
    for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
      local info=C_Container.GetContainerItemInfo(bag,slot)
      if info and info.itemID then bagCounts[info.itemID]=(bagCounts[info.itemID] or 0)+(info.stackCount or 1) end
    end
  end
end
local function scanBank()
  if not MFO_DB or not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then return end
  local counts={}
  local ids={-1}
  -- WoW Forever bank bag IDs are provided by Enum.BagIndex where available.
  if Enum and Enum.BagIndex then
    for _,key in ipairs({"Bank", "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7", "ReagentBank"}) do
      if type(Enum.BagIndex[key])=="number" then table.insert(ids,Enum.BagIndex[key]) end
    end
  end
  for bag=5,11 do table.insert(ids,bag) end
  local visited={}
  for _,bag in ipairs(ids) do
    if not visited[bag] then
      visited[bag]=true
      local slots=C_Container.GetContainerNumSlots(bag) or 0
      for slot=1,slots do
        local info=C_Container.GetContainerItemInfo(bag,slot)
        if info and info.itemID then counts[info.itemID]=(counts[info.itemID] or 0)+(info.stackCount or 1) end
      end
    end
  end
  MFO_DB.bankCounts=counts
  MFO_DB.bankScanTime=time()
end
local function ownedCount(id)
  if not MFO_DB or not MFO_DB.useOwned then return 0 end
  return (bagCounts[id] or 0)+(MFO_DB.bankCounts and MFO_DB.bankCounts[id] or 0)
end
local function calc(crate)
  local id=crate.id or resolve(crate.name)
  local cratePrice=price(id)
  local crateOwned=ownedCount(id)>0
  local effectiveCrateCost=crateOwned and 0 or cratePrice
  local best,bundleCost,bundleName,missingQty,ownedQty
  for _,b in ipairs(crate.bundles) do
    local itemID=resolve(b.name)
    local have=math.min(b.qty,ownedCount(itemID))
    local missing=b.qty-have
    local unit=price(itemID)
    local cost=(missing==0 and 0) or (unit and unit*missing)
    if cost and (not best or cost<bundleCost) then
      best=true;bundleCost=cost;bundleName=b;missingQty=missing;ownedQty=have
    end
  end
  local rate=effectiveCrateCost and best and (effectiveCrateCost+bundleCost)/crate.favour or nil
  return rate,effectiveCrateCost,bundleName,bundleCost,missingQty,ownedQty,crateOwned
end
local frame=CreateFrame("Frame","MFOFrame",UIParent,"BackdropTemplate")
frame:SetSize(900,440); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart",function(self) self:StartMoving() end); frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)

-- Wood-and-gold frame inspired by the What's Training? profession interface.
local MFO_ART="Interface\\AddOns\\MerchantsFavourOptimiser\\"
frame:SetBackdrop({bgFile=MFO_ART.."MFO_WoodBackground",
  edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",tile=false,edgeSize=22,
  insets={left=8,right=8,top=8,bottom=8}})
frame:SetBackdropColor(1,1,1,.96)
frame:SetBackdropBorderColor(1,1,1,1)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:Hide()

local header=frame:CreateTexture(nil,"ARTWORK")
header:SetTexture(MFO_ART.."MFO_WoodHeader")
header:SetPoint("TOPLEFT",frame,"TOPLEFT",9,-7)
header:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-9,-7)
header:SetHeight(34)
local footer=frame:CreateTexture(nil,"ARTWORK")
footer:SetTexture(MFO_ART.."MFO_WoodHeader")
footer:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",9,7)
footer:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-9,7)
footer:SetHeight(34)
footer:SetTexCoord(0,1,1,0)

local emblem=CreateFrame("Frame",nil,frame)
emblem:SetSize(64,64)
emblem:SetPoint("TOPLEFT",frame,"TOPLEFT",-7,8)
emblem:SetFrameLevel(frame:GetFrameLevel()+5)
local medallion=emblem:CreateTexture(nil,"ARTWORK")
medallion:SetTexture(MFO_ART.."MFO_Medallion")
medallion:SetAllPoints()
local merchantIcon=emblem:CreateTexture(nil,"OVERLAY")
merchantIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
merchantIcon:SetSize(34,34)
merchantIcon:SetPoint("CENTER",emblem,"CENTER",0,0)

local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOP",frame,"TOP",5,-15)
title:SetText("Merchant's Favour Optimiser")
title:SetTextColor(1,.82,.05)
local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
close:SetPoint("TOPRIGHT",-3,-3)
local note=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
note:SetPoint("TOPLEFT",70,-53)
note:SetText("Auctionator scanned prices | 21 crates")
local status=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
status:SetPoint("BOTTOMLEFT",19,16)
status:SetWidth(856)
status:SetJustifyH("LEFT")
local function SkinWoodButton(button)
  local texture=MFO_ART.."MFO_WoodButton"
  button:SetNormalTexture(texture)
  button:SetPushedTexture(texture)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
  local font=button:GetFontString()
  if font then font:SetFontObject(GameFontNormalSmall);font:SetTextColor(1,.83,.12) end
end
local labels={"Crate / cheapest bundle", "Crate", "Mats", "Total", "Favour", "Gold/Fav"}
local xpos={16,390,480,570,660,719}
for i,s in ipairs(labels) do local t=frame:CreateFontString(nil,"OVERLAY","GameFontNormal");t:SetPoint("TOPLEFT",xpos[i],-92);t:SetText(s) end
-- A fixed-height scrolling viewport keeps all 21 rows available without a tall window.
local scrollFrame=CreateFrame("ScrollFrame","MFOCompactScrollFrame",frame,"UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",16,-112)
scrollFrame:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-31,79)
local scrollChild=CreateFrame("Frame",nil,scrollFrame)
scrollChild:SetSize(846,21*19+4)
scrollFrame:SetScrollChild(scrollChild)
-- Preserve Blizzard scrolling mechanics; tint controls to the bronze palette.
local scrollBar=scrollFrame.ScrollBar or _G["MFOCompactScrollFrameScrollBar"]
if scrollBar then
  local up=scrollBar.ScrollUpButton or _G["MFOCompactScrollFrameScrollBarScrollUpButton"]
  local down=scrollBar.ScrollDownButton or _G["MFOCompactScrollFrameScrollBarScrollDownButton"]
  for _,arrow in ipairs({up,down}) do
    if arrow and arrow.GetNormalTexture and arrow:GetNormalTexture() then
      arrow:GetNormalTexture():SetVertexColor(.83,.66,.37)
    end
  end
  local thumb=scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()
  if thumb then thumb:SetVertexColor(.87,.70,.40) end
end
local entries={}
local selectedCrate=nil
local selectButtons={}
local shopButtons={}
local displayedResults={}
for i=1,21 do
  local y=-(i-1)*19
  entries[i]={}
  local hit=CreateFrame("Button",nil,scrollChild)
  hit:SetPoint("TOPLEFT",0,y+2);hit:SetSize(365,18)
  hit:SetScript("OnClick",function()
    local c=hit.crate
    if c then selectedCrate=c; status:SetText("Selected "..c.name..". Shift-click its item link into the box and press Bind item.") end
  end)
  selectButtons[i]=hit
  local shop=CreateFrame("Button",nil,scrollChild,"UIPanelButtonTemplate")
  shop:SetSize(54,18);shop:SetPoint("TOPLEFT",789,y+3);shop:SetText("Shop");SkinWoodButton(shop)
  shop:SetScript("OnClick",function()
    local r=displayedResults[i]
    if not r or not r.b then status:SetText("No priced material bundle for this crate.");return end
    local terms={}
    if not (MFO_DB.useOwned and r.crateOwned) then table.insert(terms,r.crate.name) end
    if not (MFO_DB.useOwned and r.missing==0) then table.insert(terms,r.b.name) end
    if #terms==0 then status:SetText("You already own the crate and all required materials.");return end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and type(Auctionator.API.v1.MultiSearch)=="function" then
      if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) and not (AuctionFrame and AuctionFrame:IsShown()) then
        status:SetText("Open the Auction House, then click Shop to search for the crate and "..r.b.qty.."x "..r.b.name..".")
        return
      end
      local ok,err=pcall(Auctionator.API.v1.MultiSearch,ADDON,terms)
      if ok then status:SetText("Auctionator search: "..r.crate.name.." + "..(r.missing or r.b.qty).."x "..r.b.name..". Buy the indicated quantities.")
      else status:SetText("Auctionator MultiSearch failed: "..tostring(err)) end
    else
      status:SetText("This Auctionator version does not expose MultiSearch. No shopping list was changed.")
    end
  end)
  shopButtons[i]=shop
  for j=1,6 do
    local t=scrollChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetPoint("TOPLEFT",xpos[j]-16,y);t:SetWidth(({365,82,82,82,50,82})[j]);t:SetJustifyH("LEFT");t:SetWordWrap(false)
    entries[i][j]=t
  end
end
local function refresh()
  learnBagItems()
  scanBags()
  local results={};local complete=0;local missingIDs=0;local missingPrices=0
  for _,crate in ipairs(rows) do
    local rate,cp,b,bc,missing,owned,crateOwned=calc(crate)
    if not (crate.id or resolve(crate.name)) then missingIDs=missingIDs+1 elseif cp==nil then missingPrices=missingPrices+1 end
    if rate then complete=complete+1 end
    table.insert(results,{crate=crate,rate=rate,cp=cp,b=b,bc=bc,missing=missing,owned=owned,crateOwned=crateOwned})
  end
  table.sort(results,function(a,b)
    if a.rate and b.rate then return a.rate<b.rate end
    if a.rate then return true end
    if b.rate then return false end
    return a.crate.name<b.crate.name
  end)
  displayedResults=results
  for i,r in ipairs(results) do
    local t=entries[i]
    selectButtons[i].crate=r.crate
    t[1]:SetText(r.crate.name:gsub("Waylaid Crate: ","")..(r.b and (" ("..(MFO_DB.useOwned and ((r.missing or r.b.qty).." to buy / "..(r.owned or 0).." owned") or (r.b.qty.."x")).." "..r.b.name..")") or ""))
    t[2]:SetText(money(r.cp));t[3]:SetText(money(r.bc));t[4]:SetText(money(r.cp and r.bc and (r.cp+r.bc) or nil));t[5]:SetText(r.crate.favour);t[6]:SetText(money(r.rate))
    t[6]:SetTextColor(r.rate and .95 or .6,r.rate and .8 or .6,r.rate and .35 or .6)
  end
  local bankInfo=""
  if MFO_DB.useOwned then
    if MFO_DB.bankScanTime then
      local elapsed=math.max(0,math.floor((time()-MFO_DB.bankScanTime)/3600))
      bankInfo=" Bank snapshot: "..elapsed.."h old."
    else bankInfo=" Bank not scanned yet." end
  end
  status:SetText(complete.."/21 ranked | "..missingIDs.." unknown IDs | "..missingPrices.." missing crate prices. "..(MFO_DB.useOwned and "Owned items deducted." or "All items valued at AH prices.")..bankInfo)
end
local shopHeader=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
shopHeader:SetPoint("TOPLEFT",809,-92);shopHeader:SetText("Shop")
local refreshBtn=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");refreshBtn:SetSize(82,22);refreshBtn:SetPoint("TOPRIGHT",-38,-37);refreshBtn:SetText("Refresh");SkinWoodButton(refreshBtn);refreshBtn:SetScript("OnClick",refresh)
local ownedCheck=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
ownedCheck:SetSize(24,24);ownedCheck:SetPoint("BOTTOMLEFT",475,44)
local ownedLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
ownedLabel:SetPoint("LEFT",ownedCheck,"RIGHT",3,0)
ownedLabel:SetText("Use owned bag / bank items")
ownedCheck:SetScript("OnClick",function(self)
  MFO_DB.useOwned=self:GetChecked() and true or false
  refresh()
end)
local bindLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");bindLabel:SetPoint("BOTTOMLEFT",16,49);bindLabel:SetText("Item link:")
local edit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate");edit:SetSize(205,22);edit:SetPoint("LEFT",bindLabel,"RIGHT",12,0);edit:SetAutoFocus(false)
local bindBtn=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");bindBtn:SetSize(85,22);bindBtn:SetPoint("LEFT",edit,"RIGHT",8,0);bindBtn:SetText("Bind item");SkinWoodButton(bindBtn)
local function bind()
  local s=edit:GetText();local id=tonumber(s:match("item:(%d+)"))
  local name=s:match("%[([^%]]+)%]")
  if not id then status:SetText("Shift-click an item link into the box first.");return end
  if not name and C_Item and C_Item.GetItemInfo then name=C_Item.GetItemInfo(id) end
  if not name then status:SetText("Item name unavailable; hover the item and retry.");return end
  if selectedCrate then
    local expected=selectedCrate.name
    if name~=expected then status:SetText("Link is "..name.."; selected crate is "..expected..". Select matching crate and retry.");return end
    MFO_DB.ids[expected]=id; selectedCrate=nil
  else
    MFO_DB.ids[name]=id
  end
  edit:SetText("");refresh()
end
bindBtn:SetScript("OnClick",bind);edit:SetScript("OnEnterPressed",function(self)bind();self:ClearFocus()end)
-- Lightweight minimap launcher: no external libraries required.
local minimapButton=CreateFrame("Button", "MFOMinimapButton", Minimap)
minimapButton:SetSize(32,32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")
local minimapIcon=minimapButton:CreateTexture(nil,"ARTWORK")
minimapIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
minimapIcon:SetSize(19,19)
minimapIcon:SetPoint("CENTER",0,0)
local minimapBorder=minimapButton:CreateTexture(nil,"OVERLAY")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapBorder:SetSize(54,54)
minimapBorder:SetPoint("TOPLEFT",0,0)
local function positionMinimapButton()
  local angle=math.rad((MFO_DB and MFO_DB.minimapAngle) or 225)
  local radius=80
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*radius,math.sin(angle)*radius)
end
local function updateMinimapDrag()
  if not (GetCursorPosition and Minimap.GetCenter) then return end
  local scale=Minimap:GetEffectiveScale()
  if not scale or scale==0 then return end
  local x,y=GetCursorPosition()
  local cx,cy=Minimap:GetCenter()
  local angle=math.deg(math.atan2(y/scale-cy,x/scale-cx))
  MFO_DB.minimapAngle=angle
  positionMinimapButton()
end
minimapButton:SetScript("OnDragStart",function(self)
  if not MFO_DB then return end
  self:SetScript("OnUpdate",updateMinimapDrag)
end)
minimapButton:SetScript("OnDragStop",function(self)
  self:SetScript("OnUpdate",nil)
end)
minimapButton:SetScript("OnClick",function(_,button)
  if button=="RightButton" then refresh();return end
  if frame:IsShown() then frame:Hide() else refresh();frame:Show() end
end)
minimapButton:SetScript("OnEnter",function(self)
  GameTooltip:SetOwner(self,"ANCHOR_LEFT")
  GameTooltip:AddLine("Merchant's Favour Optimiser",1,.82,.2)
  GameTooltip:AddLine("Left-click: Toggle optimiser",1,1,1)
  GameTooltip:AddLine("Right-click: Refresh prices",1,1,1)
  GameTooltip:AddLine("Drag: Move around minimap",1,1,1)
  GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
positionMinimapButton()
SLASH_MFO1="/mfo";SlashCmdList.MFO=function(msg) if msg=="refresh" then refresh() else if frame:IsShown() then frame:Hide() else refresh();frame:Show() end end end
local events=CreateFrame("Frame");events:RegisterEvent("ADDON_LOADED");events:RegisterEvent("BAG_UPDATE_DELAYED");events:RegisterEvent("BANKFRAME_OPENED");events:RegisterEvent("PLAYERBANKSLOTS_CHANGED");events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
events:SetScript("OnEvent",function(_,event,name)
 if event=="BANKFRAME_OPENED" or event=="PLAYERBANKSLOTS_CHANGED" or event=="PLAYERBANKBAGSLOTS_CHANGED" then scanBank();if frame:IsShown() then refresh() end;return end
 if event=="BAG_UPDATE_DELAYED" then if MFO_DB then learnBagItems();if frame:IsShown() then refresh() end end;return end
 if name~=ADDON then return end
 MFO_DB=MFO_DB or {};MFO_DB.ids=MFO_DB.ids or {};MFO_DB.useSnapshot=nil
 ownedCheck:SetChecked(MFO_DB.useOwned or false)
 positionMinimapButton()
 refresh()
 print("|cffffcc66Merchant's Favour Optimiser|r loaded. Type /mfo")
end)
