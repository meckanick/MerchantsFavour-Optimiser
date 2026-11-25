-- Compare verified Writs and add a selection to MFO Shop.
function MFO_CreateWritTab(parent, skinButton, skinScroll, money, art, readStock, setUseOwned, status, confirmPlannerWrits)
  local panel=CreateFrame("Frame",nil,parent)
  panel:SetPoint("TOPLEFT",parent,"TOPLEFT",12,-76)
  panel:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-12,38)
  panel:Hide()

  local scroll=CreateFrame("ScrollFrame","MFOWritScrollFrame",panel,"UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",0,-83)
  scroll:SetPoint("BOTTOMRIGHT",-28,7)
  local content=CreateFrame("Frame",nil,scroll)
  content:SetSize(866,1)
  scroll:SetScrollChild(content)
  skinScroll(scroll,"MFOWritScrollFrame")

  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate")
  header:SetPoint("TOPLEFT",0,-54)
  header:SetPoint("TOPRIGHT",-28,-54)
  header:SetHeight(26)
  header:SetBackdrop({bgFile=art.."WTP_ProfessionRow"})

  local function button(owner, label, width, height, x, y)
    local control=CreateFrame("Button",nil,owner)
    control:SetSize(width,height)
    control:SetPoint("TOPLEFT",x,y)
    local font=control:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    font:SetPoint("CENTER",control)
    control:SetFontString(font)
    control:SetText(label)
    skinButton(control)
    return control
  end

  local function itemTooltip(control)
    GameTooltip:SetOwner(control,"ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
      GameTooltip:SetItemByID(control.itemID)
    elseif GameTooltip.SetHyperlink then
      GameTooltip:SetHyperlink("item:"..control.itemID)
    end
    if control.description then GameTooltip:AddLine(control.description,1,.82,.2,true) end
    GameTooltip:Show()
  end

  local columns={
    {"name","Writ",215}, {"professions","Profession(s)",124}, {"tierRank","Tier",58},
    {"reputation","Rep",40}, {"writCost","Writ Cost",82}, {"itemCost","Item Cost",82},
    {"total","Total",82}, {"owned","Owned",48}, {"costPerRep","Cost / Rep",117},
  }
  local sortKey, descending="costPerRep",false
  local selectedProfessions, professionButtons={},{}
  local tiers={"All Tiers","Journeyman","Expert","Artisan"}
  local tierIndex, allFactions=1,false
  local expandedID
  local selectedWrits={}
  local rowPool, names, unresolved={},{},{}

  local nameReader=GetItemInfo or (C_Item and C_Item.GetItemInfo)
  local function itemName(id)
    if not names[id] and nameReader then
      local name=nameReader(id)
      names[id]=name
      unresolved[id]=not name or nil
    end
    return names[id]
  end

  local searchLabel=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  searchLabel:SetPoint("TOPLEFT",3,-7)
  searchLabel:SetText("Search")
  local search=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(122,22)
  search:SetPoint("TOPLEFT",51,-2)
  search:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
  search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)

  local function applyFilter()
    scroll:SetVerticalScroll(0)
    panel:Refresh()
  end
  search:SetScript("OnTextChanged",function(_,userInput)
    if userInput then applyFilter() end
  end)

  local professions={}
  for _,writ in ipairs(MFO_WritData) do
    for _,profession in ipairs(writ.professions) do professions[profession]=true end
  end
  local ordered={}
  for profession in pairs(professions) do ordered[#ordered+1]=profession end
  table.sort(ordered)
  local x=184
  for _,profession in ipairs(ordered) do
    local width=math.max(53,#profession*6+9)
    local control=button(panel,profession,width,22,x,-2)
    professionButtons[profession]=control
    control:SetScript("OnClick",function()
      selectedProfessions[profession]=not selectedProfessions[profession] or nil
      applyFilter()
    end)
    x=x+width+3
  end

  local tier=button(panel,tiers[1],94,22,x,-2)
  tier:SetScript("OnClick",function(self)
    tierIndex=tierIndex%#tiers+1
    self:SetText(tiers[tierIndex])
    applyFilter()
  end)
  local faction=button(panel,"Eligible Faction",110,22,x+98,-2)
  faction:SetScript("OnClick",function(self)
    allFactions=not allFactions
    self:SetText(allFactions and "All Factions" or "Eligible Faction")
    applyFilter()
  end)
  local stock=button(panel,"",100,22,x+212,-2)
  stock:SetScript("OnClick",function() setUseOwned(not MFO_DB.useOwned) end)

  local shopOne=button(panel,"Add Open Writ",112,22,0,-27)
  local shopMany=button(panel,"Add Selected (0)",124,22,118,-27)
  local selectionHint=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  selectionHint:SetPoint("TOPLEFT",248,-32)
  selectionHint:SetText("Click to open a Writ  |  Shift-click to select multiple")
  local function selectedIDs()
    local ids={}
    for id in pairs(selectedWrits) do ids[#ids+1]=id end
    table.sort(ids)
    return ids
  end
  if confirmPlannerWrits then
    local confirm=button(panel,"Confirm Daily Availability",168,22,620,-27)
    confirm:SetScript("OnEnter",function(self)
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:AddLine("Confirm Writs for the Favour Planner",1,.82,.2)
      GameTooltip:AddLine("Select only Writ quests you can still turn in today. This replaces the planner's confirmations. With nothing selected or open, it clears them.",1,1,1,true)
      GameTooltip:Show()
    end)
    confirm:SetScript("OnLeave",function() GameTooltip:Hide() end)
    confirm:SetScript("OnClick",function()
      local ids=selectedIDs()
      if #ids==0 and expandedID then ids[1]=expandedID end
      confirmPlannerWrits(ids)
    end)
  end
  local function addToShop(ids)
    if #ids==0 then status:SetText("Choose a Writ first.");return end
    if MFO_AH.RefreshShoppingInventory then MFO_AH.RefreshShoppingInventory() end
    local ok,reason=MFO_AH.AddShoppingWrits(ids,itemName)
    if ok then
      for _,id in ipairs(ids) do selectedWrits[id]=nil end
      panel:Refresh()
    end
    status:SetText(ok and "Writs added. Open MFO Shop at the Auction House." or reason)
  end
  shopOne:SetScript("OnClick",function() addToShop({expandedID}) end)
  shopMany:SetScript("OnClick",function() addToShop(selectedIDs()) end)

  x=0
  for _,column in ipairs(columns) do
    local key=column[1]
    column.x=x
    column.button=button(header,column[2],column[3]-2,24,x,-1)
    column.button:SetScript("OnClick",function()
      descending=sortKey==key and not descending
      sortKey=key
      applyFilter()
    end)
    x=x+column[3]
  end

  local function getLine(index)
    if rowPool[index] then return rowPool[index] end
    local line=CreateFrame("Button",nil,content)
    line:SetSize(848,22)
    line:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    line.shade=line:CreateTexture(nil,"BACKGROUND")
    line.shade:SetAllPoints()
    line.cells={}
    for i,column in ipairs(columns) do
      local cell=line:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
      cell:SetPoint("LEFT",column.x+5,0)
      cell:SetWidth(column[3]-9)
      cell:SetJustifyH("LEFT")
      cell:SetWordWrap(false)
      line.cells[i]=cell
    end
    line:SetScript("OnEnter",itemTooltip)
    line:SetScript("OnLeave",function() GameTooltip:Hide() end)
    line:SetScript("OnClick",function(self)
      if not self.isWrit then return end
      if IsShiftKeyDown and IsShiftKeyDown() then
        if self.eligible then selectedWrits[self.itemID]=not selectedWrits[self.itemID] or nil end
      else
        expandedID=expandedID~=self.itemID and self.itemID or nil
      end
      panel:Refresh()
    end)
    rowPool[index]=line
    return line
  end

  local function matches(id, query)
    local name=itemName(id)
    return (name and name:lower():find(query,1,true)) or tostring(id):find(query,1,true)
  end

  function panel:Refresh()
    if not self:IsVisible() then return end
    local now=time()
    local useOwned=MFO_DB and MFO_DB.useOwned
    stock:SetText(useOwned and "Use Owned: On" or "Use Owned: Off")
    local filter=next(selectedProfessions) and selectedProfessions
    for profession,control in pairs(professionButtons) do
      control:GetFontString():SetTextColor(1,filter and not filter[profession] and .72 or .90,
        filter and filter[profession] and .65 or .16)
      control:SetText(filter and filter[profession] and ("+ "..profession) or profession)
    end
    for _,column in ipairs(columns) do
      column.button:SetText(column[2]..(sortKey==column[1] and (descending and " v" or " ^") or ""))
    end

    local quotes, counts={},{}
    local function quote(id)
      local value=quotes[id]
      if not value then
        -- Match the existing scan-age footer's seven-day stale threshold.
        local copper,stale=MFO_AH.PriceQuote(id,7*86400-1,now)
        value={copper,stale}
        quotes[id]=value
      end
      return value[1],value[2]
    end
    local function count(id)
      if not counts[id] then
        local bags,bank=readStock(id)
        counts[id]={bags,bank}
      end
      return counts[id][1]+counts[id][2]
    end

    local query=search:GetText():lower():match("^%s*(.-)%s*$")
    local playerFaction=UnitFactionGroup and UnitFactionGroup("player")
    local eligible={}
    for _,writ in ipairs(MFO_WritCalculations.available(playerFaction)) do eligible[writ.id]=true end
    local selectedCount=0
    for id in pairs(selectedWrits) do
      if eligible[id] then selectedCount=selectedCount+1 else selectedWrits[id]=nil end
    end
    shopMany:SetText("Add Selected ("..selectedCount..")")
    local results={}
    for _,writ in ipairs(MFO_WritCalculations.available(playerFaction,filter,allFactions)) do
      if tierIndex==1 or writ.tier==tiers[tierIndex] then
        local match=query=="" or matches(writ.id,query)
        if not match then
          for _,item in ipairs(writ.items) do
            if matches(item.id,query) then match=true;break end
          end
        end
        if match then
          local result=MFO_WritCalculations.calculate(writ,quote,useOwned and count or nil)
          result.writ=writ
          result.name=itemName(writ.id) or ("Item #"..writ.id)
          result.professions=table.concat(writ.professions,", ")
          result.tierRank=writ.reputation
          result.owned=math.min(count(writ.id),1)
          for _,item in ipairs(writ.items) do
            result.owned=result.owned+math.min(count(item.id),item.qty)
          end
          results[#results+1]=result
        end
      end
    end
    table.sort(results,function(a,b)
      local left,right=a[sortKey],b[sortKey]
      if left==right then return a.writ.id<b.writ.id end
      -- Unavailable costs stay below priced rows in both directions.
      if left==nil then return false end
      if right==nil then return true end
      if descending then return left>right end
      return left<right
    end)

    local index=0
    local function addLine(id,description,isWrit,values)
      index=index+1
      local line=getLine(index)
      line.itemID,line.description,line.isWrit=id,description,isWrit
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT",0,-(index-1)*22)
      line.shade:SetColorTexture(.40,.33,.27,isWrit and (index%2==0 and .22 or .13) or .45)
      for i,cell in ipairs(line.cells) do cell:SetText(values[i] or "") end
      line.cells[9]:SetTextColor(isWrit and 1 or .95,isWrit and .76 or .95,.65)
      line:Show()
    end
    local function addDetail(id,qty)
      count(id)
      local bags,bank=counts[id][1],counts[id][2]
      local used=useOwned and math.min(qty,bags+bank) or 0
      local needed=qty-used
      local unit,stale=quote(id)
      local quoteText=not unit and "Missing" or stale and "Stale" or money(unit)
      addLine(id, ("Required: %d | Bags: %d | Cached bank: %d | To buy: %d"):format(qty,bags,bank,needed)..
        "\nUnit price: "..quoteText,
        false,{"    "..(itemName(id) or ("Item #"..id)),qty.." required",nil,nil,
          quoteText,needed.." to buy",money(needed==0 and 0 or (unit and not stale and unit*needed or nil)),
          used.." used"})
    end

    local valid=0
    for _,result in ipairs(results) do
      local writ=result.writ
      local expanded=writ.id==expandedID
      local missing,stale=#result.missingPrices>0,#result.stalePrices>0
      local rate=missing and (stale and "Missing / Stale" or "Missing Prices") or
        (stale and "Stale Prices" or money(result.costPerRep))
      if result.costPerRep then valid=valid+1 end
      local description=result.name.."\n"..result.professions.." | "..writ.tier.." | "..writ.faction..
        "\nOwned shows how many required units you have. Click to view item costs."
      if result.costPerRep then
        description=description..("\nCost per reputation point: %.3f copper"):format(result.costPerRep)
      end
      if not eligible[writ.id] then description=description.."\nFaction restricted." end
      local prefix=selectedWrits[writ.id] and "[x] " or (expanded and "- " or "+ ")
      addLine(writ.id,description,true,{prefix..result.name,result.professions,
        writ.tier,result.reputation,money(result.writCost),money(result.itemCost),money(result.total),result.owned,rate})
      rowPool[index].eligible=eligible[writ.id]
      if expanded then
        addDetail(writ.id,1)
        for _,item in ipairs(writ.items) do addDetail(item.id,item.qty) end
      end
    end
    for i=index+1,#rowPool do rowPool[i]:Hide() end
    content:SetHeight(math.max(1,index*22))
    scroll:UpdateScrollChildRect()
    local maximum=scroll:GetVerticalScrollRange()
    if scroll:GetVerticalScroll()>maximum then scroll:SetVerticalScroll(maximum) end
    status:SetText(MFO_AH.Market().." | "..valid.."/"..#results.." Writs priced"..
      (#results==0 and " | No matching Writs" or " | Prices expire after 7 days"))
  end

  -- Only redraw for item cache events that can resolve a displayed or searched name.
  local namesChanged
  function panel:ItemInfoReceived(id,success)
    if success and unresolved[id] then namesChanged=true end
  end
  panel:SetScript("OnUpdate",function(self)
    if namesChanged then namesChanged=nil;self:Refresh() end
  end)
  return panel,scroll
end
