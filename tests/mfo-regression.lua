-- Run from repository root with Lua 5.1:
-- lua5.1 tests/mfo-regression.lua
dofile("MerchantsFavourOptimiser/Data.lua")
dofile("MerchantsFavourOptimiser/Calculations.lua")

local function check(condition, message)
  if not condition then error("FAIL: " .. message, 2) end
end
local function equal(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected) ..
    ", got " .. tostring(actual) .. ")")
end

equal(#MFO_DATA, 30, "there must be exactly 30 crate definitions")
-- Artisan definitions are retained for future verification but hidden in the UI.
local visibleCount, artisanCount = 0, 0
for _, crate in ipairs(MFO_DATA) do
  if crate.name:find("Artisan", 1, true) then
    artisanCount = artisanCount + 1
    check(crate.favour == nil, crate.name .. " must not invent an Artisan reward")
  else
    visibleCount = visibleCount + 1
  end
end
equal(artisanCount, 8, "eight unconfirmed Artisan definitions must be retained")
equal(visibleCount, 22, "exactly 22 confirmed-tier crates should remain visible")
local expectedCoin = {
  Apprentice = {[5] = 250, [10] = 500},
  Journeyman = {[10] = 500, [20] = 1000},
  Expert = {[15] = 750, [30] = 1500},
}
for _, c in ipairs(MFO_DATA) do
  if c.name:find("Artisan", 1, true) then
    equal(c.turnInCopper, nil, "Artisan coin rewards must remain unverified")
  else
    local tier = c.name:match("Apprentice") or c.name:match("Journeyman") or c.name:match("Expert")
    check(tier ~= nil, c.name .. " must have a known tier")
    equal(c.turnInCopper, expectedCoin[tier][c.favour], c.name .. " reported coin reward")
  end
end
local netTestCrate = {id=9001, name="Net payout test", favour=10, turnInCopper=500,
  bundles={{name="Test Material",qty=1}}}
local netRate = MFO_Calculations.calculate(netTestCrate,
  function(id) return id == 9001 and 1000 or 1000 end,
  function() return 0 end,
  function() return 101 end)
equal(netRate, 150, "net gold per Favour must deduct turn-in money")
netTestCrate.turnInCopper = 2500
netRate = MFO_Calculations.calculate(netTestCrate,
  function() return 1000 end, function() return 0 end, function() return 101 end)
equal(netRate, -50, "turn-in coin reward may exceed purchase cost")
local ids, names = {}, {}
for _, crate in ipairs(MFO_DATA) do
  check(type(crate.name) == "string" and crate.name ~= "", "crate name must exist")
  check(type(crate.id) == "number" and crate.id > 0, crate.name .. " must have a valid item ID")
  check(not ids[crate.id], "duplicate crate item ID " .. tostring(crate.id))
  check(not names[crate.name], "duplicate crate name " .. crate.name)
  ids[crate.id], names[crate.name] = true, true
  check(crate.favour == nil or (type(crate.favour) == "number" and crate.favour > 0), crate.name .. " must have positive or unverified favour")
  check(type(crate.bundles) == "table" and #crate.bundles > 0, crate.name .. " must have bundles")
  for _, bundle in ipairs(crate.bundles) do
    check(type(bundle.name) == "string" and bundle.name ~= "", crate.name .. " has unnamed material")
    check(type(bundle.qty) == "number" and bundle.qty > 0 and bundle.qty == math.floor(bundle.qty),
      crate.name .. " has invalid quantity for " .. tostring(bundle.name))
  end
end

local textile, fabrics, unverified
for _, c in ipairs(MFO_DATA) do
  if c.id == 248688 then textile = c end
  if c.id == 248705 then fabrics = c end
  if c.name == 'Waylaid Crate: Artisan Ore' then unverified = c end
end
check(textile ~= nil and textile.bundles[1].qty == 20, "Journeyman Textiles must require 20 Wool Cloth")
check(fabrics ~= nil and fabrics.favour == 20, "Journeyman Fabrics must reward 20 Favour")
check(unverified ~= nil and unverified.favour == nil, "Artisan reward must remain unverified")

local crate = {
  name = "Test Crate", id = 9001, favour = 10,
  bundles = {
    {name = "Material A", qty = 20},
    {name = "Material B", qty = 2},
  },
}
local prices = {[9001] = 1000, [101] = 100, [102] = 500}
local owned = {}
local idsByName = {["Material A"] = 101, ["Material B"] = 102}
local function getPrice(id) return prices[id] end
local function getOwned(id) return owned[id] or 0 end
local function resolve(name) return idsByName[name] end

local rate, crateCost, bundle, bundleCost, missing, have, crateOwned =
  MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(crateCost, 1000, "crate cost should use the market price")
equal(bundle.name, "Material B", "cheapest complete bundle should be selected")
equal(bundleCost, 1000, "bundle cost should include required quantities")
equal(missing, 2, "missing quantity should be returned")
equal(have, 0, "owned quantity should start at zero")
equal(crateOwned, false, "crate should not be marked owned")
equal(rate, 200, "gold per favour should be total cost divided by favour")

owned[101], owned[102], owned[9001] = 5, 1, 1
rate, crateCost, bundle, bundleCost, missing, have, crateOwned =
  MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(crateCost, 0, "owned crate should have zero purchase cost")
equal(bundle.name, "Material B", "owned quantities should be accounted for")
equal(bundleCost, 500, "only missing material quantity should be costed")
equal(missing, 1, "missing material quantity should reflect owned items")
equal(have, 1, "owned material quantity should be reported")
equal(crateOwned, true, "owned crate should be marked owned")
equal(rate, 50, "owned crate and remaining materials should affect rate")

prices[101], prices[102] = nil, nil
owned[101], owned[102], owned[9001] = 0, 0, 0
rate = MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(rate, nil, "unknown required prices must not be treated as zero")

-- If all required materials are owned, material cost is known to be zero
-- even if their current Auctionator prices are unavailable.
prices[101] = 100
owned[101], owned[102] = 20, 2
rate, crateCost, bundle, bundleCost = MFO_Calculations.calculate(crate, getPrice, getOwned, resolve)
equal(bundleCost, 0, "fully owned bundle should cost zero")
equal(rate, 100, "fully owned materials should leave only crate cost")

-- Unknown item IDs must not cause a nil table-index error or invent a price.
local unknownCrate = {name = "Unknown", id = 9002, favour = 5,
  bundles = {{name = "Unresolved Material", qty = 3}}}
local unknownRate = MFO_Calculations.calculate(
  unknownCrate,
  function(id) return prices[id] end,
  function(id) return owned[id] or 0 end,
  function(name) return nil end)
equal(unknownRate, nil, "unresolved material IDs should remain unranked safely")

local noFavourRate, _, noFavourBundle = MFO_Calculations.calculate(
  unverified, function() return 100 end, function() return 0 end,
  function() return 100 end)
equal(noFavourRate, nil, "unverified favour cannot generate gold-per-favour rank")
check(noFavourBundle ~= nil, "unverified favour still allows cheapest bundle selection")


-- Planner must minimise total spend rather than selecting the lowest per-Favour rate.
local planOptions={
  {key="five",favour=5,cost=90},
  {key="ten",favour=10,cost=160},
  {key="twenty",favour=20,cost=300},
}
local plan=MFO_Calculations.plan(25,planOptions)
equal(plan.favour,25,"planner must reach the exact target when cheaper")
equal(plan.cost,390,"planner must choose the cheapest combined cost")
equal(plan.items.twenty,1,"planner should select one twenty-Favour crate")
equal(plan.items.five,1,"planner should select one five-Favour crate")
local overfill=MFO_Calculations.plan(18,{{key="fifteen",favour=15,cost=200},{key="ten",favour=10,cost=90}})
equal(overfill.favour,20,"planner should allow cheaper overfill")
equal(overfill.cost,180,"planner should minimise total cost with overfill")
local missing=MFO_Calculations.plan(10,{{key="missing",favour=10,cost=nil}})
equal(missing,nil,"planner must not treat missing prices as free")
local invalid=MFO_Calculations.plan(1001,planOptions)
equal(invalid,nil,"planner must bound target input")
local forced=MFO_Calculations.plan(20,planOptions,planOptions[1])
equal(forced.items.five,2,"forced planner seed should be retained")
equal(forced.cost,340,"forced planner should find cheapest completion")

-- Guard against accidental capitalization of case-sensitive Lua identifiers
-- while editing player-facing text. This caught the v0.1.55 ownedCheck bug.
local coreFile = assert(io.open("MerchantsFavourOptimiser/Core.lua", "r"))
local coreSource = coreFile:read("*a")
coreFile:close()
for _, identifier in ipairs({"ownedCheck", "ownedLabel", "ownedCount"}) do
  check((coreSource:find("local " .. identifier, 1, true) ~= nil or
    coreSource:find("local function " .. identifier, 1, true) ~= nil),
    "UI identifier " .. identifier .. " must retain its original case")
end
check(not coreSource:find("OwnedCheck", 1, true), "wrong-case OwnedCheck reference")
check(not coreSource:find("OwnedLabel", 1, true), "wrong-case OwnedLabel reference")
check(not coreSource:find("OwnedCount", 1, true), "wrong-case OwnedCount reference")
check(coreSource:find('Crate (Cheapest Bundle)', 1, true) ~= nil, "crate column heading must be preserved")
check(coreSource:find('Net C/F', 1, true) ~= nil, "net cost heading must be preserved")
check(coreSource:match('clearButton:SetScript%("OnClick",function%(%)(.-)end%)'):find('planFavour()',1,true)~=nil,
  "Clear must explicitly restore rankings after programmatic SetText")
check(coreSource:find('targetInput:SetScript("OnTextChanged"',1,true)~=nil,
  "planner must react to target entry without separate button")
check(coreSource:find('planner:Show();subheader:Hide();scrollFrame:Hide()',1,true)~=nil,
  "planner must replace the rankings in the existing window")
check(coreSource:find('plannerStockToggle=CreateFrame',1,true)~=nil,
  "inline planner must expose its own owned-items toggle")
check(coreSource:find('plannerStockToggle:SetChecked(MFO_DB.useOwned)',1,true)~=nil,
  "planner owned-items checkbox must sync with shared saved setting")
check(not coreSource:find('plannerBtn=CreateFrame',1,true),
  "standalone planner launcher must be removed")

check(not coreSource:find("Bind Item", 1, true), "obsolete manual bind button must be absent")
check(not coreSource:find("Item Link:", 1, true), "obsolete item link box must be absent")
check(coreSource:find('refreshBtn:SetScript("OnClick",refresh)', 1, true) ~= nil, "refresh control must remain")
check(coreSource:find('note:Hide()',1,true)~=nil, "scan note must not clutter toolbar")
check(not coreSource:find('GameTooltip:AddLine(note:GetText()',1,true), "Refresh must not display scan-age tooltip")
check(coreSource:find('clearButton:SetPoint("RIGHT",refreshBtn,"LEFT",-10,0)',1,true)~=nil,
  "Clear button must sit beside Refresh")
check(coreSource:find('targetInput:SetPoint("RIGHT",clearButton,"LEFT",-10,0)',1,true)~=nil,
  "Favour input must sit beside Clear")


print("PASS: 30 crate definitions, calculations and UI capitalization guards")

check(coreSource:find('scanAgeFooter:SetPoint("BOTTOMRIGHT"',1,true)~=nil,
  "scan-age indicator must sit at bottom-right")
check(coreSource:find('scanAgeFooter:SetText("Last AH Scan: "..elapsed.." Ago")',1,true)~=nil,
  "scan-age indicator must display measured elapsed age")
check(coreSource:find('if days<1 then scanAgeFooter:SetTextColor',1,true)~=nil,
  "scan-age indicator must use freshness colors")

check(coreSource:find('footerParts={MFO_AH.Market(),complete.."/"..#rows.." Crates"}',1,true)~=nil,
  "footer must show concise crate count")
check(coreSource:find('if missingIDs>0 then footerParts',1,true)~=nil,
  "footer should only show missing ID warnings when relevant")
check(coreSource:find('if missingPrices>0 then footerParts',1,true)~=nil,
  "footer should only show missing price warnings when relevant")

check(coreSource:find('local scannedAt=MFO_AH and MFO_AH.LastScan()',1,true)~=nil,
  "scan footer must use standalone full-scan completion timestamp")
check(not coreSource:find('GetAuctionAgeByItemID',1,true),
  "scan footer must not mistake oldest item price age for last full scan")

check(coreSource:find('MFO_AH.Scan(items)',1,true)~=nil,"MFO must scan without Auctionator")
check(coreSource:find('MFO_AH.ReplaceShopping(items)',1,true)~=nil,"MFO must replace its own shopping list")
check(not coreSource:find('Auctionator.API.v1.MultiSearch',1,true),"MFO shopping must not depend on Auctionator")

local ahSource=assert(io.open("MerchantsFavourOptimiser/StandaloneAH.lua","r")):read("*a")
check(ahSource:find("root.markets[realm][faction]",1,true)~=nil,
  "AH prices and shopping must be scoped to realm and faction")
check(ahSource:find("root.legacyAHData",1,true)~=nil,
  "legacy account-wide data must be backed up before migration")
check(coreSource:find("MFO_AH.Market()",1,true)~=nil,
  "active market must be visible in the interface")

check(coreSource:find('scanOverlay:SetPoint("TOPLEFT",scrollFrame',1,true)~=nil,
  "AH scan overlay must cover the crate table")
check(coreSource:find('scanPercent:SetText(math.floor(percent).."%"',1,true)~=nil,
  "radial scan progress must display a percentage")
check(coreSource:find('scanOverlay:Hide()',1,true)~=nil,
  "AH scan overlay must disappear after completion")
check(not coreSource:find('local scanBar=CreateFrame',1,true),
  "old horizontal AH scan progress bar must be removed")

local ahTab=assert(io.open("MerchantsFavourOptimiser/AHShopping.lua","r")):read("*a")
check(ahTab:find('AH.Shopping()',1,true)~=nil,"AH tab must read MFO shopping list")
check(ahTab:find('AH.Price(',1,true)~=nil,"AH tab must display stored prices")
check(ahTab:find('C_AuctionHouse.SendSearchQuery',1,true)~=nil,"AH tab must support modern item search")
check(ahTab:find('QueryAuctionItems',1,true)~=nil,"AH tab must support legacy item search")

check(ahTab:find('tab=CreateFrame("Button",nil,parent,"BackdropTemplate")',1,true)~=nil,"AH shop must use custom AH tab surface")
check(ahTab:find('tab:SetPoint("TOPLEFT",last,"TOPRIGHT",-7,0)',1,true)~=nil,"AH shop must attach to bottom tab row by top edge")
check(ahTab:find('panel:SetPoint("TOPLEFT",parent,"TOPLEFT",8,-8)',1,true)~=nil,"AH shop must cover the AH window")

check(ahTab:find('addon=="Blizzard_AuctionUI"',1,true)~=nil,"MFO tab must attach when Blizzard Auction UI loads")
check(ahTab:find('AUCTION_HOUSE_SHOW',1,true)~=nil,"MFO tab must handle opening the auction house")

check(not ahTab:find('tab:SetPoint("TOPRIGHT"',1,true),"AH shop must never use top-right placement")

check(ahTab:find('restoreNative()',1,true)~=nil,"AH shop must restore native panels")
check(ahTab:find('background:SetTexture(ART.."MFO_WoodBackground")',1,true)~=nil,"AH shop must use opaque MFO wood background")

check(ahTab:find('setNativeTitle(parent)',1,true)~=nil,"Full-window overlay must have an MFO header")

check(ahTab:find('local left=inset(',1,true)~=nil,"MFO shop must create a left list pane")
check(ahTab:find('local right=inset(',1,true)~=nil,"MFO shop must create a right detail pane")
check(ahTab:find('hideNative(parent)',1,true)~=nil,"MFO shop must hide native auction content")

check(ahTab:find('isBottomTab(child,parent)',1,true)~=nil,"MFO shop must preserve native bottom tabs")
check(ahTab:find('tint:SetTexture(ART.."MFO_CoinBackground")',1,true)~=nil,"MFO background must use coin watermark")

check(ahTab:find('restoreNativeTitle()',1,true)~=nil,"MFO must restore native Auction House title")
check(ahTab:find('region:SetText("MFO - Shopping")',1,true)~=nil,"MFO must set native header title")

check(ahTab:find('left:SetWidth(340)',1,true)~=nil,"Shopping list must use Auctionator-style pane proportions")
check(ahTab:find('row.cost:SetWidth(72)',1,true)~=nil,"Shopping prices must have dedicated width")
check(ahTab:find('header:SetText("")',1,true)~=nil,"Duplicate shopping title must be hidden")

check(ahTab:find('searchLabel:SetText("Search Term:")',1,true)==nil,"Unused search toolbar must be removed")
check(ahTab:find('header:SetText("")',1,true)~=nil,"Native title must not be duplicated")

check(ahTab:find('right:SetPoint("TOPLEFT",left,"TOPRIGHT",8,0)',1,true)~=nil,"Right panel must anchor to left without overlap")

check(ahTab:find('local function startLiveSearch(id)',1,true)~=nil,"Live AH search must be triggered by item selection")
check(ahTab:find('COMMODITY_SEARCH_RESULTS_UPDATED',1,true)~=nil,"Live AH must support commodity results")
check(ahTab:find('ITEM_SEARCH_RESULTS_UPDATED',1,true)~=nil,"Live AH must support item results")

check(ahTab:find('panel.detail=right:CreateFontString',1,true)~=nil,"Selected item details must render above right inset backdrop")
check(ahTab:find('local row=CreateFrame("Button",nil,left)',1,true)~=nil,"Shopping rows must render above left inset backdrop")
check(ahTab:find('local liveStatus=right:CreateFontString',1,true)~=nil,"Live search status must render above right inset backdrop")

check(ahTab:find('button(right,"Search AH"',1,true)==nil,"No redundant manual search button")
check(ahTab:find('for i=1,6 do',1,true)~=nil,"Results fit above footer")

check(ahTab:find('ART.."MFO_WoodBackground"',1,true)~=nil,"Shopping must reuse MFO wood texture")
check(ahTab:find('ART.."MFO_CoinBackground"',1,true)~=nil,"Shopping must reuse MFO coin watermark")
check(ahTab:find('ART.."WTP_ProfessionRow"',1,true)~=nil,"Shopping section headings must use main addon texture")
check(ahTab:find('ART.."WTP_FooterButton"',1,true)~=nil,"Shopping buttons must use main addon skin")
check(ahTab:find('tab=CreateFrame("Button",nil,parent,"BackdropTemplate")',1,true)~=nil,"MFO Shop must use a tab backdrop, not red button")

check(ahTab:find('setTabSelected(true)',1,true)~=nil,"MFO tab must show selected state")

check(ahTab:find('tab=CreateFrame("Button",nil,parent,"BackdropTemplate")',1,true)~=nil,"MFO Shop must not use red button template")
check(ahTab:find('selectedGlow:Show()',1,true)~=nil,"Selected tab must display rectangular gold glow")
check(ahTab:find('tab=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")',1,true)==nil,"MFO Shop tab must not use default red button skin")

check(ahTab:find('tab:SetHeight(active and 35 or 29)',1,true)~=nil,"Selected MFO tab must extend below inactive tabs")
check(ahTab:find('local grey=.24-.10*t',1,true)~=nil,"Inactive MFO tab must be neutral grey")
check(ahTab:find('strip:SetColorTexture(.22+.40*t,.16+.23*t,.09+.025*t,1)',1,true)~=nil,"Selected MFO tab must use brown-to-gold gradient")

check(ahTab:find('AuctionHouseFrameDisplayModeTabTemplate',1,true)~=nil,"Forever modern AH tab template must be preferred")
check(ahTab:find('PanelTemplates_SelectTab(tab)',1,true)~=nil,"Modern tab must use native selected state")
check(ahTab:find('else\n  tab=CreateFrame("Button",nil,parent,"BackdropTemplate")',1,true)~=nil,"Forever custom fallback must remain")

check(ahTab:find('SOUNDKIT.IG_CHARACTER_INFO_TAB',1,true)~=nil,"MFO tab should use native tab click sound")
check(ahTab:find('playTabClick()',1,true)~=nil,"MFO tab click must trigger tab sound")

-- Replacing a shopping list must be explicit, atomic and scoped to the market.
local ahSource=assert(io.open("MerchantsFavourOptimiser/StandaloneAH.lua","r")):read("*a")
check(ahSource:find("function AH.ReplaceShopping(items)",1,true)~=nil,"AH must provide explicit replacement")
check(ahSource:find('if not next(replacement) then return false',1,true)~=nil,"Empty replacement must preserve existing list")
check(ahSource:find("db().shopping=replacement",1,true)~=nil,"Replacement must overwrite current market list")
check(coreSource:find("MFO_AH.ReplaceShopping(items)",1,true)~=nil,"Main Shop buttons must replace list")
check(not coreSource:find("MFO_AH.Shop(items)",1,true),"Main Shop buttons must not append")

check(ahTab:find('if aCrate~=bCrate then return aCrate end',1,true)~=nil,"Crates must appear before shopping materials")
check(ahTab:find('crateIDs[item.id]',1,true)~=nil,"Shopping must recognize known crate item IDs")

check(ahTab:find('button(right,"Close"',1,true)==nil,"Shopping panel must not duplicate AH close control")
check(ahTab:find('panel.page=',1,true)==nil,"Shopping panel must not show page counter")
check(ahTab:find('button(left,"<"',1,true)==nil and ahTab:find('button(left,">"',1,true)==nil,"Shopping panel must not show pagination arrows")
check(ahTab:find('left:EnableMouseWheel(true)',1,true)~=nil,"Long shopping lists must remain scrollable")
check(ahTab:find('local coin=left:CreateTexture',1,true)==nil,"Shopping list pane must not have extra coin overlay")
check(ahTab:find('liveStatus:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",16,18)',1,true)~=nil,"Listing status must be at bottom of selected item pane")

check(ahTab:find('panel.itemIcon=CreateFrame("Button",nil,right)',1,true)~=nil,"Selected item must show a hoverable icon")
check(ahTab:find('GameTooltip:SetHyperlink("item:"..selected)',1,true)~=nil,"Selected item must expose native item tooltip")
check(ahTab:find('if not offer or not item or live.id~=selected or live.waiting then return end',1,true)~=nil,"Purchases must guard stale auction results")


check(ahTab:find('pcall(api.StartCommoditiesPurchase',1,true)==nil,"Protected purchase must not use pcall")

check(ahTab:find('panel.buyOffer=button(right,"Purchase Details",120)',1,true)~=nil,"Protected purchases must be disabled")
check(ahTab:find('api.StartCommoditiesPurchase(order.id,order.qty)',1,true)==nil,"No protected commodity purchase call")
check(ahTab:find('api.ConfirmCommoditiesPurchase(order.id,order.qty)',1,true)==nil,"No protected commodity confirmation call")
check(ahTab:find('api.PlaceBid(order.auctionID,order.buyout)',1,true)==nil,"No protected bid call")
