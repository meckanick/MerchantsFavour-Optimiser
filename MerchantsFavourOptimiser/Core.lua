local ADDON = ...
-- Keep unconfirmed Artisan crate definitions in Data.lua for future activation,
-- but exclude them from the visible table, prices, shopping, and rankings.
local rows = {}
for _, crate in ipairs(MFO_DATA) do
  if not crate.name:find("Artisan", 1, true) then
    rows[#rows + 1] = crate
  end
end
local note -- forward declaration
local knownIDs
local price
local MFO_COIN_GOLD="|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local MFO_COIN_SILVER="|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
local MFO_COIN_COPPER="|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
local function money(v)
  if not v then return "?" end
  v = math.floor(v + 0.5)
  local goldAmount = math.floor(v/10000)
  local silverAmount = math.floor(v/100)%100
  local copperAmount = v%100
  local silverCopper = string.format("%d%s %d%s", silverAmount, MFO_COIN_SILVER, copperAmount, MFO_COIN_COPPER)
  if goldAmount > 0 then
    return string.format("%d%s %s", goldAmount, MFO_COIN_GOLD, silverCopper)
  end
  return silverCopper
end
local scanAgeFooter
local lastScanAgeText,lastScanAgeColor
local function setScanAgeDisplay(text,color)
  -- The visible age usually stays unchanged across multiple refreshes.
  if text~=lastScanAgeText then
    scanAgeFooter:SetText(text)
    lastScanAgeText=text
  end
  if color~=lastScanAgeColor then
    if color=="unknown" then scanAgeFooter:SetTextColor(.65,.65,.65)
    elseif color=="fresh" then scanAgeFooter:SetTextColor(.3,.95,.3)
    elseif color=="recent" then scanAgeFooter:SetTextColor(1,.85,.2)
    elseif color=="old" then scanAgeFooter:SetTextColor(1,.55,.15)
    else scanAgeFooter:SetTextColor(1,.25,.25) end
    lastScanAgeColor=color
  end
end
-- Display the timestamp of the last completed MFO standalone AH scan.
local function updateScanNote()
  local scannedAt=MFO_AH and MFO_AH.LastScan()
  if type(scannedAt)~="number" or scannedAt<=0 then
    setScanAgeDisplay("Last AH Scan: Unknown","unknown")
    return
  end
  local ageSeconds=math.max(0,time()-scannedAt)
  local days=ageSeconds/86400
  local amount,unit
  if ageSeconds<3600 then
    amount=math.max(1,math.floor(ageSeconds/60))
    unit="Minute"
  elseif ageSeconds<86400 then
    amount=math.floor(ageSeconds/3600)
    unit="Hour"
  elseif ageSeconds<604800 then
    amount=math.floor(ageSeconds/86400)
    unit="Day"
  elseif ageSeconds<2592000 then
    amount=math.floor(ageSeconds/604800)
    unit="Week"
  else
    amount=math.floor(ageSeconds/2592000)
    unit="Month"
  end
  local elapsed
  if ageSeconds<60 then
    elapsed="Less Than 1 Minute"
  else
    elapsed=amount.." "..unit..(amount==1 and "" or "s")
  end
  local color=days<1 and "fresh" or days<3 and "recent" or days<7 and "old" or "stale"
  setScanAgeDisplay("Last AH Scan: "..elapsed.." Ago",color)
end
-- Cache repeated item price reads only during a single ranking/planner refresh.
-- Nil prices are cached too; the cache is discarded after refresh.
local refreshPriceCache={}
local priceCacheActive=false
price = function(id)
  if not id or not MFO_AH then return nil end
  if priceCacheActive then
    local cached=refreshPriceCache[id]
    if cached~=nil then return cached~=false and cached or nil end
  end
  local value=MFO_AH.Price(id)
  if priceCacheActive then refreshPriceCache[id]=value==nil and false or value end
  return value
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
 ['Bolt of Woolen Cloth']=2997, ['Bolt of Silk Cloth']=4305, ['Cured Medium Hide']=4233,
 ['Golden Sansam']=13464, ['Sungrass']=8838, ['Blindweed']=8839, ['Ghost Mushroom']=8845, ['Gromsblood']=8846,
 ['Dreamfoil']=13463, ['Mountain Silversage']=13465, ['Plaguebloom']=13466, ['Icecap']=13467,
 ['Truesilver Ore']=7911, ['Thorium Ore']=10620, ['Dark Iron Ore']=11370,
 ['Runecloth']=14047, ['Thick Leather']=4304, ['Rugged Leather']=8170,
 ['Dream Dust']=11176, ['Greater Nether Essence']=11175, ['Small Brilliant Shard']=14343, ['Large Brilliant Shard']=14344,
 ['Bolt of Runecloth']=14048, ['Cured Thick Hide']=8172,
 ['Dark Iron Bar']=11371, ['Truesilver Bar']=6037, ['Thorium Bar']=12359,
 ['Thorium Widget']=15994, ['Truesilver Transformer']=18631, ['Thorium Tube']=16000,
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
        if id and name and MFO_DB and MFO_DB.ids and MFO_DB.ids[name]~=id then
          MFO_DB.ids[name]=id
        end
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
  -- Reuse the snapshot table instead of allocating one on every bag event.
  -- Clear old counts first so removed items never remain counted.
  for id in pairs(bagCounts) do bagCounts[id]=nil end
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
  for bag=0,4 do
    for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
      local info=C_Container.GetContainerItemInfo(bag,slot)
      if info and info.itemID then bagCounts[info.itemID]=(bagCounts[info.itemID] or 0)+(info.stackCount or 1) end
    end
  end
end
-- Reuse the fixed list of Forever bank bag names across bank visits.
local bankBagKeys={"Bank", "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7", "ReagentBank"}
local bankScanIDs={}
local bankVisited={}
local function scanBank()
  if not MFO_DB or not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then return end
  local counts={}
  -- Clear both scratch tables on each scan; bank indices may change.
  for i=#bankScanIDs,1,-1 do bankScanIDs[i]=nil end
  for bag in pairs(bankVisited) do bankVisited[bag]=nil end
  local ids=bankScanIDs
  ids[1]=-1
  -- WoW Forever bank bag IDs are provided by Enum.BagIndex where available.
  if Enum and Enum.BagIndex then
    local bankIndex=Enum.BagIndex
    for _,key in ipairs(bankBagKeys) do
      if type(bankIndex[key])=="number" then ids[#ids+1]=bankIndex[key] end
    end
  end
  for bag=5,11 do ids[#ids+1]=bag end
  for _,bag in ipairs(ids) do
    if not bankVisited[bag] then
      bankVisited[bag]=true
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
-- Independent of Use Owned: completion readiness always reflects actual inventory.
MFO_AH.CrateReadiness=function(entries)
  return MFO_CrateTracking.Evaluate(entries,bagCounts,
    MFO_DB and MFO_DB.bankCounts, MFO_DB and MFO_DB.bankScanTime)
end
MFO_AH.RefreshCrateReadiness=function()
  learnBagItems();scanBags()
  return MFO_AH.CrateReadiness(MFO_AH.ShoppingCratePlan and MFO_AH.ShoppingCratePlan() or {})
end
local function ownedCount(id)
  if not MFO_DB or not MFO_DB.useOwned then return 0 end
  return (bagCounts[id] or 0)+(MFO_DB.bankCounts and MFO_DB.bankCounts[id] or 0)
end
if MFO_AH.SetOwnedReader then MFO_AH.SetOwnedReader(function(id) return ownedCount(id) end) end
MFO_AH.RefreshShoppingInventory=function() learnBagItems();scanBags() end
local function calc(crate)
  return MFO_Calculations.calculate(crate, price, ownedCount, resolve)
end
local frame=CreateFrame("Frame","MFOFrame",UIParent,"BackdropTemplate")
frame:SetSize(918,410); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:EnableMouse(true)
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
footer:SetHeight(28)
footer:SetTexCoord(0,1,1,0)

local emblem=CreateFrame("Frame",nil,frame)
emblem:SetSize(64,64)
emblem:SetPoint("TOPLEFT",frame,"TOPLEFT",-7,8)
emblem:SetFrameLevel(frame:GetFrameLevel()+5)
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
note:SetText("MFO Saved AH Prices | "..#rows.." Crates")
-- Keep the price-age diagnostic available on Refresh hover without occupying the toolbar.
note:Hide()
local status=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
status:SetPoint("BOTTOMLEFT",19,16)
status:SetWidth(550)
status:SetJustifyH("LEFT")
-- Footer scan-age indicator uses the last completed standalone AH scan.
-- The API reports age in days (including fractional days).
scanAgeFooter=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
scanAgeFooter:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-19,16)
scanAgeFooter:SetWidth(290)
scanAgeFooter:SetJustifyH("RIGHT")
scanAgeFooter:SetText("Last AH Scan: Unknown")
scanAgeFooter:SetTextColor(.65,.65,.65)
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
local labels={"Crate (Cheapest Bundle)", "Crate", "Mats", "Total", "Favour", "Net C/F", "Shop"}
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
  textLabel:SetWidth(i==1 and 210 or columnWidths[i]-12)
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
-- A fixed-height scrolling viewport supports every crate without enlarging the window.
local scrollFrame=CreateFrame("ScrollFrame","MFOCompactScrollFrame",frame,"UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-110)
scrollFrame:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-40,45)
local scrollChild=CreateFrame("Frame",nil,scrollFrame)
scrollChild:SetSize(864,#rows*19+4)
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
local rowWidths={341,76,76,76,48,76}
local entries={}
local shopButtons={}
local displayedResults={}
local readinessButtons={}
for i=1,#rows do
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
  local shop=CreateFrame("Button",nil,scrollChild)
  -- Preserve the full-width wood button, align its center with the Shop
  -- heading, and give it breathing room before the scrollbar.
  shop:SetSize(54,18);shop:SetPoint("TOPLEFT",800,y+3);shop:SetText("Shop");SkinWoodButton(shop)
  shop:SetScript("OnClick",function()
    local r=displayedResults[i]
    if not r or not r.b then status:SetText("No Priced Material Bundle for This Crate.");return end
    local items={}
    local crateID=r.crate.id or resolve(r.crate.name)
    local materialID=resolve(r.b.name)
    if crateID then
      items[crateID]={name=r.crate.name,qty=(MFO_DB.useOwned and r.crateOwned) and 0 or 1,requiredQty=1}
    end
    if materialID then
      items[materialID]={name=r.b.name,qty=r.missing or r.b.qty,requiredQty=r.b.qty}
    end
    local ok,reason=MFO_AH.ReplaceShopping(items)
    if ok and crateID and materialID and MFO_AH.SetShoppingCratePlan then
      MFO_AH.SetShoppingCratePlan({{crateID=crateID,materialID=materialID,quantity=1,materialQty=r.b.qty}})
    end
    status:SetText(ok and "Shopping List Replaced. Open MFO Shop at the Auction House." or (reason or "Unable to create shopping list."))
  end)
  shopButtons[i]=shop
  local readiness=CreateFrame("Frame",nil,scrollChild)
  readiness:SetPoint("TOPLEFT",scrollChild,"TOPLEFT",xpos[1]+1,y+2)
  readiness:SetSize(14,16)
  readiness:EnableMouse(true)
  readiness.icon=readiness:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  readiness.icon:SetAllPoints(readiness)
  readiness:SetScript("OnEnter",function(self)
    local record=displayedResults[i] and displayedResults[i].readiness
    if not record then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:AddLine("Crate Readiness - Individual Estimate",1,.82,.2)
    GameTooltip:AddLine("This crate is assessed independently; other crates may share these materials.",.75,.75,.75,true)
    MFO_CrateTracking.AddTooltip(GameTooltip,record)
    GameTooltip:Show()
  end)
  readiness:SetScript("OnLeave",function()GameTooltip:Hide()end)
  readinessButtons[i]=readiness
  -- Net C/F has its own hover target; the crate-name column stays tooltip-free.
  local netHover=CreateFrame("Frame",nil,scrollChild)
  netHover:SetPoint("TOPLEFT",scrollChild,"TOPLEFT",xpos[6]-5,y+2)
  netHover:SetSize(76,18)
  netHover:EnableMouse(true)
  netHover:SetScript("OnEnter",function(self)
    local r=displayedResults[i]
    if not r then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:AddLine("Net Cost per Favour",1,.82,.2)
    GameTooltip:AddLine(r.crate.name,1,1,1)
    GameTooltip:AddLine("Crate Purchase: "..money(r.cp),1,1,1)
    GameTooltip:AddLine("Cheapest Materials: "..money(r.bc),1,1,1)
    local total=r.cp and r.bc and (r.cp+r.bc) or nil
    GameTooltip:AddLine("Total Purchase Cost: "..money(total),1,1,1)
    if r.crate.turnInCopper then
      GameTooltip:AddLine("Turn-In Money (Deducted): -"..money(r.crate.turnInCopper),.35,1,.35)
    else
      GameTooltip:AddLine("Turn-In Money: Unconfirmed",.75,.75,.75)
    end
    local net=total and r.crate.turnInCopper and (total-r.crate.turnInCopper) or nil
    GameTooltip:AddLine("Net Cost: "..money(net),1,.82,.2)
    GameTooltip:AddLine("Favour Awarded: "..tostring(r.crate.favour or "?"),1,1,1)
    GameTooltip:AddLine("Net Cost per Favour: "..money(r.rate),1,.82,.2)
    if r.crate.turnInCopper then
      GameTooltip:AddLine("Turn-In Money Is Beta-Reported, Not Yet Verified In-Game.",.7,.7,.7,true)
    end
    GameTooltip:Show()
  end)
  netHover:SetScript("OnLeave",function() GameTooltip:Hide() end)
  for j=1,6 do
    local t=scrollChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    -- Align numeric values under their existing header labels without moving the headers.
    -- Move only the crate-name text and Shop buttons to match their header labels.
    t:SetPoint("TOPLEFT",xpos[j]+(j==1 and 22 or -5),y);t:SetWidth(rowWidths[j]);t:SetJustifyH("LEFT");t:SetWordWrap(false)
    entries[i][j]=t
  end
end
local planFavour
local function refresh(inventoryFresh)
  -- Clear and reuse the per-refresh price cache rather than allocating a new table.
  for id in pairs(refreshPriceCache) do refreshPriceCache[id]=nil end
  priceCacheActive=true
  updateScanNote()
  -- BAG_UPDATE_DELAYED already refreshed bag IDs and quantities.
  if not inventoryFresh then learnBagItems();scanBags() end
  local results={};local complete=0;local missingIDs=0;local missingPrices=0
  for _,crate in ipairs(rows) do
    local rate,cp,b,bc,missing,owned,crateOwned=calc(crate)
    if not crate.id then
     if not resolve(crate.name) then missingIDs=missingIDs+1 elseif cp==nil then missingPrices=missingPrices+1 end
   elseif cp==nil then missingPrices=missingPrices+1 end
    if rate then complete=complete+1 end
    local readiness
    if b then
      local crateID=crate.id or resolve(crate.name)
      local materialID=resolve(b.name)
      if crateID and materialID then
        readiness=MFO_AH.CrateReadiness({{crateID=crateID,materialID=materialID,
          quantity=1,materialQty=b.qty}})[1]
      end
    end
    results[#results+1]={crate=crate,rate=rate,cp=cp,b=b,bc=bc,missing=missing,owned=owned,crateOwned=crateOwned,readiness=readiness}
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
    local indicator=readinessButtons[i]
    if r.readiness then
      indicator.icon:SetText(MFO_CrateTracking.Symbol(r.readiness.status))
      indicator:Show()
    else indicator:Hide() end
    t[1]:SetText(r.crate.name:gsub("Waylaid Crate: ","")..(r.b and (" ("..(MFO_DB.useOwned and ((r.missing or r.b.qty).." to Buy / "..(r.owned or 0).." Owned") or (r.b.qty.."x")).." "..r.b.name..")") or ""))
    t[2]:SetText(money(r.cp));t[3]:SetText(money(r.bc));t[4]:SetText(money(r.cp and r.bc and (r.cp+r.bc) or nil));t[5]:SetText(r.crate.favour or "?");t[6]:SetText(money(r.rate))
    t[6]:SetTextColor(r.rate and .95 or .6,r.rate and .8 or .6,r.rate and .35 or .6)
  end
  local footerParts={MFO_AH.Market(),complete.."/"..#rows.." Crates"}
  if missingIDs>0 then footerParts[#footerParts+1]=missingIDs.." Unknown IDs" end
  if missingPrices>0 then footerParts[#footerParts+1]=missingPrices.." Missing Prices" end
  if MFO_DB.useOwned then
    footerParts[#footerParts+1]="Using Owned Items"
    if not MFO_DB.bankScanTime then footerParts[#footerParts+1]="Bank Not Scanned" end
  end
  status:SetText(table.concat(footerParts," | "))
  if planFavour then planFavour(true) end
  priceCacheActive=false
end
-- Update the timestamp of MFO's completed standalone scan without requiring a manual refresh.
-- Opening the AH alone does not mark a scan as complete.
local lastScanDisplayUpdate=0
frame:HookScript("OnShow",function() updateScanNote() end)
frame:HookScript("OnUpdate",function(_,elapsed)
  lastScanDisplayUpdate=lastScanDisplayUpdate+elapsed
  if lastScanDisplayUpdate>=30 then
    lastScanDisplayUpdate=0
    updateScanNote()
  end
end)
local refreshBtn=CreateFrame("Button",nil,frame);refreshBtn:SetSize(82,22);refreshBtn:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-38,-44);refreshBtn:SetText("Refresh");SkinWoodButton(refreshBtn);refreshBtn:SetScript("OnClick",function() refresh() end)
-- Inline planner: the target entry lives in the existing toolbar and
-- replaces the rankings table only while a target is entered.
local targetLabel=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
targetLabel:SetText("Favour Needed:")
local targetInput=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
targetInput:SetSize(66,22)
targetInput:SetAutoFocus(false);targetInput:SetNumeric(true)
local planner=CreateFrame("Frame","MFOFavourPlanner",frame)
planner:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-76)
planner:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-38,38)
planner:Hide()
local plannerTitle=planner:CreateFontString(nil,"OVERLAY","GameFontNormal")
plannerTitle:SetPoint("TOPLEFT",12,-7)
plannerTitle:SetText("Cheapest Crate Combination")
plannerTitle:SetTextColor(1,.76,.13)
local clearButton=CreateFrame("Button",nil,frame)
clearButton:SetSize(68,22);clearButton:SetPoint("RIGHT",refreshBtn,"LEFT",-10,0)
targetInput:SetPoint("RIGHT",clearButton,"LEFT",-10,0)
targetLabel:SetPoint("RIGHT",targetInput,"LEFT",-12,0)
clearButton:SetText("Clear");SkinWoodButton(clearButton)
clearButton:SetScript("OnClick",function()
  targetInput:SetText("")
  targetInput:ClearFocus()
  -- SetText is programmatic, so OnTextChanged(userInput) does not run the planner.
  -- Explicitly restore the crate rankings when Clear is clicked.
  planFavour()
end)
local plannerInfo=planner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
plannerInfo:SetPoint("TOPLEFT",12,-37);plannerInfo:SetWidth(810)
plannerInfo:SetJustifyH("LEFT");plannerInfo:SetText("Enter a Favour Target and Click Find Cheapest.")
local plannerSummary=planner:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
plannerSummary:SetPoint("TOPLEFT",12,-60);plannerSummary:SetWidth(810)
plannerSummary:SetJustifyH("LEFT")
local plannerRows={}
for i=1,11 do
  local line=planner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  line:SetPoint("TOPLEFT",15,-87-(i-1)*19)
  line:SetWidth(800);line:SetJustifyH("LEFT")
  plannerRows[i]=line
end
local plannerWarning=planner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
plannerWarning:SetPoint("BOTTOMLEFT",12,40);plannerWarning:SetWidth(810)
plannerWarning:SetJustifyH("LEFT")
plannerWarning:SetText("AH Prices Are Estimates; Turn-In Money Is Beta-Reported.")
local plannerShop=CreateFrame("Button",nil,planner)
plannerShop:SetSize(165,24);plannerShop:SetPoint("BOTTOMRIGHT",-12,9)
plannerShop:SetText("Shop Planned Items");SkinWoodButton(plannerShop)
local plannerShopping=nil
planFavour=function(inventoryFresh)
  -- A previous shopping plan is invalid as soon as its target or prices change.
  plannerShopping=nil
  local raw=targetInput:GetText()
  if raw=="" then
    planner:Hide();subheader:Show();scrollFrame:Show()
    return
  end
  planner:Show();subheader:Hide();scrollFrame:Hide()
  local target=tonumber(targetInput:GetText())
  if not target or target<1 or target>1000 or target~=math.floor(target) then
    plannerInfo:SetText("Enter a Whole-Number Favour Target Between 1 and 1000.")
    plannerSummary:SetText("")
    for _,line in ipairs(plannerRows) do line:SetText("") end
    return
  end
  MFO_DB.plannerTarget=target
  -- refresh() already scanned bags; text edits still need fresh inventory.
  if not inventoryFresh then learnBagItems();scanBags() end
  local options,lookup={},{}
  for _,crate in ipairs(rows) do
    local crateID=crate.id or resolve(crate.name)
    local cratePrice=price(crateID)
    local bestBundle,bestCost,bestID
    for _,bundle in ipairs(crate.bundles) do
      local itemID=resolve(bundle.name)
      local unitPrice=price(itemID)
      if unitPrice and (not bestCost or unitPrice*bundle.qty<bestCost) then
        bestBundle,bestCost,bestID=bundle,unitPrice*bundle.qty,itemID
      end
    end
    if cratePrice and bestBundle and type(crate.favour)=="number" and crate.favour>0 then
      local option={key=crate.name,name=crate.name,id=crateID,favour=crate.favour,
        bundle=bestBundle,materialID=bestID,cratePrice=cratePrice,
        unitPrice=bestCost/bestBundle.qty,
        cost=cratePrice+bestCost-(crate.turnInCopper or 0),turnIn=crate.turnInCopper or 0}
      options[#options+1]=option;lookup[option.key]=option
    end
  end
  local solution,err=MFO_Calculations.plan(target,options)
  if not solution then
    plannerInfo:SetText(err or "No Priced Combination Available.")
    plannerSummary:SetText("")
    for _,line in ipairs(plannerRows) do line:SetText("") end
    plannerShopping=nil
    return
  end
  -- Revalue the combined shopping list once, consuming each owned item only
  -- once even when several crates share materials.
  local function evaluate(sol)
    local demand,details={},{}
    for key,qty in pairs(sol.items) do
      local o=lookup[key]
      if o then
        demand[o.id]=(demand[o.id] or 0)+qty
        demand[o.materialID]=(demand[o.materialID] or 0)+qty*o.bundle.qty
        details[#details+1]={option=o,qty=qty}
      end
    end
    table.sort(details,function(a,b)return a.option.name<b.option.name end)
    local total,terms,shopping=0,{},{}
    for id,qty in pairs(demand) do
      local unitPrice=price(id)
      if not unitPrice then return nil end
      local missing=math.max(0,qty-math.min(qty,ownedCount(id)))
      total=total+missing*unitPrice
      if missing>0 then shopping[id]=missing end
    end
    for _,entry in ipairs(details) do
      total=total-entry.qty*entry.option.turnIn
    end
    return total,details,shopping
  end
  local bestCost,bestDetails,bestShopping=evaluate(solution)
  -- With owned stock enabled, compare alternative seeded combinations.
  -- This improves stock-aware results without treating shared items as
  -- available more than once; it is not a global mixed-inventory guarantee.
  if MFO_DB.useOwned then
    for _,seed in ipairs(options) do
      local candidate=MFO_Calculations.plan(target,options,seed)
      if candidate then
        local cost,details,shopping=evaluate(candidate)
        if cost and (not bestCost or cost<bestCost) then
          solution,bestCost,bestDetails,bestShopping=candidate,cost,details,shopping
        end
      end
    end
  end
  if not bestCost then
    plannerInfo:SetText("Some Required AH Scan Prices Are Missing.")
    plannerSummary:SetText("")
    for _,line in ipairs(plannerRows) do line:SetText("") end
    return
  end
  plannerInfo:SetText("Cheapest Priced Combination"..(MFO_DB.useOwned and " (Owned-Stock Estimate)" or "")..":")
  plannerSummary:SetText("Target: "..target.." | Favour: "..solution.favour..
    " | Net Cost: "..money(bestCost).." | "..#bestDetails.." Crate Types")
  for i,line in ipairs(plannerRows) do
    local entry=bestDetails[i]
    if entry then
      local name=entry.option.name:gsub("Waylaid Crate: ","")
      line:SetText(entry.qty.."x "..name.." ("..entry.option.favour.." Favour Each) — "..entry.option.bundle.qty..
        "x "..entry.option.bundle.name.." per Crate")
    elseif i==11 and #bestDetails>11 then
      line:SetText("Additional Crate Types Not Shown")
    else line:SetText("") end
  end
  local fullDemand={}
  for _,entry in ipairs(bestDetails) do
    local o=entry.option
    fullDemand[o.id]=(fullDemand[o.id] or 0)+entry.qty
    fullDemand[o.materialID]=(fullDemand[o.materialID] or 0)+entry.qty*o.bundle.qty
  end
  plannerShopping={items=bestShopping,details=bestDetails,required=fullDemand}
  plannerWarning:SetText(MFO_DB.useOwned and
    "Owned Items Counted Once; Mixed-Stock Optimisation Is an Estimate. Coin Rewards Are Beta-Reported." or
    "Minimum Net Cost at Current Prices; Turn-In Coin Rewards Are Beta-Reported.")
end
targetInput:SetScript("OnTextChanged",function(self,userInput)if userInput then planFavour() end end)
targetInput:SetScript("OnEnterPressed",function(self)self:ClearFocus();planFavour()end)
targetInput:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
plannerShop:SetScript("OnEnter",function(self)
  if not plannerShopping then return end
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  GameTooltip:AddLine("Planned Shopping Quantities",1,.82,.2)
  local items={}
  for _,entry in ipairs(plannerShopping.details) do
    local o=entry.option
    items[o.id]=o.name
    items[o.materialID]=o.bundle.name
  end
  local sorted={}
  for id,qty in pairs(plannerShopping.items) do sorted[#sorted+1]={id=id,qty=qty,name=items[id] or tostring(id)} end
  table.sort(sorted,function(a,b)return a.name<b.name end)
  for _,item in ipairs(sorted) do GameTooltip:AddLine(item.name.." x "..item.qty,1,1,1) end
  GameTooltip:AddLine("Saved in MFO shopping list; purchases are manual.",.8,.8,.8,true)
  GameTooltip:Show()
end)
plannerShop:SetScript("OnLeave",function()GameTooltip:Hide()end)
plannerShop:SetScript("OnClick",function()
  if not plannerShopping then plannerInfo:SetText("Calculate a Plan First.");return end
  local items={}
  local names={}
  for _,entry in ipairs(plannerShopping.details) do
    local o=entry.option
    names[o.id]=o.name
    names[o.materialID]=o.bundle.name
  end
  for id,required in pairs(plannerShopping.required) do
    items[id]={name=names[id] or tostring(id),qty=plannerShopping.items[id] or 0,requiredQty=required}
  end
  local ok,reason=MFO_AH.ReplaceShopping(items)
  if ok and MFO_AH.SetShoppingCratePlan then
    local cratePlan={}
    for _,entry in ipairs(plannerShopping.details) do
      local o=entry.option
      cratePlan[#cratePlan+1]={crateID=o.id,materialID=o.materialID,
        quantity=entry.qty,materialQty=o.bundle.qty}
    end
    MFO_AH.SetShoppingCratePlan(cratePlan)
  end
  plannerInfo:SetText(ok and "Shopping List Replaced. Open MFO Shop at the Auction House." or (reason or "Unable to create shopping list."))
end)
local ownedCheck=CreateFrame("CheckButton",nil,subheader,"UICheckButtonTemplate")
-- Align the checkbox at the right edge of the first column, before its divider.
ownedCheck:SetSize(22,22);ownedCheck:SetPoint("RIGHT",subheader,"LEFT",374,0)
local ownedLabel=subheader:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
ownedLabel:SetPoint("RIGHT",ownedCheck,"LEFT",-7,0)
ownedLabel:SetWidth(105)
ownedLabel:SetJustifyH("RIGHT")
ownedLabel:SetText("Use Owned")
-- Match the header labels' font size, flags and gold tint.
local headerFont,headerSize,headerFlags=GameFontHighlightSmall:GetFont()
if headerFont and headerSize then ownedLabel:SetFont(headerFont,headerSize+4,headerFlags) end
ownedLabel:SetTextColor(1,.76,.13)
ownedCheck:SetScript("OnEnter",function(self)
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  GameTooltip:AddLine("Use Owned Bag / Bank Items",1,.82,.2)
  GameTooltip:AddLine("Deduct Owned Materials From the Cheapest Bundle Cost.",1,1,1,true)
  GameTooltip:Show()
end)
ownedCheck:SetScript("OnLeave",function() GameTooltip:Hide() end)
-- Mirror the same saved setting inside the planner while the crate subheader is hidden.
local plannerStockToggle=CreateFrame("CheckButton",nil,planner,"UICheckButtonTemplate")
plannerStockToggle:SetSize(22,22)
plannerStockToggle:SetPoint("TOPRIGHT",planner,"TOPRIGHT",-12,-2)
local plannerStockLabel=planner:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
plannerStockLabel:SetPoint("RIGHT",plannerStockToggle,"LEFT",-7,0)
plannerStockLabel:SetText("Use Owned")
if headerFont and headerSize then plannerStockLabel:SetFont(headerFont,headerSize+4,headerFlags) end
plannerStockLabel:SetTextColor(1,.76,.13)
local function updateOwnedSetting(checked)
  MFO_DB.useOwned=checked and true or false
  ownedCheck:SetChecked(MFO_DB.useOwned)
  plannerStockToggle:SetChecked(MFO_DB.useOwned)
  refresh()
end
local function showOwnedTooltip(self)
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  GameTooltip:AddLine("Use Owned Bag / Bank Items",1,.82,.2)
  GameTooltip:AddLine("Deduct Available Bag and Cached Bank Items From the Planner Shopping Cost.",1,1,1,true)
  GameTooltip:Show()
end
plannerStockToggle:SetScript("OnEnter",showOwnedTooltip)
plannerStockToggle:SetScript("OnLeave",function()GameTooltip:Hide()end)
plannerStockToggle:SetScript("OnClick",function(self)updateOwnedSetting(self:GetChecked())end)
ownedCheck:SetScript("OnClick",function(self)updateOwnedSetting(self:GetChecked())end)
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
  GameTooltip:AddLine("Left-Click: Toggle Optimiser",1,1,1)
  GameTooltip:AddLine("Right-Click: Refresh Prices",1,1,1)
  GameTooltip:AddLine("Drag: Move Around Minimap",1,1,1)
  GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
positionMinimapButton()
local scanItemScratch={}
local function scanRelevantItems()
  -- The scanner copies this list into its queue synchronously.
  for id in pairs(scanItemScratch) do scanItemScratch[id]=nil end
  local items=scanItemScratch
  for _,crate in ipairs(rows) do
    items[crate.id]=crate.name
    for _,bundle in ipairs(crate.bundles) do
      local id=resolve(bundle.name)
      if id then items[id]=bundle.name end
    end
  end
  local ok,message=MFO_AH.Scan(items)
  status:SetText(message or (ok and "Scanning" or "Scan unavailable"))

end
local shoppingFrame=CreateFrame("Frame","MFOShoppingFrame",UIParent,"BackdropTemplate")
shoppingFrame:SetSize(400,350);shoppingFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
shoppingFrame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=22,insets={left=8,right=8,top=8,bottom=8}})
shoppingFrame:Hide()
local shoppingTitle=shoppingFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
shoppingTitle:SetPoint("TOP",0,-20);shoppingTitle:SetText("MFO Shopping List")
local shoppingLines={}
for i=1,13 do
  local line=shoppingFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  line:SetPoint("TOPLEFT",20,-45-(i-1)*20);line:SetWidth(355);line:SetJustifyH("LEFT")
  shoppingLines[i]=line
end
local shoppingSortScratch={}
local function showShopping()
  for i=#shoppingSortScratch,1,-1 do shoppingSortScratch[i]=nil end
  local sorted=shoppingSortScratch
  for id,item in pairs(MFO_AH.Shopping()) do
    sorted[#sorted+1]={id=id,name=item.name,qty=item.qty}
  end
  table.sort(sorted,function(a,b)return a.name<b.name end)
  for i,line in ipairs(shoppingLines) do
    local item=sorted[i]
    local price=item and MFO_AH.Price(item.id)
    line:SetText(item and (item.name.." x "..item.qty.." ("..money(price and price*item.qty)..")") or "")
  end
  shoppingFrame:Show()
end
local closeShopping=CreateFrame("Button",nil,shoppingFrame,"UIPanelCloseButton")
closeShopping:SetPoint("TOPRIGHT",0,0)
local clearShopping=CreateFrame("Button",nil,shoppingFrame,"UIPanelButtonTemplate")
clearShopping:SetSize(95,22);clearShopping:SetPoint("BOTTOM",0,15);clearShopping:SetText("Clear List")
clearShopping:SetScript("OnClick",function()MFO_AH.ClearShopping();showShopping()end)
local scanButton=CreateFrame("Button",nil,frame)
scanButton:SetSize(82,22);scanButton:SetPoint("TOPLEFT",frame,"TOPLEFT",76,-44)
scanButton:SetText("Scan AH");SkinWoodButton(scanButton);scanButton:SetScript("OnClick",scanRelevantItems)
scanButton:SetScript("OnEnter",function(self)
  GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
  GameTooltip:AddLine("Scan Auction House",1,.82,.2)
  GameTooltip:AddLine("Active Market: "..MFO_AH.Market(),1,1,1)
  GameTooltip:AddLine("Prices and shopping lists are shared only with characters on this megarealm and faction.",.8,.8,.8,true)
  GameTooltip:Show()
end)
scanButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
-- Dim the crate table while scanning, with a centred radial progress display.
local scanOverlay=CreateFrame("Frame",nil,frame)
scanOverlay:SetPoint("TOPLEFT",scrollFrame,"TOPLEFT",0,0)
scanOverlay:SetPoint("BOTTOMRIGHT",scrollFrame,"BOTTOMRIGHT",0,0)
scanOverlay:SetFrameStrata(frame:GetFrameStrata())
scanOverlay:SetFrameLevel(scrollFrame:GetFrameLevel()+20)
scanOverlay:EnableMouse(true) -- prevent interacting with dimmed rows mid-scan
local scanShade=scanOverlay:CreateTexture(nil,"BACKGROUND")
scanShade:SetAllPoints(scanOverlay)
scanShade:SetColorTexture(0,0,0,.72)
local scanRing=CreateFrame("Frame",nil,scanOverlay)
scanRing:SetSize(130,130)
scanRing:SetPoint("CENTER",scanOverlay,"CENTER",0,4)
local scanSegments={}
local scanSegmentCount=48
for i=1,scanSegmentCount do
  local angle=2*math.pi*(i-1)/scanSegmentCount
  local segment=scanRing:CreateTexture(nil,"ARTWORK")
  segment:SetTexture("Interface\\Buttons\\WHITE8X8")
  segment:SetSize(6,15)
  segment:SetPoint("CENTER",scanRing,"CENTER",math.sin(angle)*51,math.cos(angle)*51)
  if segment.SetRotation then segment:SetRotation(-angle) end
  segment:SetVertexColor(.29,.24,.16,.85)
  scanSegments[i]=segment
end
local scanPercent=scanRing:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
scanPercent:SetPoint("CENTER",scanRing,"CENTER",0,5)
scanPercent:SetText("0%")
local scanCaption=scanRing:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
scanCaption:SetPoint("TOP",scanPercent,"BOTTOM",0,-6)
scanCaption:SetText("Scanning AH")
scanOverlay:Hide()
local scanSummary=CreateFrame("Frame",nil,frame)
scanSummary:SetSize(250,22)
scanSummary:SetPoint("LEFT",scanButton,"RIGHT",12,0)
scanSummary:EnableMouse(true)
local scanSummaryText=scanSummary:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
scanSummaryText:SetPoint("LEFT",scanSummary,"LEFT",0,0)
scanSummaryText:SetJustifyH("LEFT")
scanSummary:Hide()
scanSummary:SetScript("OnEnter",function(self)
  local missing=MFO_AH.Missing()
  GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
  GameTooltip:AddLine("Auction House Scan Results",1,.82,.2)
  if #missing==0 then GameTooltip:AddLine("All searched items were priced.",.4,1,.4)
  else
    GameTooltip:AddLine("No price found for:",1,.55,.4)
    for _,item in ipairs(missing) do GameTooltip:AddLine(item.name.." ("..item.id..")",1,1,1) end
    GameTooltip:AddLine("These items may have no buyout listings.",.7,.7,.7,true)
  end
  GameTooltip:Show()
end)
scanSummary:SetScript("OnLeave",function() GameTooltip:Hide() end)
local lastScanLit=-1
local lastScanPercent=-1
local lastScanSummaryText
local lastScanDisplayMode
local function updateScanProgress()
  local percent,running,priced,total=MFO_AH.Progress()
  percent=math.max(0,math.min(100,tonumber(percent) or 0))
  local shownPercent=math.floor(percent)
  if shownPercent~=lastScanPercent then
    scanPercent:SetText(shownPercent.."%")
    lastScanPercent=shownPercent
  end
  local lit=math.floor(percent*scanSegmentCount/100+.5)
  if lit~=lastScanLit then
    -- Only segments whose state changed need a texture update.
    if lit>lastScanLit then
      for i=math.max(1,lastScanLit+1),lit do
        scanSegments[i]:SetVertexColor(.95,.73,.30,1)
      end
    else
      for i=lit+1,lastScanLit do
        scanSegments[i]:SetVertexColor(.29,.24,.16,.85)
      end
    end
    lastScanLit=lit
  end
  local mode=running and "running" or total>0 and "complete" or "idle"
  if mode~=lastScanDisplayMode then
    -- Visibility only changes when the scan enters a different state.
    if mode=="running" then
      scanSummary:Hide()
      scanOverlay:Show()
    elseif mode=="complete" then
      scanOverlay:Hide()
      scanSummary:Show()
    else
      scanOverlay:Hide()
      scanSummary:Hide()
    end
    lastScanDisplayMode=mode
  end
  if mode=="complete" then
    local missingCount=#MFO_AH.Missing()
    local summary="Scan Complete: "..priced.."/"..total.." Priced"..(missingCount>0 and (" | "..missingCount.." Missing") or "")
    if summary~=lastScanSummaryText then
      scanSummaryText:SetText(summary)
      lastScanSummaryText=summary
    end
  end
  return running
end
MFO_AH.onUpdate=function()
  -- Progress was already sampled for the scan overlay; reuse its running flag.
  local running=updateScanProgress()
  if not running then status:SetText(MFO_AH.Status()) end
  if frame:IsShown() then refresh() end
end
-- Explicit open action for other MFO views (never toggle an already-open window).
MFO_OpenMainWindow=function()
  refresh()
  frame:Show()
end
SLASH_MFO1="/mfo"
SlashCmdList.MFO=function(msg)
  if msg=="refresh" then refresh()
  elseif msg=="scan" then scanRelevantItems()
  elseif msg=="shop" then showShopping()
  else if frame:IsShown() then frame:Hide() else refresh();frame:Show() end end
end
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
   if frame:IsShown() then refresh(true) end
  end
  return
 end
 if name~=ADDON then return end
 MFO_DB=MFO_DB or {};MFO_DB.ids=MFO_DB.ids or {}
 ownedCheck:SetChecked(MFO_DB.useOwned or false)
 plannerStockToggle:SetChecked(MFO_DB.useOwned or false)
 positionMinimapButton()
 refresh()
 print("|cffffcc66Merchant's Favour Optimiser|r loaded. Type /mfo")
end)
