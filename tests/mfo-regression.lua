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
check(coreSource:find('setScanAgeDisplay("Last AH Scan: "..elapsed.." Ago",color)',1,true)~=nil,
  "scan-age indicator must display measured elapsed age")
check(coreSource:find('local color=days<1 and "fresh" or days<3 and "recent" or days<7 and "old" or "stale"',1,true)~=nil and
      coreSource:find('scanAgeFooter:SetTextColor(.3,.95,.3)',1,true)~=nil and
      coreSource:find('scanAgeFooter:SetTextColor(1,.85,.2)',1,true)~=nil and
      coreSource:find('scanAgeFooter:SetTextColor(1,.55,.15)',1,true)~=nil and
      coreSource:find('scanAgeFooter:SetTextColor(1,.25,.25)',1,true)~=nil,
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
-- The market table may be accessed through local aliases to avoid repeated
-- nested lookups; verify both realm and faction indexes are still present.
check(ahSource:find("local realmMarkets=markets[realm]",1,true)~=nil and
      ahSource:find("local market=realmMarkets[faction]",1,true)~=nil and
      ahSource:find("realmMarkets[faction]=market",1,true)~=nil,
  "AH prices and shopping must be scoped to realm and faction")
-- Legacy capability flags must be local to the scanner, not accidentally
-- resolved as globals by functions defined before their initialization.
check(ahSource:find("local modern,eventOK",1,true)~=nil and
      ahSource:find('modern = C_AuctionHouse and',1,true)~=nil and
      ahSource:find('eventOK=pcall(events.RegisterEvent',1,true)~=nil,
  "legacy scanner must share forward-declared capability flags")
check(ahSource:find('local realm=(GetRealmName and GetRealmName())',1,true)~=nil and
      ahSource:find('local faction=(UnitFactionGroup and UnitFactionGroup("player"))',1,true)~=nil,
  "market identity should avoid repeated function type checks")
-- The price cache already resolved the realm/faction: pass it into db()
-- rather than repeating the client API lookups on a cache miss.
check(ahSource:find("local function db(realm,faction)",1,true)~=nil and
      ahSource:find("if not realm or not faction then realm,faction=marketIdentity() end",1,true)~=nil and
      ahSource:find("priceRecords=db(realm,faction).prices",1,true)~=nil,
  "price cache must reuse resolved market identity without changing other db callers")
check(ahSource:find("root.legacyAHData",1,true)~=nil,
  "legacy account-wide data must be backed up before migration")
check(coreSource:find("MFO_AH.Market()",1,true)~=nil,
  "active market must be visible in the interface")

check(coreSource:find('scanOverlay:SetPoint("TOPLEFT",scrollFrame',1,true)~=nil,
  "AH scan overlay must cover the crate table")
check(coreSource:find('scanPercent:SetText(shownPercent.."%"',1,true)~=nil and
      coreSource:find('local shownPercent=math.floor(percent)',1,true)~=nil,
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
check(ahTab:find('for i=1,visibleOffers do',1,true)~=nil,"Results fit above footer")

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
check(ahTab:find('liveStatus:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",16,16)',1,true)~=nil,"Listing status must be at bottom of selected item pane")

check(ahTab:find('panel.itemIcon=CreateFrame("Button",nil,right)',1,true)~=nil,"Selected item must show a hoverable icon")
check(ahTab:find('GameTooltip:SetHyperlink("item:"..selected)',1,true)~=nil,"Selected item must expose native item tooltip")
check(ahTab:find('if not offer or not item or live.id~=selected or live.waiting then return end',1,true)~=nil,"Purchases must guard stale auction results")


check(ahTab:find('pcall(api.StartCommoditiesPurchase',1,true)==nil,"Protected purchase must not use pcall")

check(ahTab:find('api.PlaceBid(order.auctionID,order.buyout)',1,true)==nil,"No protected bid call")

check(ahTab:find('panel.buyOffer=button(right,"Buy Selected",115)',1,true)~=nil,"Primary button commodity diagnostic present")
check(ahTab:find('api.StartCommoditiesPurchase(selected,qty)',1,true)~=nil,"Commodity test uses primary button")
check(ahTab:find('api.PlaceBid(order.auctionID,order.buyout)',1,true)==nil,"Regular buyouts remain disabled")


check(ahTab:find('local chainBuy=false',1,true)~=nil,"Chain Buy defaults off")

check(ahTab:find('local preflight=CreateFrame("Frame"',1,true)~=nil,"Chain Buy pre-purchase dialog present")
check(ahTab:find('chainToggle:SetChecked(false)',1,true)~=nil,"Chain Buy defaults unchecked")
check(ahTab:find('chainBuy and needed or math.min(needed,available)',1,true)~=nil,"Chain Buy quantity selection retained")
check(ahTab:find('row.quantity:SetText',1,true)~=nil,"Listing quantities use separate aligned column")

check(ahTab:find('dialogFill:SetColorTexture(.065,.042,.02,1)',1,true)~=nil,"Pre-purchase dialog must retain opaque inner fill")

check(ahTab:find('local visibleOffers=4',1,true)~=nil,"Auction listing viewport limits visible rows")
check(ahTab:find('CreateFrame("Slider",nil,right)',1,true)~=nil,"Auction listing uses independent slider compatible with Forever")
check(ahTab:find('offerViewport:EnableMouseWheel(true)',1,true)~=nil,"Auction listings scroll with mouse wheel")

check(ahTab:find('ART.."WTP_ScrollTrack"',1,true)~=nil,"AH scrollbar uses MFO track")
check(ahTab:find('ART.."WTP_ScrollThumb"',1,true)~=nil,"AH scrollbar uses MFO thumb")
check(ahTab:find('grey(up,not canUp)',1,true)~=nil,"Top arrow greys out at scroll limit")
check(ahTab:find('grey(down,not canDown)',1,true)~=nil,"Bottom arrow greys out at scroll limit")
check(ahTab:find('offerScroll:HookScript("OnUpdate",updateScrollSkin)',1,true)~=nil,"Scroll hover highlights update")

check(ahTab:find('UIPanelScrollBarTemplate',1,true)==nil,"Do not use secure scroll template without a ScrollFrame")
check(ahTab:find('offerScroll:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-9,47)',1,true)~=nil,"Scrollbar stays above buy footer")

check(ahTab:find('offerScroll:SetPoint("TOPRIGHT",right,"TOPRIGHT",-9,-184)',1,true)~=nil,"Scrollbar starts below Available heading")

check(ahTab:find('math.floor(maximum-value+.5)',1,true)~=nil,"Invert native vertical slider value to match downwards drag")
check(ahTab:find('offerOffset/(high-low)',1,true)~=nil,"Visible grip follows listing offset")

-- Live AH listing view must retain every result returned by the game API.
check(ahTab:find("math.min(count,100)",1,true)==nil,"Legacy AH results are not capped at 100")
check(ahTab:find("math.min(api.GetNumCommoditySearchResults",1,true)==nil,"Commodity results are not capped at 100")
check(ahTab:find("math.min(api.GetNumItemSearchResults",1,true)==nil,"Item results are not capped at 100")
check(ahTab:find("showing 6 lowest",1,true)==nil,"No misleading six-listing status")
check(ahTab:find("scroll to see all",1,true)~=nil,"All-listings status is shown")

-- Purchase-dialog regressions: both skins must be applied while their local frames exist.
local skinDefinition=assert(ahTab:find('local function skinPurchaseDialog(frame,title)',1,true),"Dialog skin helper missing")
local confirmDefinition=assert(ahTab:find('local confirm=CreateFrame("Frame"',1,true),"Purchase confirmation frame missing")
local preflightDefinition=assert(ahTab:find('local preflight=CreateFrame("Frame"',1,true),"Pre-purchase frame missing")
local skinConfirm=assert(ahTab:find('skinPurchaseDialog(confirm,"Confirm Purchase")',1,true),"Confirmation skin invocation missing")
local skinPreflight=assert(ahTab:find('skinPurchaseDialog(preflight,"Purchase Item")',1,true),"Pre-purchase skin invocation missing")
local panelHide=assert(ahTab:find('panel:Hide()\n panel.offset=0',1,true),"Panel initial hide missing")
check(skinDefinition<confirmDefinition and confirmDefinition<preflightDefinition and preflightDefinition<skinConfirm and skinConfirm<panelHide,"Dialog skins must be applied within UI construction, never after the event watcher")
check(skinConfirm<skinPreflight and skinPreflight<panelHide,"Both dialogs must be skinned before the panel is initially hidden")
check(ahTab:find('end)  skinPurchaseDialog',1,true)==nil,"Never append local skin calls to an event callback")
check(ahTab:find('ART.."WTP_ProfessionRow"',1,true)~=nil,"Dialog headers must use existing MFO row texture")
check(ahTab:find('ART.."MFO_WoodBackground"',1,true)~=nil,"Dialog backgrounds must use existing MFO wood texture")
check(ahTab:find('\\\\nBuy quantity:',1,true)==nil,"Purchase text must not display literal backslash-n")
check(ahTab:find('\\nBuy quantity:',1,true)~=nil,"Purchase text must contain a Lua newline escape")
check(ahTab:find('api.StartCommoditiesPurchase(selected,qty)',1,true)~=nil,"Keep commodity start in direct click handler")
check(ahTab:find('C_AuctionHouse.ConfirmCommoditiesPurchase(order.id,order.qty)',1,true)~=nil,"Keep commodity confirm in direct click handler")

-- AH reliability: no throttle event may be interpreted as a search result.
check(ahTab:find('if event=="AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then',1,true)~=nil,"Throttle ready event must be handled separately")
check(ahTab:find('return -- Throttle notifications are not auction result payloads.',1,true)~=nil,"Throttle event must not clear live search")
check(ahTab:find('if live.elapsed>=15 then',1,true)~=nil,"Stalled live searches must expire")
check(ahTab:find('Auction search timed out. Select the item again to retry.',1,true)~=nil,"Search timeout must show recovery instruction")
check(ahTab:find('live.offers={};live.waiting=false;selectedOffer=nil',1,true)~=nil,"Purchase completion must invalidate stale offers")

-- Closing and reopening AH Shopping must not reuse stale listing selections.
check(ahTab:find('live.id=nil;live.offers={};live.waiting=false;live.elapsed=0',1,true)~=nil,"Closing shopping must reset live search state")
check(ahTab:find('selectedOffer=nil;selected=nil',1,true)~=nil,"Reopening shopping must reset selected listing and item")
check(ahTab:find('if watcher.uiElapsed>=1 then watcher.uiElapsed=0;update() end',1,true)~=nil,"Visible shopping UI should rebuild no more than once per second")

-- Purchase recovery: ignore unrelated commodity events and close stale dialogs.
check(ahTab:find('local awaitingPurchase=false',1,true)~=nil,"Track a submitted commodity confirmation")
check(ahTab:find('if not commodityOrder and not awaitingPurchase then return end',1,true)~=nil,"Ignore unrelated failed commodity events")
check(ahTab:find('if not awaitingPurchase then return end',1,true)~=nil,"Ignore unrelated commodity success events")
check(ahTab:find('resetPurchaseDialogs=function()',1,true)~=nil,"Dialog cleanup must be initialized")
check(ahTab:find('if resetPurchaseDialogs then resetPurchaseDialogs() end',1,true)~=nil,"Purchase cleanup must dismiss stale dialogs")
check(ahTab:find('awaitingPurchase=true;purchaseElapsed=0;purchaseWarningShown=false\n   C_AuctionHouse.ConfirmCommoditiesPurchase',1,true)~=nil,"Confirmation must track pending result before API call")

-- In-flight purchases cannot be resubmitted while awaiting AH acknowledgement.
check(ahTab:find('if commodityOrder or awaitingPurchase then',1,true)~=nil,"Search and purchase must guard active commodity transactions")
check(ahTab:find('or commodityOrder or awaitingPurchase then return end',1,true)~=nil,"Buy Selected must reject duplicate in-flight purchases")
check(ahTab:find('purchaseElapsed>=20',1,true)~=nil,"Delayed purchase must be reported")
check(ahTab:find('Check your inventory or AH before trying again.',1,true)~=nil,"Delayed purchase warning must discourage blind retries")
check(ahTab:find('if not awaitingPurchase then commodityOrder=nil end',1,true)~=nil,"Reactivating shopping must preserve an in-flight confirmation")

-- Performance: avoid reconstructing static crate metadata and duplicate detail price reads.
check(ahTab:find('local crateIDs={}',1,true)~=nil,"Crate membership must be cached")
check(ahTab:find('local selectedPrice=current and prices[selected]',1,true)~=nil,"Selected price must be fetched once per detail update")
check(ahTab:find('gold((selectedPrice or 0)*current.qty)',1,true)~=nil,"Selected total must reuse cached selected price")

-- First-search race: arm waiting state before dispatching an AH query.
local armed=assert(ahTab:find('live.waiting=true;live.message="Searching live auctions..."',1,true))
local dispatched=assert(ahTab:find('pcall(C_AuctionHouse.SendSearchQuery,key,{},false)',1,true))
check(armed<dispatched,"AH listener must be armed before search dispatch")
check(ahTab:find('live.waiting=false\n live.message="Live search unavailable in this client."',1,true)~=nil,"Failed search dispatch must clear waiting state")

-- Per-refresh prices are shared by totals, detail, and visible rows.
check(ahTab:find('local shopping=AH.Shopping()',1,true)~=nil,"Shopping data should be fetched once per refresh")
check(ahTab:find('prices[v.id]=price',1,true)~=nil,"Price snapshot must be populated during total calculation")
check(ahTab:find('local price=prices[item.id]',1,true)~=nil,"Visible rows should reuse calculated prices")

-- Stage 6 scanner: prevent per-frame cache polling and synchronous first-result races.
check(ahSource:find('if scanTick<.2 then return end',1,true)~=nil,"AH scan polling must be throttled")
local armed=assert(ahSource:find('waiting=true;started=GetTime and GetTime() or 0',1,true))
local dispatched=assert(ahSource:find('pcall(C_AuctionHouse.SendSearchQuery,key,{},false)',1,true))
check(armed<dispatched,"Modern AH scanner must arm result handler before dispatch")
check(ahSource:find('if not ok then busy=false;waiting=false;AH.message="Modern AH query failed"',1,true)~=nil,"Failed dispatch must reset waiting state")

-- Legacy shopping popup should read each cached price only once.
local coreSource=assert(io.open("MerchantsFavourOptimiser/Core.lua","r")):read("*a")
check(coreSource:find('local price=item and MFO_AH.Price(item.id)',1,true)~=nil,"Legacy shopping popup must cache each item price")
check(coreSource:find('money(price and price*item.qty)',1,true)~=nil,"Legacy shopping popup must reuse cached price")

-- Known crate IDs must avoid redundant item-name lookups during UI redraw.
check(coreSource:find('if not crate.id then',1,true)~=nil,"Only crates without IDs should need name resolution")
check(coreSource:find('if not resolve(crate.name) then missingIDs=missingIDs+1',1,true)~=nil,"Unresolved crates must still be counted")
check(coreSource:find('elseif cp==nil then missingPrices=missingPrices+1 end',1,true)~=nil,"Known crates must still count missing prices")

-- Repeated refreshes must not rewrite an unchanged scan-age footer.
check(coreSource:find("if text~=lastScanAgeText then",1,true)~=nil and
      coreSource:find("if color~=lastScanAgeColor then",1,true)~=nil,
  "scan-age footer must avoid redundant text and colour updates")
check(coreSource:find('setScanAgeDisplay("Last AH Scan: Unknown","unknown")',1,true)~=nil and
      coreSource:find('setScanAgeDisplay("Last AH Scan: "..elapsed.." Ago",color)',1,true)~=nil,
  "scan-age footer must update for both missing and completed scans")

-- Scan overlay visibility should only be toggled on state transitions.
check(coreSource:find("local lastScanDisplayMode",1,true)~=nil and
      coreSource:find('local mode=running and "running" or total>0 and "complete" or "idle"',1,true)~=nil and
      coreSource:find("if mode~=lastScanDisplayMode then",1,true)~=nil and
      coreSource:find("lastScanDisplayMode=mode",1,true)~=nil,
  "AH overlay visibility must only change on scan state transitions")
check(coreSource:find('if mode=="complete" then\n    local missingCount=#MFO_AH.Missing()',1,true)~=nil,
  "AH completion summary must refresh when counts change within completed state")

-- Completion callbacks may repeat with identical priced/missing counts.
check(coreSource:find("local lastScanSummaryText",1,true)~=nil and
      coreSource:find("if summary~=lastScanSummaryText then",1,true)~=nil and
      coreSource:find("scanSummaryText:SetText(summary)",1,true)~=nil,
  "AH completion summary should update only when its text changes")

-- The AH update callback must reuse the progress sample's running flag.
check(coreSource:find("  return running\nend\nMFO_AH.onUpdate=function()",1,true)~=nil and
      coreSource:find("local running=updateScanProgress()",1,true)~=nil and
      coreSource:find("if not running then status:SetText(MFO_AH.Status()) end",1,true)~=nil,
  "AH callback must reuse scan progress instead of sampling twice")

-- Scan progress callbacks should not recolour all 48 segments when only
-- one segment (or none) has changed.
check(coreSource:find("local lastScanLit=-1",1,true)~=nil and
      coreSource:find("if lit~=lastScanLit then",1,true)~=nil and
      coreSource:find("for i=math.max(1,lastScanLit+1),lit do",1,true)~=nil and
      coreSource:find("for i=lit+1,lastScanLit do",1,true)~=nil,
  "AH scan progress must only recolour changed segments")
check(coreSource:find("if shownPercent~=lastScanPercent then",1,true)~=nil,
  "AH scan progress must avoid redundant percentage text updates")

-- The rankings footer does not display bank snapshot age; do not compute it.
check(coreSource:find('local bankInfo=""',1,true)==nil and
      coreSource:find('bankInfo=" Bank Snapshot: "',1,true)==nil and
      coreSource:find('if not MFO_DB.bankScanTime then footerParts[#footerParts+1]="Bank Not Scanned" end',1,true)~=nil,
  "rankings refresh should avoid unused bank age calculation while preserving bank status")

-- AH price cache must be cleared per refresh, reused, and inactive outside refreshes.
check(coreSource:find("local refreshPriceCache={}",1,true)~=nil and
      coreSource:find("for id in pairs(refreshPriceCache) do refreshPriceCache[id]=nil end",1,true)~=nil and
      coreSource:find("priceCacheActive=true",1,true)~=nil and
      coreSource:find("priceCacheActive=false",1,true)~=nil,
  "price cache must reuse a cleared table for each refresh")
check(coreSource:find("if priceCacheActive then refreshPriceCache[id]=value==nil and false or value end",1,true)~=nil,
  "price cache must retain missing-price sentinel only while active")

-- Scratch tables are cleared between independent scans and shopping window redraws.
check(coreSource:find("local scanItemScratch={}",1,true)~=nil and
      coreSource:find("for id in pairs(scanItemScratch) do scanItemScratch[id]=nil end",1,true)~=nil and
      coreSource:find("local items=scanItemScratch",1,true)~=nil,
  "AH scan requests must clear and reuse their item scratch table")
check(coreSource:find("local shoppingSortScratch={}",1,true)~=nil and
      coreSource:find("for i=#shoppingSortScratch,1,-1 do shoppingSortScratch[i]=nil end",1,true)~=nil and
      coreSource:find("local sorted=shoppingSortScratch",1,true)~=nil,
  "shopping list redraw must reuse a cleared scratch table")
check(coreSource:find("local missingCount=#MFO_AH.Missing()",1,true)~=nil and
      coreSource:find("missingCount>0",1,true)~=nil,
  "scan completion summary must preserve missing-price counts")

-- Batch allocation reductions must preserve fresh bank indices and table row layout.
check(coreSource:find("local bankScanIDs={}",1,true)~=nil and
      coreSource:find("for i=#bankScanIDs,1,-1 do bankScanIDs[i]=nil end",1,true)~=nil and
      coreSource:find("ids[1]=-1",1,true)~=nil,
  "bank index scratch table must be reset before every scan")
check(coreSource:find("local rowWidths={341,76,76,76,48,76}",1,true)~=nil and
      coreSource:find("t:SetWidth(rowWidths[j])",1,true)~=nil,
  "rankings columns must reuse original fixed widths")
check(coreSource:find("results[#results+1]={crate=crate,rate=rate",1,true)~=nil and
      coreSource:find("table.sort(results,function(a,b)",1,true)~=nil,
  "ranking result append must preserve sorted result processing")

-- Repeated bank snapshots must reuse the static Forever bank bag key list.
check(coreSource:find('local bankBagKeys={"Bank", "BankBag_1"',1,true)~=nil and
      coreSource:find("for _,key in ipairs(bankBagKeys) do",1,true)~=nil and
      coreSource:find("local bankIndex=Enum.BagIndex",1,true)~=nil,
  "bank snapshots must reuse bank bag keys while resolving live Enum indices")
check(coreSource:find("local bankVisited={}",1,true)~=nil and
      coreSource:find("for bag in pairs(bankVisited) do bankVisited[bag]=nil end",1,true)~=nil and
      coreSource:find("if not bankVisited[bag] then",1,true)~=nil,
  "bank scans must still deduplicate overlapping bank bag indices")

-- Learning bag item IDs must not rewrite an unchanged saved mapping.
check(coreSource:find("MFO_DB.ids[name]~=id then",1,true)~=nil and
      coreSource:find("MFO_DB.ids[name]=id",1,true)~=nil,
  "bag item learning must only save new or corrected item IDs")

-- Repeated bag events must reuse the count snapshot without retaining stale items.
check(coreSource:find("local bagCounts={}",1,true)~=nil and
      coreSource:find("for id in pairs(bagCounts) do bagCounts[id]=nil end",1,true)~=nil,
  "bag scans must clear and reuse their count table")
check(coreSource:find("bagCounts={}",1,true)==coreSource:find("local bagCounts={}",1,true)+6,
  "bag scans must not allocate a replacement bag count table")

-- BAG_UPDATE_DELAYED already scans bags before requesting a visible refresh.
-- Reuse that snapshot, but keep normal refreshes scanning inventory.
check(coreSource:find("local function refresh(inventoryFresh)",1,true)~=nil and
      coreSource:find("if not inventoryFresh then learnBagItems();scanBags() end",1,true)~=nil,
  "rankings refresh must reuse fresh inventory when supplied")
check(coreSource:find("learnBagItems();scanBags()\n   local bank=BankFrame",1,true)~=nil and
      coreSource:find("if frame:IsShown() then refresh(true) end",1,true)~=nil,
  "bag update must scan inventory once and refresh using that snapshot")

-- Planner refresh reuses inventory freshly scanned by the main rankings refresh.
check(coreSource:find('if planFavour then planFavour(true) end',1,true)~=nil,"Rankings refresh should pass fresh-inventory hint")
check(coreSource:find('planFavour=function(inventoryFresh)',1,true)~=nil,"Planner should accept fresh-inventory hint")
check(coreSource:find('if not inventoryFresh then learnBagItems();scanBags() end',1,true)~=nil,"Independent planner changes must still rescan bags")

-- Interrupted AH scans must not claim completion or leave the overlay running.
check(ahSource:find('local function stopScan(message)',1,true)~=nil and
      ahSource:find('busy=false;waiting=false',1,true)~=nil and
      ahSource:find('if AH.onUpdate then AH.onUpdate() end',1,true)~=nil,
  "AH failure handling must notify UI and clear scanner state")
check(ahSource:find('if not auctionOpen() then\n    stopScan("AH closed; scan cancelled without updating completion time")',1,true)~=nil,
  "closing the AH must cancel an active scan without saving a completion timestamp")
check(ahSource:find('stopScan("Modern AH query failed; scan not saved")',1,true)~=nil and
      ahSource:find('stopScan("AH query failed; scan not saved")',1,true)~=nil and
      ahSource:find('stopScan("Scan timed out; completion time unchanged")',1,true)~=nil,
  "query failures and timeouts must report the stopped scan")
