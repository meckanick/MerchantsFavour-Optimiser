-- Live quest state comes from Forever. Only confirmed turn-ins are saved.
MFO_WritTracking = {}
local Tracking = MFO_WritTracking
local offers, offerOwner, offerReset = {}, nil, nil
local lastReset, revision = nil, 0

local function read(api, ...)
  if type(api) ~= "function" then return nil end
  local ok, value = pcall(api, ...)
  if ok then return value end
end

function Tracking.CharacterKey()
  local name = read(UnitName, "player")
  local realm = read(GetRealmName)
  local faction = read(UnitFactionGroup, "player")
  if type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT
    and type(realm) == "string" and realm ~= ""
    and (faction == "Alliance" or faction == "Horde") then
    return realm .. ":" .. faction .. ":" .. name
  end
end

local function clock()
  local now = read(GetServerTime)
  if type(now) ~= "number" or not (now > 0 and now < math.huge) then return end
  local seconds = read(C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset)
  if type(seconds) ~= "number" or not (seconds > 0 and seconds < math.huge) then return now end
  return now, now + seconds
end

function Tracking.PollReset()
  local key = Tracking.CharacterKey()
  local now, reset = clock()
  if key ~= offerOwner then lastReset = nil end
  -- The two server clocks may round on different ticks.
  if now and lastReset then
    if not reset and now < lastReset then
      reset = lastReset
    elseif reset and math.abs(reset - lastReset) <= 2 then
      reset = now < lastReset and lastReset or nil
    end
  end
  if key ~= offerOwner or reset ~= offerReset then
    offers, offerOwner, offerReset = {}, key, reset
    revision = revision + 1
  end
  if reset then lastReset = reset end
  return revision, key, now, reset
end

local function completions(key, create)
  if not key or type(MFO_DB) ~= "table" then return end
  local characters = MFO_DB.writQuestCompletions
  if type(characters) ~= "table" then
    if not create then return end
    characters = {}
    MFO_DB.writQuestCompletions = characters
  end
  if type(characters[key]) ~= "table" then
    if not create then return end
    characters[key] = {}
  end
  return characters[key]
end

function Tracking.OnEvent(event, questID)
  if event == "QUEST_DETAIL" then questID = read(GetQuestID) end
  if type(questID) ~= "number" then return false end
  for _, writ in ipairs(MFO_WritData) do
    if writ.daily and writ.questID == questID then
      local _, key, _, reset = Tracking.PollReset()
      if not key then return false end
      if event == "QUEST_TURNED_IN" then
        offers[questID] = nil
        local saved = completions(key, true)
        if saved then
          saved[questID] = reset or true
        end
      elseif event == "QUEST_DETAIL" and reset then
        local saved = completions(key)
        -- A fresh offer plus a cleared server flag can resolve an undated turn-in.
        if saved and saved[questID] == true and
          read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID) == false then
          saved[questID] = nil
        end
        offers[questID] = true
      elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        offers[questID] = nil
      end
      return true
    end
  end
  return false
end

function Tracking.Snapshot()
  local _, key, now = Tracking.PollReset()
  local states = {}
  if not key then return states end
  local saved = completions(key) or {}
  local log = C_QuestLog
  for _, writ in ipairs(MFO_WritData) do
    if writ.daily and writ.questID then
      local questID = writ.questID
      local expiry = saved[questID]
      if type(expiry) == "number" and now and now >= expiry then
        saved[questID], expiry = nil, nil
      end
      if read(log and log.IsQuestFlaggedCompleted, questID) == true
        or (type(expiry) == "number" and now and now < expiry) then
        states[writ.id] = "completed"
      elseif not expiry then
        local index = read(log and log.GetLogIndexForQuestID, questID)
        if type(index) == "number" and index > 0 then
          offers[questID] = nil
          local ready = read(log.ReadyForTurnIn, questID)
          if ready == nil then ready = read(log.IsComplete, questID) end
          states[writ.id] = ready == true and "objectives_complete" or "active"
        elseif offers[questID] then
          states[writ.id] = "available"
        end
      end
    end
  end
  return states
end

function Tracking.Eligible(state)
  return state == "available" or state == "active" or state == "objectives_complete"
end

function Tracking.Label(state, bagsReady)
  if state == "objectives_complete" then return bagsReady and "Ready for Delivery" or "Active" end
  if state == "active" then return "Active" end
  if state == "available" then return "Available" end
  if state == "completed" then return "Completed Today" end
  return "Unknown"
end
