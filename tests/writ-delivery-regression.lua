dofile("MerchantsFavourOptimiser/WritData.lua")
dofile("MerchantsFavourOptimiser/WritLocations.lua")
dofile("MerchantsFavourOptimiser/WritCalculations.lua")
dofile("MerchantsFavourOptimiser/WritDelivery.lua")
local Delivery = MFO_WritDelivery

local verified, mapped, audited = {}, 0, {}
for _, writ in ipairs(MFO_WritData) do verified[writ.questID] = true end
local audit = assert(io.open("research/writ-delivery-audit.tsv"))
audit:read("*l")
for line in audit:lines() do
  local fields = {}
  for field in (line.."\t"):gmatch("(.-)\t") do fields[#fields+1] = field end
  local quest = tonumber(fields[1])
  assert(verified[quest] and not audited[quest], "unexpected or duplicate audited quest")
  audited[quest] = true
  local point = MFO_WritLocations[quest]
  assert((point ~= nil) == (fields[2] == "Included"), "delivery inclusion mismatch for "..quest)
  if point then
    local name = fields[5]:match('^"(.*)"$')
    name = name and name:gsub('""', '"') or fields[5]
    assert(point.kind == fields[3] and point.id == tonumber(fields[4]) and point.name == name)
    assert(point.mapID == tonumber(fields[6]) and point.zone == fields[7] and point.faction == fields[10])
    assert(math.abs(point.x * 100 - tonumber(fields[8])) < 1e-9)
    assert(math.abs(point.y * 100 - tonumber(fields[9])) < 1e-9)
    assert(fields[11]:match("^https://") and fields[12]:match("^https://") and fields[13] ~= "")
  end
end
audit:close()
for quest in pairs(verified) do assert(audited[quest], "missing delivery audit row for "..quest) end
for quest, point in pairs(MFO_WritLocations) do
  assert(verified[quest] and point.id > 0 and point.mapID > 0)
  assert(point.kind == "npc" or point.kind == "object")
  assert(point.x > 0 and point.x < 1 and point.y > 0 and point.y < 1)
  mapped = mapped + 1
end
local trunk = MFO_WritLocations[94223]
assert(mapped == 97 and trunk.id == 642320 and trunk.kind == "object" and trunk.mapID == 1431)
assert(MFO_WritLocations[94214].id == 3134 and MFO_WritLocations[94315] == nil)

local function writ(id, faction, item)
  return {id = id, questID = 100 + id, faction = faction, reputation = 75, items = {{id = item, qty = 1}}}
end
local function point(id, faction, mapID, x, kind)
  return {id = id, faction = faction, mapID = mapID, x = x, y = .5,
    zone = mapID == 1 and "A Zone" or "B Zone", name = tostring(id), kind = kind or "npc"}
end
local near = point(6, "Both", 2, .25, "object")
local shared = point(1, "Both", 2, .8)
local far = point(7, "Both", 1, .5)
MFO_WritData = {
  writ(1,"Both",11), writ(2,"Both",12), writ(3,"Both",13), writ(4,"Both",14),
  writ(5,"Horde",15), writ(6,"Both",16), writ(7,"Both",17), writ(8,"Both",18),
  writ(9,"Both",19), writ(10,"Both",11),
}
MFO_WritLocations = {
  [101] = shared, [102] = shared,
  [103] = point(3,"Both",2), [104] = point(4,"Both",2,.9), [105] = shared,
  [106] = near, [107] = far, [108] = point(8,"Horde",2,.5), [110] = far,
}
local states, bags = {}, {}
for _, w in ipairs(MFO_WritData) do states[w.id] = "objectives_complete"; bags[w.id] = 1 end
for i = 11, 19 do bags[i] = 1 end
states[4] = "completed"
local route, missing = Delivery.Build(states, bags, "Alliance", 2, .24, .5)
assert(#route == 3 and route[1].point == near and route[2].point == shared and route[3].point == far)
assert(table.concat(route[2].writs,",") == "1,2" and table.concat(route[3].writs,",") == "7")
assert(table.concat(missing,",") == "3,9")
assert(#Delivery.Build(states, bags, nil) == 0)
route = Delivery.Build(states, bags, "Horde", 2, .24, .5)
assert(#route == 4 and route[2].point == MFO_WritLocations[108] and #route[3].writs == 3)

MFO_DB = {useOwned = true}
MFO_WritTracking = {Snapshot = function() return states end}
UnitFactionGroup = function() return "Alliance" end
Delivery.Refresh(bags)
assert(#Delivery.Route() == 3 and not Delivery.OpenMap(near) and not Delivery.HasTomTom())
assert(not Delivery.SendToTomTom(near))

local function noop() end
local created, minimapTicker, cancellations = {}, nil, 0
local function frame()
  return {
    GetFrameLevel = function() return 0 end, GetWidth = function() return 200 end,
    GetHeight = function() return 100 end, SetSize = noop, EnableMouse = noop,
    SetFrameLevel = noop, ClearAllPoints = noop, CreateTexture = function()
      return {SetAllPoints = noop, SetColorTexture = noop}
    end,
    CreateFontString = function() return {SetPoint = noop, SetText = noop} end,
    SetScript = noop, HookScript = function(self, name, fn) self[name] = fn end,
    SetPoint = function(self, _, _, anchor, x, y) self.anchor, self.x, self.y = anchor, x, y end,
    Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end, IsVisible = function(self) return self.shown end,
  }
end
CreateFrame = function(_, _, parent)
  local pin = frame()
  pin.parent = parent
  created[#created + 1] = pin
  return pin
end
local canvas = frame()
WorldMapFrame = frame()
WorldMapFrame.mapID = 2
WorldMapFrame.GetCanvas = function() return canvas end
WorldMapFrame.GetMapID = function(self) return self.mapID end
WorldMapFrame.OnCanvasSizeChanged = noop
WorldMapFrame.OnMapChanged = noop
WorldMapFrame.SetMapID = function(self, id) self.mapID = id; self:OnMapChanged() end
ShowUIPanel = function(map) map:Show(); map:OnShow() end
hooksecurefunc = function(target, name, callback) target[name] = callback end

local playerX = .24
CreateVector2D = function(x, y) return {GetXY = function() return x, y end} end
C_Map = {
  GetBestMapForUnit = function() return 2 end,
  GetPlayerMapPosition = function() return CreateVector2D(playerX, .5) end,
  GetWorldPosFromMapPos = function(_, v)
    local x, y = v:GetXY()
    return 1, CreateVector2D(-1000*y, -1000*x)
  end,
}
C_Minimap = {GetViewRadius = function() return 50 end}
C_Timer = {NewTicker = function(interval, callback)
  assert(interval == .2 and not minimapTicker)
  minimapTicker = callback
  return {Cancel = function() minimapTicker = nil; cancellations = cancellations + 1 end}
end}
Minimap = frame()
Minimap:Show()
Delivery.Refresh(bags)
assert(#created == 1 and created[1].parent == Minimap and created[1].stop.point == near)
assert(math.abs(created[1].x - 20) < .001 and created[1].y == 0)
assert(Delivery.OpenMap(near))
assert(#created == 3 and created[2].parent == canvas and created[2].stop.point == near)
assert(created[2].anchor == "TOPLEFT" and created[2].x == 50 and created[2].y == -50)
playerX = .8
minimapTicker()
assert(created[1].stop.point == shared and math.abs(created[1].x) < .001)
WorldMapFrame:SetMapID(1)
assert(created[2].stop.point == far and created[2].shown and not created[3].shown)
WorldMapFrame:SetMapID(999)
assert(not created[2].shown)

local handle, removed, sent, arrows = {}, 0, false, 0
TomTom = {
  WaypointExists = function() return sent end,
  AddWaypoint = function(_, mapID, x, y, options)
    assert(mapID == 2 and x == .25 and y == .5)
    assert(options.crazy and not options.persistent and not options.world and not options.minimap)
    sent = true
    return handle
  end,
  SetCrazyArrow = function(_, uid) assert(uid == handle); arrows = arrows + 1 end,
  RemoveWaypoint = function(_, uid) assert(uid == handle); removed = removed + 1 end,
}
assert(Delivery.SendToTomTom(near))
assert(Delivery.SendToTomTom(near) and arrows == 1)
states[6] = "completed"
Delivery.Refresh(bags)
assert(removed == 1 and #Delivery.Route() == 2)
bags[11] = nil
Delivery.Refresh(bags)
route = Delivery.Route()
assert(#route == 2 and table.concat(route[1].writs,",") == "2")
MFO_DB.writDeliveryMarkers = false
Delivery.RefreshMarkers()
assert(not created[1].shown and not minimapTicker and cancellations == 1 and #Delivery.Route() == 2)
MFO_DB.writDeliveryMarkers = true
C_Map.GetWorldPosFromMapPos = function() error("unsupported") end
Delivery.Refresh(bags)
assert(not minimapTicker and #Delivery.Route() == 2)
print("PASS: verified Writ destinations, shared stops and stock, faction and completion, map pins and API fallback")
