local ADDON = ...
local rows = MFO_DATA
local note -- forward declaration: updateScanNote is defined before the UI font string\nlocal knownIDs\nlocal price
local function money(v)
  if not v then return "?" end
  v = math.floor(v + 0.5)
  return string.format("%dg %ds %dc", math.floor(v/10000), math.floor(v/100)%100, v%100)
end
-- Match What's Training? Professions: use Auctionator's public v1 API for per-item scan age.
local function auctionatorAPI()
  local a = _G.Auctionator
  return type(a) == "table" and type(a.API) == "table" and a.API.v1 or nil
end
local function formatAgeDays(days)
  days = math.floor(days)
  if days == 0 then return "less than 1 day ago" end
  return days .. (days == 1 and " day ago" or " days ago")
end
local function updateScanNote()
  local api = auctionatorAPI()
  if not api or type(api.GetAuctionAgeByItemID) ~= "function" then
    note:SetText("Auctionator scanned prices | 21 crates | Scan age unavailable")
    return
  end
  local oldestAge, checked = nil, 0
  for _, itemID in pairs(knownIDs or {}) do
    local priceValue = price(itemID)
    if priceValue then
      local ok, age = pcall(api.GetAuctionAgeByItemID, ADDON, itemID)
      if ok and type(age) == "number" and age >= 0 then
        checked = checked + 1
        if not oldestAge or age > oldestAge then oldestAge = age end
      end
    end
  end
  if oldestAge then
    note:SetText("Auctionator scanned prices | 21 crates | Oldest price: " .. formatAgeDays(oldestAge))
  else
    note:SetText("Auctionator scanned prices | 21 crates | Scan age unavailable")
  end
end
price = function(id)
  if not id or not Auctionator or not Auctionator.API or not Auctionator.API.v1 or type(Auctionator.API.v1.GetAuctionPriceByItemID)~="function" then return nil end
  local ok, value = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, id)
  if ok and type(value)=="number" and value>0 then return value end
end
-- Stable item IDs avoid depending on the local item-name cache.
-- Unknown IDs are never guessed; they can be learned using the binder.
knownIDs = {
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
  return MFO_Calculations.calculate(crate, price, ownedCount, resolve)
end
local frame=CreateFrame("Frame","MFOFrame",UIParent,"BackdropTemplate")
frame:SetSize(918,440); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart",function(self) self:StartMoving() end); frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)

-- Wood-and-gold frame inspired by the What's Training? profession interface.
local MFO_ART="Interface\\AddOns\\MerchantsFavourOptimiser\\"
frame:SetBackdrop({bgFile=MFO_ART.."MFO_WoodBackground",
  edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",tile=false,edgeSize=22,
  insets={left=8,right=8,top=8,bottom=8}})
frame:SetBackdropColor(1,1,1,1)
frame:SetBackdropBorderColor(1,1,1,1)
-- Render watermark on BORDER above the backdrop, but behind the interface ARTWORK and text.
local coinWatermark=frame:CreateTexture(nil,"BORDER",nil,-8)
coinWatermark:SetTexture(MFO_ART.."MFO_CoinBackground")
coinWatermark:SetPoint("TOPLEFT",frame,"TOPLEFT",9,-8)
coinWatermark:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-9,8)
coinWatermark:SetVertexColor(.78,.68,.54,1)
coinWatermark:SetAlpha(.40)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:Hide()

local header=frame:CreateTexture(nil,"ARTWORK")
header:SetTexture(MFO_ART.."WTP_NativeHeader")
header:SetPoint("TOPLEFT",frame,"TOPLEFT",9,-7)
header:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-9,-7)
header:SetHeight(27)
local footer=frame:CreateTexture(nil,"ARTWORK")
footer:SetTexture(MFO_ART.."WTP_NativeHeader")
footer:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",9,7)
footer:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-9,7)
footer:SetHeight(34)
footer:SetTexCoord(0,1,1,0)

local emblem=CreateFrame("Frame",nil,frame)
emblem:SetSize(64,64)
emblem:SetPoint("TOPLEFT",frame,"TOPLEFT",-7,8)
emblem:SetFrameLevel(frame:GetFrameLevel()+5)
local medallion=emblem:CreateTexture(nil,"ARTWORK")
medallion:SetTexture(nil)
medallion:SetAllPoints()
local merchantIcon=emblem:CreateTexture(nil,"OVERLAY")
merchantIcon:SetTexture(MFO_ART.."MFO_CoinBadge3D")
merchantIcon:SetSize(68,68)
merchantIcon:SetPoint("CENTER",emblem,"CENTER",0,0)

local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOP",frame,"TOP",5,-15)
title:SetText("Merchant's Favour Optimiser")
title:SetTextColor(1,.82,.05)
local close=CreateFrame("Button",nil,frame)
-- Fit the visible X artwork within the 34px wooden header, rather than
-- sizing the entire UIPanelCloseButton template to the header height.
close:SetSize(30,30)
close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-2,-3)
close:SetNormalTexture(MFO_ART.."WTP_NativeClose")
close:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
close:SetFrameLevel(frame:GetFrameLevel()+10)
close:SetScript("OnClick",function() frame:Hide() end)
note=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
note:SetPoint("TOPLEFT",70,-53)
note:SetText("Auctionator scanned prices | 21 crates")
local status=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
status:SetPoint("BOTTOMLEFT",19,16)
status:SetWidth(856)
status:SetJustifyH("LEFT")
-- Recessed bronze controls matching the profession panel's visual language.
-- Same textured button artwork and font treatment as What's Training? Professions.
local function SkinWoodButton(button)
  local texture=MFO_ART.."WTP_FooterButton"
  button:SetNormalTexture(texture)
  button:SetPushedTexture(texture)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
  local font=button:GetFontString()
  if font then font:SetFontObject(GameFontNormalSmall);font:SetTextColor(1,.82,.05) end
end
local labels={"Crate / cheapest bundle", "Crate", "Mats", "Total", "Favour", "Gold/Fav", "Shop"}
local xpos={16,390,480,570,660,719,809}
local columnWidths={374,90,90,90,59,90,57}
local subheader=CreateFrame("Frame",nil,frame,"BackdropTemplate")
-- Stretch the subheading texture between the inner gold frame borders.
-- No separate brown outline: the window's own gold trim defines its edges.
subheader:SetPoint("TOPLEFT",frame,"TOPLEFT",8,-76)
subheader:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-8,-76)
subheader:SetHeight(28)
subheader:SetBackdrop({bgFile=MFO_ART.."WTP_ProfessionRow"})
subheader:SetBackdropColor(1,1,1,1)
for i,label in ipairs(labels) do
  local textLabel=subheader:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  textLabel:SetPoint("LEFT",subheader,"LEFT",xpos[i]-8+(i==1 and 16 or 7),0)
  textLabel:SetWidth(columnWidths[i]-(i==1 and 22 or 12))
  textLabel:SetJustifyH("LEFT")
  textLabel:SetText(label)
  -- Keep the headers exactly four font points above the row text.
  local bodyFont,bodySize,bodyFlags=GameFontHighlightSmall:GetFont()
  if bodyFont and bodySize then
    textLabel:SetFont(bodyFont,bodySize+4,bodyFlags)
  end
  textLabel:SetTextColor(1,.76,.13)
  if i>1 then
    local divider=subheader:CreateTexture(nil,"ARTWORK")
    divider:SetColorTexture(.42,.27,.11,.75)
    divider:SetSize(1,15)
    divider:SetPoint("LEFT",subheader,"LEFT",xpos[i]-8,-1)
  end
end
-- A fixed-height scrolling viewport keeps all 21 rows available without a tall window.
local scrollFrame=CreateFrame("ScrollFrame","MFOCompactScrollFrame",frame,"UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-110)
scrollFrame:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-40,79)
local scrollChild=CreateFrame("Frame",nil,scrollFrame)
scrollChild:SetSize(864,21*19+4)
scrollFrame:SetScrollChild(scrollChild)
-- Preserve Blizzard scrolling mechanics; tint controls to the bronze palette.
local scrollBar=scrollFrame.ScrollBar or _G["MFOCompactScrollFrameScrollBar"]
if scrollBar then
  local up=scrollBar.ScrollUpButton or _G["MFOCompactScrollFrameScrollBarScrollUpButton"]
  local down=scrollBar.ScrollDownButton or _G["MFOCompactScrollFrameScrollBarScrollDownButton"]
  local thumb=scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()
  if up then
    up:SetSize(14,14)
    up:SetNormalTexture(MFO_ART.."WTP_ScrollUp")
    up:SetPushedTexture(MFO_ART.."WTP_ScrollUp")
    up:SetDisabledTexture(MFO_ART.."WTP_ScrollUp")
    up:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
  end
  if down then
    down:SetSize(14,14)
    down:SetNormalTexture(MFO_ART.."WTP_ScrollDown")
    down:SetPushedTexture(MFO_ART.."WTP_ScrollDown")
    down:SetDisabledTexture(MFO_ART.."WTP_ScrollDown")
    down:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
  end
  local track=scrollBar:CreateTexture(nil,"BACKGROUND")
  track:SetTexture(MFO_ART.."WTP_ScrollTrack")
  track:SetWidth(10)
  track:SetPoint("TOP",up or scrollBar,"BOTTOM",0,-1)
  track:SetPoint("BOTTOM",down or scrollBar,"TOP",0,1)
  local grip,gripGlow
  if thumb then
    thumb:SetTexture(MFO_ART.."WTP_ScrollThumb")
    thumb:SetWidth(10)
    grip=scrollBar:CreateTexture(nil,"ARTWORK")
    grip:SetTexture(MFO_ART.."WTP_ScrollThumb")
    grip:SetWidth(10)
    grip:SetHeight(120)
    thumb:SetAlpha(0)
  end
  local function MakeGlow(target,texture)
    if not target then return nil end
    -- Arrow glows must be on their button's own OVERLAY layer.
    -- Scrollbar-parent textures render behind child button artwork.
    -- The decorative grip is a Texture, so it still uses the bar.
    local owner=(target==up or target==down) and target or scrollBar
    local glow=owner:CreateTexture(nil,"OVERLAY")
    glow:SetAllPoints(target)
    glow:SetTexture(MFO_ART..texture)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(.22)
    glow:Hide()
    return glow
  end
  local upGlow=MakeGlow(up,"WTP_ScrollUp")
  local downGlow=MakeGlow(down,"WTP_ScrollDown")
  if grip then gripGlow=MakeGlow(grip,"WTP_ScrollThumb") end
  local function ToggleGlow(glow,active)
    if glow then if active then glow:Show() else glow:Hide() end end
  end
  local function SetGrey(button,grey)
    if not button then return end
    for _,method in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture"}) do
      local texture=button[method] and button[method](button)
      if texture and texture.SetDesaturated then texture:SetDesaturated(grey) end
    end
  end
  local dragging=false
  scrollBar:HookScript("OnMouseDown",function(_,button)
    if button=="LeftButton" then dragging=true end
  end)
  scrollBar:HookScript("OnMouseUp",function(_,button)
    if button=="LeftButton" then dragging=false end
  end)
  local function UpdateScrollAppearance()
    if dragging and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then dragging=false end
    local minimum,maximum=scrollBar:GetMinMaxValues()
    minimum,maximum=minimum or 0,maximum or 0
    local value=scrollBar:GetValue() or 0
    local canUp=value>minimum+.5
    local canDown=value<maximum-.5
    SetGrey(up,not canUp)
    SetGrey(down,not canDown)
    ToggleGlow(upGlow,canUp and up and up:IsMouseOver())
    ToggleGlow(downGlow,canDown and down and down:IsMouseOver())
    if grip and thumb then
      local topEdge=up and up:GetBottom()
      local bottomEdge=down and down:GetTop()
      local barBottom=scrollBar:GetBottom()
      if topEdge and bottomEdge and barBottom then
        topEdge,bottomEdge=topEdge-2,bottomEdge+2
        local trackHeight=topEdge-bottomEdge
        if trackHeight>0 then
          local gripHeight=math.min(120,trackHeight)
          local fraction=maximum>minimum and math.max(0,math.min(1,(value-minimum)/(maximum-minimum))) or 0
          local centerY=topEdge-gripHeight/2-fraction*(trackHeight-gripHeight)
          if grip:GetHeight()~=gripHeight then grip:SetHeight(gripHeight) end
          grip:ClearAllPoints()
          grip:SetPoint("CENTER",scrollBar,"BOTTOM",0,centerY-barBottom)
          if thumb:IsShown() then grip:Show() else grip:Hide() end
        else grip:Hide() end
      else grip:Hide() end
      local gripHover=false
      if grip:IsShown() and GetCursorPosition then
        local cx,cy=GetCursorPosition()
        local scale=scrollBar:GetEffectiveScale()
        if scale and scale>0 then
          cx,cy=cx/scale,cy/scale
          local l,r,b,t=grip:GetLeft(),grip:GetRight(),grip:GetBottom(),grip:GetTop()
          gripHover=l and r and b and t and cx>=l and cx<=r and cy>=b and cy<=t or false
        end
      end
      ToggleGlow(gripGlow,thumb:IsShown() and maximum>minimum and (gripHover or thumb:IsMouseOver() or dragging))
    end
  end
  -- OnUpdate is supported by the Forever UI; don't hook the unsupported
  -- OnScrollRangeChanged script (which stopped the addon loading in v0.1.22).
  scrollBar:HookScript("OnUpdate",UpdateScrollAppearance)
  UpdateScrollAppearance()
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
  local rowShade=scrollChild:CreateTexture(nil,"BACKGROUND")
  rowShade:SetTexture(MFO_ART.."WTP_ProfessionRow")
  rowShade:SetVertexColor(.40,.33,.27,i%2==0 and .22 or .13)
  rowShade:SetPoint("TOPLEFT",scrollChild,"TOPLEFT",0,y+2)
  rowShade:SetSize(861,19)
  hit:SetPoint("TOPLEFT",0,y+2);hit:SetSize(365,18)
  hit:SetScript("OnEnter",function() rowShade:SetVertexColor(.85,.76,.59,.52) end)
  hit:SetScript("OnLeave",function() rowShade:SetVertexColor(.40,.33,.27,i%2==0 and .22 or .13) end)
  hit:SetScript("OnClick",function()
    local c=hit.crate
    if c then selectedCrate=c; status:SetText("Selected "..c.name..". Shift-click its item link into the box and press Bind item.") end
  end)
  selectButtons[i]=hit
  local shop=CreateFrame("Button",nil,scrollChild)
  -- Preserve the full-width wood button, align its center with the Shop
  -- heading, and give it breathing room before the scrollbar.
  shop:SetSize(54,18);shop:SetPoint("TOPLEFT",800,y+3);shop:SetText("Shop");SkinWoodButton(shop)
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
    -- Align numeric values under their existing header labels without moving the headers.
    -- Move only the crate-name text and Shop buttons to match their header labels.
    t:SetPoint("TOPLEFT",xpos[j]+(j==1 and 8 or -5),y);t:SetWidth(({341,76,76,76,48,76})[j]);t:SetJustifyH("LEFT");t:SetWordWrap(false)
    entries[i][j]=t
  end
end
local function refresh()
  updateScanNote()
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
local refreshBtn=CreateFrame("Button",nil,frame);refreshBtn:SetSize(82,22);refreshBtn:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-38,-44);refreshBtn:SetText("Refresh");SkinWoodButton(refreshBtn);refreshBtn:SetScript("OnClick",refresh)
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
local bindBtn=CreateFrame("Button",nil,frame);bindBtn:SetSize(85,22);bindBtn:SetPoint("LEFT",edit,"RIGHT",8,0);bindBtn:SetText("Bind item");SkinWoodButton(bindBtn)
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
minimapIcon:SetTexture(MFO_ART.."MFO_CoinBadge3D")
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
local events=CreateFrame("Frame")
local function registerSupportedEvent(eventName)
  -- Some retail events do not exist in WoW Forever. Never let one optional
  -- registration failure prevent the addon from loading.
  local ok=pcall(events.RegisterEvent,events,eventName)
  if not ok then
    print("|cffffcc66Merchant's Favour Optimiser|r skipped unsupported event: "..eventName)
  end
end
registerSupportedEvent("ADDON_LOADED")
registerSupportedEvent("BAG_UPDATE_DELAYED")
registerSupportedEvent("BANKFRAME_OPENED")
registerSupportedEvent("PLAYERBANKSLOTS_CHANGED")
events:SetScript("OnEvent",function(_,event,name)
 if event=="BANKFRAME_OPENED" then scanBank();if frame:IsShown() then refresh() end;return end
 if event=="PLAYERBANKSLOTS_CHANGED" then
  -- Only scan live bank containers while the bank UI is open; retain the last
  -- valid snapshot after closing because remote bank contents are unavailable.
  local bank=BankFrame or _G.BankFrame
  if bank and bank.IsShown and bank:IsShown() then scanBank();if frame:IsShown() then refresh() end end
  return
 end
 if event=="BAG_UPDATE_DELAYED" then
  if MFO_DB then
   learnBagItems();scanBags()
   local bank=BankFrame or _G.BankFrame
   if bank and bank.IsShown and bank:IsShown() then scanBank() end
   if frame:IsShown() then refresh() end
  end
  return
 end
 if name~=ADDON then return end
 MFO_DB=MFO_DB or {};MFO_DB.ids=MFO_DB.ids or {};MFO_DB.useSnapshot=nil
 ownedCheck:SetChecked(MFO_DB.useOwned or false)
 positionMinimapButton()
 refresh()
 print("|cffffcc66Merchant's Favour Optimiser|r loaded. Type /mfo")
end)
