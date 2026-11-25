-- Compare verified Writs and add a selection to MFO Shop.
function MFO_CreateWritTab(parent, skinButton, skinScroll, money, art, readStock, setUseOwned, status)
  local delivery=MFO_WritDelivery
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
    if control.craftEstimate then
      MFO_WritCrafting.Describe(control.craftEstimate,money,GetItemInfo or (C_Item and C_Item.GetItemInfo)
        or function() end,function(line) GameTooltip:AddLine(line,1,.9,.65,true) end)
    end
    GameTooltip:Show()
  end

  local columns={
    {"name","Writ",179}, {"professions","Profession(s)",96}, {"tierRank","Tier",58},
    {"reputation","Rep",40}, {"writCost","Writ Cost",78}, {"itemCost","Item Cost",78},
    {"total","Total",72}, {"owned","Owned",48}, {"costPerRep","Cost / Rep",95},
    {"questLabel","Quest Status",104},
  }
  local sortKey, descending="costPerRep",false
  local selectedProfessions, professionButtons={},{}
  local tiers={"All Tiers","Journeyman","Expert","Artisan"}
  local tierIndex, allFactions=1,false
  local expandedID
  local selectedWrits={}
  local showRoute=false
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
  local craftButton=button(panel,"Crafting: Off",114,22,503,-27)
  craftButton:SetScript("OnClick",function()
    if not MFO_WritCrafting then return end
    MFO_DB.writCrafting=not MFO_WritCrafting.Enabled()
    MFO_AH.RecalculateShopping()
    if MFO_AH.RefreshWritShop then MFO_AH.RefreshWritShop() end
    panel:Refresh()
  end)
  craftButton:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:AddLine("Compare Finished Items With Crafting",1,.82,.2)
    GameTooltip:AddLine("Uses verified recipes learned by this character and fresh auction prices.",1,1,1,true)
    GameTooltip:AddLine("Open your professions to verify known recipes. Run a Writs or Full scan to price the reagents.",1,1,1,true)
    GameTooltip:Show()
  end)
  craftButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
  local routeButton=button(panel,"Delivery Route",108,22,623,-27)
  local markerButton=button(panel,"",112,22,737,-27)
  markerButton:SetScript("OnClick",function()
    MFO_DB.writDeliveryMarkers=not delivery.MarkersEnabled()
    delivery.RefreshMarkers()
    panel:Refresh()
  end)
  local selectionHint=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  selectionHint:SetPoint("TOPLEFT",248,-32)
  selectionHint:SetText("Click to open  |  Shift-click to select")
  local catalogControls={header,shopOne,shopMany,selectionHint,searchLabel,search,tier,faction,stock,craftButton}
  for _,control in pairs(professionButtons) do catalogControls[#catalogControls+1]=control end
  routeButton:SetScript("OnClick",function(self)
    showRoute=not showRoute
    self:SetText(showRoute and "Writ Prices" or "Delivery Route")
    search:ClearFocus()
    GameTooltip:Hide()
    for _,control in ipairs(catalogControls) do
      if showRoute then control:Hide() else control:Show() end
    end
    scroll:SetPoint("TOPLEFT",0,showRoute and -54 or -83)
    applyFilter()
  end)
  local function selectedIDs()
    local ids={}
    for id in pairs(selectedWrits) do ids[#ids+1]=id end
    table.sort(ids)
    return ids
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
    line:SetScript("OnEnter",function(self)
      if self.stop then
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine(delivery.Description(self.stop.point),1,.82,.2)
        for _,id in ipairs(self.stop.writs) do GameTooltip:AddLine(itemName(id) or ("Item #"..id),1,1,1) end
        GameTooltip:AddLine("Click to open zone map",1,.82,.2)
        if delivery.HasTomTom() and delivery.MarkersEnabled() then
          GameTooltip:AddLine("Shift-click to set TomTom arrow",1,.82,.2)
        end
        GameTooltip:Show()
      elseif self.itemID then
        itemTooltip(self)
      end
    end)
    line:SetScript("OnLeave",function() GameTooltip:Hide() end)
    line:SetScript("OnClick",function(self)
      if self.stop then
        if IsShiftKeyDown and IsShiftKeyDown() and delivery.HasTomTom() and delivery.MarkersEnabled() then
          if not delivery.SendToTomTom(self.stop.point) then status:SetText("TomTom waypoint unavailable.") end
        elseif not delivery.OpenMap(self.stop.point) then
          status:SetText("World map unavailable. Use the listed zone and coordinates.")
        end
        return
      end
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

  local function renderLine(index,id,description,isWrit,values,stop)
    local line=getLine(index)
    line.itemID,line.description,line.isWrit,line.stop=id,description,isWrit,stop
    line.craftEstimate=nil
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT",0,-(index-1)*22)
    line.shade:SetColorTexture(.40,.33,.27,isWrit and (index%2==0 and .22 or .13) or .45)
    line.cells[1]:SetWidth(showRoute and 839 or columns[1][3]-9)
    for i,cell in ipairs(line.cells) do cell:SetText(values[i] or "") end
    line.cells[9]:SetTextColor(isWrit and 1 or .95,isWrit and .76 or .95,.65)
    line:Show()
  end

  local function finishLines(index)
    for i=index+1,#rowPool do rowPool[i]:Hide() end
    content:SetHeight(math.max(1,index*22))
    scroll:UpdateScrollChildRect()
    local maximum=scroll:GetVerticalScrollRange()
    if scroll:GetVerticalScroll()>maximum then scroll:SetVerticalScroll(maximum) end
  end

  local function renderRoute()
    local route,missing=delivery.Route()
    local index=0
    for _,stop in ipairs(route) do
      index=index+1
      local writCount=#stop.writs
      renderLine(index,nil,nil,false,{("%d. %s | %d ready"):format(stop.order,
        delivery.Description(stop.point),writCount)},stop)
    end
    if #missing>0 then
      index=index+1
      renderLine(index,nil,nil,false,{"No verified delivery location"})
      for _,id in ipairs(missing) do
        index=index+1
        renderLine(index,id,nil,false,{"    "..(itemName(id) or ("Item #"..id))})
      end
    elseif #route==0 then
      index=1
      renderLine(index,nil,nil,false,{"No Writs ready for delivery"})
    end
    finishLines(index)
    status:SetText("Approximate order | Current zone first | No verified travel paths")
  end

  function panel:RefreshDelivery()
    if showRoute and self:IsVisible() then renderRoute() end
  end

  local function matches(id, query)
    local name=itemName(id)
    return (name and name:lower():find(query,1,true)) or tostring(id):find(query,1,true)
  end

  function panel:Refresh()
    if not self:IsVisible() then return end
    markerButton:SetText(delivery.MarkersEnabled() and "Map Markers: On" or "Map Markers: Off")
    if showRoute then renderRoute();return end
    local now=time()
    local useOwned=MFO_DB and MFO_DB.useOwned
    local craftEnabled=MFO_WritCrafting and MFO_WritCrafting.Enabled()
    local recipes=craftEnabled and MFO_WritCrafting.Recipes() or nil
    craftButton:SetText(craftEnabled and "Crafting: On" or "Crafting: Off")
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
        local bags,bank=readStock(id,true)
        counts[id]={bags,bank}
      end
      return counts[id][1]+counts[id][2]
    end

    local query=search:GetText():lower():match("^%s*(.-)%s*$")
    local playerFaction=UnitFactionGroup and UnitFactionGroup("player")
    local states=MFO_WritTracking.Snapshot()
    local factionEligible,eligible={},{}
    for _,writ in ipairs(MFO_WritCalculations.available(playerFaction)) do
      factionEligible[writ.id]=true
      eligible[writ.id]=MFO_WritTracking.Eligible(states[writ.id])
    end
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
          local result=MFO_WritCalculations.calculate(writ,quote,useOwned and count or nil,recipes)
          result.writ=writ
          result.name=itemName(writ.id) or ("Item #"..writ.id)
          result.professions=table.concat(writ.professions,", ")
          result.tierRank=writ.reputation
          result.owned=math.min(count(writ.id),1)
          for _,item in ipairs(writ.items) do
            result.owned=result.owned+math.min(count(item.id),item.qty)
          end
          local state=states[writ.id]
          local bagsReady=state=="objectives_complete"
            and MFO_WritCalculations.BagRequirementsMet(writ,function(id) return counts[id][1] end)
          result.questLabel=factionEligible[writ.id] and MFO_WritTracking.Label(state,bagsReady) or "Faction Restricted"
          results[#results+1]=result
        end
      end
    end
    table.sort(results,function(a,b)
      if sortKey=="costPerRep" then
        local aDone,bDone=states[a.writ.id]=="completed",states[b.writ.id]=="completed"
        if aDone~=bDone then return bDone end
      end
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
      renderLine(index,id,description,isWrit,values)
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
      description=description.."\nQuest status: "..result.questLabel
      local prefix=selectedWrits[writ.id] and "[x] " or (expanded and "- " or "+ ")
      addLine(writ.id,description,true,{prefix..result.name,result.professions,
        writ.tier,result.reputation,money(result.writCost),money(result.itemCost),money(result.total),result.owned,rate,result.questLabel})
      rowPool[index].eligible=eligible[writ.id]
      rowPool[index].craftEstimate=(result.crafting or result.craftLimited) and result or nil
      if expanded then
        if result.procurement then
          local ids={}
          for id in pairs(result.procurement) do ids[#ids+1]=id end
          table.sort(ids)
          for _,id in ipairs(ids) do addDetail(id,result.procurement[id]) end
        else
          addDetail(writ.id,1)
          for _,item in ipairs(writ.items) do addDetail(item.id,item.qty) end
        end
      end
    end
    finishLines(index)
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
