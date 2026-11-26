MFO_TableStyle={rowHeight=19}
local style=MFO_TableStyle
local MFO_ART="Interface\\AddOns\\MerchantsFavourOptimiser\\"

function style.Header(parent)
  local header=CreateFrame("Frame",nil,parent,"BackdropTemplate")
  header:SetHeight(28)
  header:SetBackdrop({bgFile=MFO_ART.."WTP_ProfessionRow"})
  return header
end

function style.Heading(parent,text,x,width)
  local label=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  label:SetPoint("LEFT",parent,"LEFT",x,0)
  label:SetWidth(width)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  label:SetText(text)
  local font,size,flags=GameFontHighlightSmall:GetFont()
  if font and size then label:SetFont(font,size+4,flags) end
  label:SetTextColor(1,.76,.13)
  return label
end

function style.Divider(header,x)
  local divider=header:CreateTexture(nil,"ARTWORK")
  divider:SetColorTexture(.42,.27,.11,.75)
  divider:SetSize(1,15)
  divider:SetPoint("LEFT",header,"LEFT",x,-1)
end

function style.RowShade(parent,layer)
  local shade=parent:CreateTexture(nil,layer)
  shade:SetTexture(MFO_ART.."WTP_ProfessionRow")
  return shade
end

function style.TintRow(shade,index,hovered,selected)
  if hovered then
    shade:SetVertexColor(.85,.76,.59,.52)
  elseif selected then
    shade:SetVertexColor(.68,.54,.30,.42)
  else
    shade:SetVertexColor(.40,.33,.27,index%2==0 and .22 or .13)
  end
end

function style.RateColor(label,priced)
  label:SetTextColor(priced and .95 or .6,priced and .8 or .6,priced and .35 or .6)
end
