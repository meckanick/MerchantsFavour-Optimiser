MFO_WritDelivery = {}
local Delivery = MFO_WritDelivery
local stops, unresolved = {}, {}
local worldPins, minimapPins = {}, {}
local attachedMap, ticker
local tomTomOwner, tomTomHandle, tomTomPoint

local function read(api, ...)
  if type(api) ~= "function" then return end
  local ok, first, second = pcall(api, ...)
  if ok then return first, second end
end

local function number(value)
  return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
    and value > -math.huge and value < math.huge
end

local function coordinate(value)
  return number(value) and value >= 0 and value <= 1
end

local function validPoint(mapID, x, y)
  return number(mapID) and mapID > 0 and coordinate(x) and coordinate(y) and (x > 0 or y > 0)
end

function Delivery.Build(states, bags, faction, mapID, x, y)
  local route, missing, grouped, reserved = {}, {}, {}, {}
  if faction ~= "Alliance" and faction ~= "Horde" then return route, missing end
  local function remaining(id)
    return (bags[id] or 0) - (reserved[id] or 0)
  end
  for _, writ in ipairs(MFO_WritCalculations.available(faction)) do
    local point = MFO_WritLocations[writ.questID]
    local requirements = states[writ.id] == "objectives_complete"
      and (not point or point.faction == "Both" or point.faction == faction)
      and MFO_WritCalculations.BagRequirementsMet(writ, remaining)
    if requirements then
      if point and validPoint(point.mapID, point.x, point.y) then
        local stop = grouped[point]
        if not stop then
          stop = {point = point, writs = {}}
          grouped[point] = stop
          route[#route + 1] = stop
        end
        stop.writs[#stop.writs + 1] = writ.id
        for id, qty in pairs(requirements) do reserved[id] = (reserved[id] or 0) + qty end
      else
        missing[#missing + 1] = writ.id
      end
    end
  end

  table.sort(route, function(a, b)
    a, b = a.point, b.point
    if a.mapID ~= b.mapID then
      if a.mapID == mapID then return true end
      if b.mapID == mapID then return false end
      if a.zone ~= b.zone then return a.zone < b.zone end
      return a.mapID < b.mapID
    end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  -- Greedy straight-line order within a zone. Other zones start at their first stop.
  local previousMap, width, height
  for i, stop in ipairs(route) do
    local zone = stop.point.mapID
    if previousMap ~= zone then
      width, height = read(C_Map and C_Map.GetMapWorldSize, zone)
      if not (number(width) and number(height) and width > 0 and height > 0) then width, height = 1, 1 end
    end
    if previousMap == zone or (zone == mapID and validPoint(mapID, x, y)) then
      local best, distance = i, math.huge
      for j = i, #route do
        local point = route[j].point
        if point.mapID ~= zone then break end
        local candidate = ((point.x - x) * width)^2 + ((point.y - y) * height)^2
        if candidate < distance then best, distance = j, candidate end
      end
      route[i], route[best] = route[best], route[i]
    end
    local point = route[i].point
    previousMap, x, y = zone, point.x, point.y
  end
  return route, missing
end

local function playerPosition()
  local mapID = read(C_Map and C_Map.GetBestMapForUnit, "player")
  if not number(mapID) then return end
  local position = read(C_Map.GetPlayerMapPosition, mapID, "player")
  local x, y
  if position and not (issecretvalue and issecretvalue(position)) then x, y = read(position.GetXY, position) end
  if validPoint(mapID, x, y) then return mapID, x, y end
  return mapID
end

local function worldPosition(mapID, x, y)
  local position = read(CreateVector2D, x, y)
  if not position then return end
  local continent, world = read(C_Map and C_Map.GetWorldPosFromMapPos, mapID, position)
  if not (number(continent) and world) or (issecretvalue and issecretvalue(world)) then return end
  local north, west = read(world.GetXY, world)
  if number(north) and number(west) then return continent, north, west end
end

function Delivery.Description(point)
  return ("%s%s | %s (%.1f, %.1f)"):format(point.name, point.kind == "object" and " [Object]" or "",
    point.zone, point.x * 100, point.y * 100)
end

function Delivery.Route()
  return stops, unresolved
end

function Delivery.MarkersEnabled()
  return MFO_DB and MFO_DB.writDeliveryMarkers ~= false
end

function Delivery.HasTomTom()
  return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
    and type(TomTom.RemoveWaypoint) == "function" and type(TomTom.WaypointExists) == "function"
    and type(TomTom.SetCrazyArrow) == "function"
end

local function clearTomTom()
  if tomTomHandle then read(tomTomOwner.RemoveWaypoint, tomTomOwner, tomTomHandle) end
  tomTomOwner, tomTomHandle, tomTomPoint = nil, nil, nil
end

function Delivery.SendToTomTom(point)
  if not (Delivery.HasTomTom() and Delivery.MarkersEnabled()) then return false end
  local title = "MFO Writ Delivery: " .. point.name
  local exists = read(TomTom.WaypointExists, TomTom, point.mapID, point.x, point.y, title)
  if exists == true and tomTomOwner == TomTom and tomTomPoint == point then
    return pcall(TomTom.SetCrazyArrow, TomTom, tomTomHandle, 15, title)
  end
  if exists ~= false then return false end
  clearTomTom()
  local handle = read(TomTom.AddWaypoint, TomTom, point.mapID, point.x, point.y, {
    title = title, from = "MFO", persistent = false, world = false, minimap = false,
    crazy = true, silent = true, cleardistance = 0, arrivaldistance = 15,
  })
  if not handle then return false end
  tomTomOwner, tomTomHandle, tomTomPoint = TomTom, handle, point
  return true
end

local function hidePins(pool, first)
  for i = first or 1, #pool do pool[i]:Hide() end
end

local function placePin(pool, index, parent, stop, anchor, x, y)
  local pin = pool[index]
  if not pin then
    pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(18, 18)
    pin:EnableMouse(true)
    pin:SetFrameLevel(parent:GetFrameLevel() + 10)
    local shade = pin:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(.24, .15, .08, .94)
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.label:SetPoint("CENTER")
    pin:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(Delivery.Description(self.stop.point), 1, .82, .2)
      GameTooltip:AddLine(("%d Writs ready"):format(#self.stop.writs), 1, 1, 1)
      GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[index] = pin
  end
  if pin.stop ~= stop then pin.stop = stop; pin.label:SetText(stop.order) end
  if pin.x ~= x or pin.y ~= y then
    pin.x, pin.y = x, y
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", parent, anchor, x, y)
  end
  pin:Show()
end

local function drawWorldPins()
  local map = attachedMap
  local index = 0
  if map and Delivery.MarkersEnabled() and map:IsShown() then
    local mapID, canvas = map:GetMapID(), map:GetCanvas()
    if not canvas then hidePins(worldPins); return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    for _, stop in ipairs(stops) do
      local point = stop.point
      if point.mapID == mapID then
        index = index + 1
        placePin(worldPins, index, canvas, stop, "TOPLEFT", width * point.x, -height * point.y)
      end
    end
  end
  hidePins(worldPins, index + 1)
end

local function attachWorldMap()
  local map = WorldMapFrame
  if attachedMap or not (map and map.GetMapID and map.GetCanvas and map.IsShown and map.HookScript
    and map.OnMapChanged and map.OnCanvasSizeChanged and hooksecurefunc and map:GetCanvas()) then return end
  attachedMap = map
  map:HookScript("OnShow", drawWorldPins)
  hooksecurefunc(map, "OnMapChanged", drawWorldPins)
  hooksecurefunc(map, "OnCanvasSizeChanged", drawWorldPins)
end

local function drawMinimapPins()
  local mapID, x, y = playerPosition()
  local radius = read(C_Minimap and C_Minimap.GetViewRadius)
  if not (x and number(radius) and radius > 0 and Minimap:IsVisible()) then
    hidePins(minimapPins)
    return
  end
  local continent, north, west = worldPosition(mapID, x, y)
  local rotated = read(C_CVar and C_CVar.GetCVarBool, "rotateMinimap")
  local angle = 0
  if rotated then angle = read(GetPlayerFacing) end
  if not (continent and number(angle)) then hidePins(minimapPins); return end
  local cos, sin = math.cos(angle), math.sin(angle)
  local index = 0
  for _, stop in ipairs(stops) do
    if stop.continent == continent and stop.point.mapID == mapID then
      local east, south = (west - stop.west) / radius, (north - stop.north) / radius
      if east^2 + south^2 <= .85^2 then
        index = index + 1
        placePin(minimapPins, index, Minimap, stop, "CENTER",
          (east * cos - south * sin) * Minimap:GetWidth() / 2,
          -(east * sin + south * cos) * Minimap:GetHeight() / 2)
      end
    end
  end
  hidePins(minimapPins, index + 1)
end

function Delivery.RefreshMarkers()
  if tomTomPoint then
    local keep = false
    for _, stop in ipairs(stops) do
      if stop.point == tomTomPoint then keep = Delivery.MarkersEnabled(); break end
    end
    if not keep then clearTomTom() end
  end
  attachWorldMap()
  drawWorldPins()
  local localPins
  if Delivery.MarkersEnabled() and Minimap and Minimap.IsVisible and C_Timer and C_Timer.NewTicker
    and C_Minimap and C_Minimap.GetViewRadius and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local mapID = playerPosition()
    for _, stop in ipairs(stops) do
      if stop.point.mapID == mapID and stop.continent then localPins = true; break end
    end
  end
  if localPins then
    drawMinimapPins()
    if not ticker then ticker = C_Timer.NewTicker(.2, drawMinimapPins) end
  else
    if ticker then ticker:Cancel(); ticker = nil end
    hidePins(minimapPins)
  end
end

function Delivery.Refresh(bags)
  local mapID, x, y = playerPosition()
  stops, unresolved = Delivery.Build(MFO_WritTracking.Snapshot(), bags, read(UnitFactionGroup, "player"), mapID, x, y)
  for i, stop in ipairs(stops) do
    stop.order = i
    stop.continent, stop.north, stop.west = worldPosition(stop.point.mapID, stop.point.x, stop.point.y)
  end
  Delivery.RefreshMarkers()
end

function Delivery.OpenMap(point)
  local map = WorldMapFrame
  if not (map and map.SetMapID and ShowUIPanel) then return false end
  local ok = pcall(function()
    ShowUIPanel(map)
    map:SetMapID(point.mapID)
  end)
  return ok
end
