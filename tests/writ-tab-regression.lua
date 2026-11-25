dofile("MerchantsFavourOptimiser/WritCalculations.lua")
dofile("MerchantsFavourOptimiser/WritTracking.lua")
dofile("MerchantsFavourOptimiser/WritDelivery.lua")
dofile("MerchantsFavourOptimiser/WritTab.lua")

local function writ(id, tier, reputation, faction, professions)
  return {id=id,questID=900+id,daily=true,tier=tier,reputation=reputation,faction=faction,professions=professions,
    items={{id=id+100,qty=2}}}
end
MFO_WritData={
  writ(1,"Journeyman",75,"Both",{"Alchemy","Engineering"}),
  writ(2,"Expert",125,"Alliance",{"Engineering"}),
  writ(3,"Artisan",200,"Horde",{"Leatherworking"}),
  writ(4,"Expert",125,"Both",{"Alchemy"}),
  writ(5,"Artisan",200,"Both",{"Engineering"}),
}
local names={[1]="Writ: Elixir",[2]="Writ: Tube",[3]="Writ: Hide",[4]="Writ: Oil",
  [101]="Elixir",[102]="Copper Tube",[103]="Hide",[104]="Oil",[105]="Trigger"}
local prices={[1]=50,[2]=75,[3]=200,[4]=100,[5]=100,[101]=50,[102]=25,[103]=100}
local updated={[2]=true,[5]=true}
local stock={[1]={1,0},[101]={0,3}}
local currentTime=700000
local added,shift
IsShiftKeyDown=function() return shift end
GetItemInfo=function(id) return names[id] end
UnitFactionGroup=function() return "Alliance" end
UnitName=function() return "Tester" end
GetRealmName=function() return "Test" end
local completed={}
C_QuestLog={
  GetLogIndexForQuestID=function(id) return id end,
  IsComplete=function() return true end,
  IsQuestFlaggedCompleted=function(id) return completed[id]==true end,
}
time=function() return currentTime end
MFO_DB={}
MFO_AH={
  AddShoppingWrits=function(ids,name)
    if ids[1]==3 then return false,"Faction restricted" end
    added=table.concat(ids,",")
    assert(name(ids[1])==names[ids[1]])
    return true
  end,
  Market=function() return "Test Market" end,
  PriceQuote=function(id,maxAge,now)
    assert(maxAge==7*86400-1 and now==currentTime)
    return prices[id],updated[id]
  end,
}

local function noop() end
local methods={}
for _,name in ipairs({"SetPoint","ClearAllPoints","SetSize","SetAutoFocus","ClearFocus",
  "SetBackdrop","SetAllPoints","SetColorTexture","SetJustifyH","SetWordWrap","SetWidth",
  "SetTextColor","SetHighlightTexture","UpdateScrollChildRect"}) do methods[name]=noop end
function methods:SetText(value) self.text=value end
function methods:GetText() return self.text or "" end
function methods:SetFontString(font) self.font=font end
function methods:GetFontString() return self.font end
function methods:SetHeight(height) self.height=height end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:SetVerticalScroll(offset) self.offset=offset end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:GetVerticalScrollRange() return 0 end
function methods:SetScript(event,callback) self[event]=callback end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
local function object(kind,parent)
  local result=setmetatable({kind=kind,parent=parent,children={},shown=true},{__index=methods})
  if parent then parent.children[#parent.children+1]=result end
  return result
end
function methods:CreateFontString() return object("FontString",self) end
function methods:CreateTexture() return object("Texture",self) end
CreateFrame=function(kind,_,parent) return object(kind,parent) end

local tooltipItem
GameTooltip={SetOwner=noop,SetItemByID=function(_,id) tooltipItem=id end,AddLine=noop,Show=noop,Hide=noop}
local parent=object("Frame")
local status=object("FontString")
local panel,scroll
panel,scroll=MFO_CreateWritTab(parent,noop,noop,function(copper) return copper or "?" end,"",
  function(id)
    local counts=stock[id] or {0,0}
    return counts[1],counts[2]
  end,
  function(value) MFO_DB.useOwned=value;panel:Refresh() end,status)
local function find(owner,kind,text)
  for _,child in ipairs(owner.children) do
    if child.kind==kind and (text==nil or child.text==text) then return child end
  end
  error("Missing control: "..(text or kind))
end
local function click(owner,label)
  local button=find(owner,"Button",label)
  button:OnClick()
end
local function ids()
  local visible={}
  for _,row in ipairs(scroll.scrollChild.children) do
    if row.shown and row.isWrit then visible[#visible+1]=row.itemID end
  end
  return table.concat(visible,",")
end

panel:Show()
panel:Refresh()
assert(ids()=="1,2,4,5", "Eligible faction and cheapest valid rate by default")
local rows=scroll.scrollChild.children
assert(rows[1].cells[1].text=="+ Writ: Elixir" and rows[1].cells[2].text=="Alchemy, Engineering")
assert(rows[1].cells[3].text=="Journeyman" and rows[1].cells[4].text==75)
assert(rows[1].cells[5].text==50 and rows[1].cells[6].text==100 and rows[1].cells[7].text==150)
assert(rows[1].cells[8].text==3 and rows[1].cells[9].text==2)
assert(rows[2].cells[9].text=="Stale Prices" and rows[3].cells[9].text=="Missing Prices")
assert(rows[4].cells[9].text=="Missing / Stale")
assert(status.text:find("1/4 Writs priced",1,true))

rows[1]:OnEnter()
assert(tooltipItem==1)
rows[1]:OnClick()
assert(rows[2].itemID==1 and not rows[2].isWrit and rows[3].itemID==101)
assert(rows[3].cells[2].text=="2 required" and rows[3].cells[7].text==100)
rows[3]:OnEnter()
assert(tooltipItem==101 and rows[3].description:find("Cached bank: 3",1,true))
click(panel,"Use Owned: Off")
assert(MFO_DB.useOwned and rows[1].cells[9].text==0 and rows[3].cells[8].text=="2 used")
rows[1]:OnClick()
assert(rows[2].isWrit)

click(panel,"Eligible Faction")
assert(ids()=="1,3,2,4,5")
local header
for _,child in ipairs(panel.children) do
  if child.kind=="Frame" then header=child end
end
click(header,"Cost / Rep ^")
assert(ids()=="3,1,2,4,5", "Descending cost keeps stale and missing rows last")
click(header,"Rep")
assert(ids()=="1,2,4,3,5")

click(panel,"Alchemy")
assert(ids()=="1,4")
click(panel,"Engineering")
assert(ids()=="1,2,4,5", "Matching multiple professions must not duplicate a Writ")
click(panel,"All Tiers")
assert(ids()=="1")
click(panel,"Journeyman")
assert(ids()=="2,4")
local search=find(panel,"EditBox")
search:SetText(" cOpPeR TuBe ")
search:OnTextChanged(true)
assert(ids()=="2", "Search should match required item names case-insensitively")
search:SetText("2")
search:OnTextChanged(true)
assert(ids()=="2", "Writ ID search works with an empty name cache")
search:SetText("no such writ")
search:OnTextChanged(true)
assert(ids()=="" and status.text:find("No matching Writs",1,true))

search:SetText("trigger")
search:OnTextChanged(true)
assert(ids()=="")
click(panel,"Expert")
assert(ids()=="5" and rows[1].cells[1].text=="+ Item #5")
names[5]="Writ: Trigger"
panel:ItemInfoReceived(5,true)
panel:OnUpdate()
assert(rows[1].cells[1].text=="+ Writ: Trigger")
prices[105],updated[5]=100,nil
panel:Refresh()
assert(rows[1].cells[9].text==1.5)
search:SetText("")
search:OnTextChanged(true)
click(panel,"Artisan")
click(panel,"+ Engineering")
click(panel,"+ Alchemy")
local function writRow(id)
  for _,row in ipairs(rows) do
    if row.shown and row.isWrit and row.itemID==id then return row end
  end
  error("Missing Writ "..id)
end
writRow(3):OnClick()
click(panel,"Add Open Writ")
assert(added==nil and status.text=="Faction restricted")
writRow(1):OnClick()
click(panel,"Add Open Writ")
assert(added=="1")
shift=true
writRow(3):OnClick()
writRow(2):OnClick()
writRow(5):OnClick()
assert(writRow(2).cells[1].text=="[x] Writ: Tube")
click(panel,"Add Selected (2)")
assert(added=="2,5")
assert(find(panel,"Button","Add Selected (0)"))
assert(writRow(1).cells[10].text=="Active","bank stock does not make a Writ deliverable")
stock[101]={2,1}
panel:Refresh()
assert(writRow(1).cells[10].text=="Ready for Delivery")
writRow(1):OnClick()
completed[901]=true
panel:Refresh()
assert(writRow(1).cells[10].text=="Completed Today" and find(panel,"Button","Add Selected (0)"))
C_QuestLog=nil
panel:Refresh()
assert(writRow(1).cells[10].text=="Unknown")
local point={id=3134,kind="npc",name="Kzixx",mapID=1431,zone="Duskwood",x=.818,y=.198}
local stop={point=point,order=1,writs={1}}
MFO_WritDelivery.Route=function() return {stop},{2} end
click(panel,"Delivery Route")
assert(rows[1].stop==stop and rows[1].cells[1].text:find("Duskwood (81.8, 19.8)",1,true))
assert(rows[2].cells[1].text=="No verified delivery location" and rows[3].itemID==2)
assert(not search.shown and status.text:find("Approximate order",1,true))
rows[1]:OnClick()
assert(status.text:find("World map unavailable",1,true))
click(panel,"Map Markers: On")
assert(MFO_DB.writDeliveryMarkers==false and MFO_DB.useOwned)
click(panel,"Writ Prices")
assert(search.shown and rows[1].isWrit and not rows[1].stop)
dofile("MerchantsFavourOptimiser/WritCrafting.lua")
MFO_WritCrafting.Recipes=function()
  return {[101]={output=2,reagents={[200]=1},name="Elixir",profession="Alchemy"}}
end
local tip={}
GameTooltip.AddLine=function(_,line) tip[#tip+1]=line end
local shopRefreshes=0
MFO_AH.RecalculateShopping=function() shopRefreshes=shopRefreshes+1 end
MFO_DB.useOwned=false
prices[200],names[200]=3,"Ingredient"
click(panel,"Crafting: Off")
local open=writRow(1)
assert(MFO_DB.writCrafting and shopRefreshes==1 and open.cells[7].text==53)
open:OnEnter()
local text=table.concat(tip,"\n")
assert(text:find("Buy Finished Items: 150",1,true) and text:find("With Crafting: 53",1,true))
assert(text:find("1x Ingredient",1,true) and text:find("Estimated Savings: 97",1,true))
if open.cells[1].text:sub(1,1)=="+" then open:OnClick() end
assert(rows[3].itemID==200 and rows[3].cells[7].text==3,"expanded Writ shows procurement rows")
click(panel,"Crafting: On")
assert(not MFO_DB.writCrafting and shopRefreshes==2 and writRow(1).cells[7].text==150)
print("PASS: Writ tab filters, rankings, costs, tooltips, cache, delivery and crafting controls")
