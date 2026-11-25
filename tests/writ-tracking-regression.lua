local path="MerchantsFavourOptimiser/WritTracking.lua"
MFO_WritData={
  {id=10,questID=910,daily=true},
  {id=11,questID=911,daily=true},
}
MFO_DB={useOwned=true,bankCounts={[100]=9}}
local character,realm,faction="Alice","First","Alliance"
local now,deadline=100000,100600
local offered,logged,objectiveComplete,flag=nil,{},{},{}
UnitName=function() return character end
GetRealmName=function() return realm end
UnitFactionGroup=function() return faction end
GetQuestID=function() return offered end
GetServerTime=function() return now end
C_DateAndTime={GetSecondsUntilDailyReset=function() return deadline-now end}
C_QuestLog={
  GetLogIndexForQuestID=function(id) return logged[id] end,
  IsComplete=function(id) return objectiveComplete[id] end,
  IsQuestFlaggedCompleted=function(id) return flag[id] or false end,
}
local serverClock,questLog=GetServerTime,C_QuestLog
local function reload()
  dofile(path)
  return MFO_WritTracking
end
local tracking=reload()
local function state(id) return tracking.Snapshot()[id or 10] end
assert(state()==nil,"absent quest information is unknown")
offered=910
assert(tracking.OnEvent("QUEST_DETAIL") and state()=="available")
logged[910]=1
tracking.OnEvent("QUEST_ACCEPTED",910)
assert(state()=="active","delayed objective information still permits active status")
objectiveComplete[911]=true
assert(state()=="active","another quest's objectives do not count")
objectiveComplete[910]=true
C_QuestLog.ReadyForTurnIn=function() return false end
assert(state()=="active","an explicit turn-in restriction wins over completed objectives")
C_QuestLog.ReadyForTurnIn=nil
assert(tracking.Label(state(),false)=="Active")
assert(tracking.Label(state(),true)=="Ready for Delivery")
assert(not tracking.OnEvent("QUEST_TURNED_IN",999))
assert(tracking.OnEvent("QUEST_TURNED_IN",910))
assert(state()=="completed","turn-in wins over stale quest log and completion flag")
assert(state(11)==nil,"another Writ stays independent")
logged,objectiveComplete={},{}
tracking=reload()
assert(state()=="completed","saved turn-in survives reload with delayed quest info")
assert(MFO_DB.useOwned and MFO_DB.bankCounts[100]==9)

character="Bob"
assert(state()==nil)
character,realm="Alice","Second"
assert(state()==nil)
realm,faction="First","Horde"
assert(state()==nil)
faction="Alliance"
assert(state()=="completed")
offered=911
tracking.OnEvent("QUEST_DETAIL")
assert(state(11)=="available")
now=deadline-1
assert(state()=="completed" and state(11)=="available")
now,deadline=deadline,deadline+86400
assert(state()==nil and state(11)==nil,"server reset expires completions and old offers")
assert(next(MFO_DB.writQuestCompletions[tracking.CharacterKey()])==nil)
flag[911]=true
assert(state(11)=="completed","a server completion flag covers pre-install turn-ins")
flag[911]=nil
assert(state(11)==nil,"a false flag alone proves neither availability nor activity")

offered=910
tracking.OnEvent("QUEST_DETAIL")
assert(state()=="available")
local revision=tracking.PollReset()
deadline=deadline+1
assert(tracking.PollReset()==revision and state()=="available","clock rounding preserves the reset window")
tracking.OnEvent("QUEST_ACCEPTED",910)
assert(state()==nil,"an accepted offer waits for quest-log data")
logged[910]=1
assert(state()=="active")
logged[910]=nil
tracking.OnEvent("QUEST_REMOVED",910)
assert(state()==nil,"abandoning a quest does not infer availability or completion")

GetServerTime=nil
assert(tracking.OnEvent("QUEST_TURNED_IN",910))
tracking=reload()
C_QuestLog=nil
assert(state()==nil and not tracking.Eligible(state()),"undated completion cannot become eligible")
GetServerTime,C_QuestLog=serverClock,questLog
logged[910]=1
assert(state()==nil,"uncertain completion wins over potentially stale activity")
logged[910]=nil
assert(tracking.OnEvent("QUEST_DETAIL") and state()=="available","a fresh offer resolves an undated record")
C_DateAndTime.GetSecondsUntilDailyReset=function() error("clock unavailable") end
assert(tracking.OnEvent("QUEST_TURNED_IN",910) and state()=="completed","known deadline survives countdown outage")
now=deadline+1
assert(state()==nil,"server time expires a known completion during a countdown outage")
GetQuestID=nil
assert(not tracking.OnEvent("QUEST_DETAIL") and state()==nil)
UnitName=nil
flag[911]=true
assert(state(11)==nil,"missing character identity cannot use quest data")
print("PASS: Writ quest evidence, reset windows, reload, identity isolation and unavailable APIs")
