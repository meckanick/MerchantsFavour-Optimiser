-- Shared tab skin for standalone views and the legacy Auction House.
function MFO_CreateWoodTab(parent,label,width)
  local tab=CreateFrame("Button",nil,parent,"BackdropTemplate")
  tab:SetWidth(width)
  tab:SetBackdrop({
    bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=false,edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3}
  })
  local tabText=tab:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  tabText:SetPoint("CENTER",tab,"CENTER",0,0)
  tab:SetFontString(tabText)
  tab:SetText(label)

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

  local function setSelected(active)
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
  setSelected(false)
  return tab,setSelected
end

function MFO_CreateWindowTab(parent,label)
  -- The Auction House display-mode tab inherits this button template.
  if type(PanelTemplates_SelectTab)=="function" and type(PanelTemplates_DeselectTab)=="function" then
    local ok,tab=pcall(CreateFrame,"Button",nil,parent,"PanelTabButtonTemplate")
    if ok and tab then
      tab:SetText(label)
      if type(PanelTemplates_TabResize)=="function" then
        PanelTemplates_TabResize(tab,20,nil,70)
      else
        tab:SetWidth(94)
      end
      PanelTemplates_DeselectTab(tab)
      return tab,function(active)
        if active then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
      end
    end
  end
  return MFO_CreateWoodTab(parent,label,94)
end
