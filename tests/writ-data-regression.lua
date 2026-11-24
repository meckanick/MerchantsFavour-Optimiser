-- Run from repository root: lua5.1 tests/writ-data-regression.lua
dofile("MerchantsFavourOptimiser/WritData.lua")
local ids, quests, rows = {}, {}, {}
local rewards = {Journeyman=75, Expert=125, Artisan=200}
local professions = {Alchemy=true, Blacksmithing=true, Engineering=true, Leatherworking=true, Tailoring=true}
local function positive(n) return type(n)=="number" and n>0 and n<math.huge and n==math.floor(n) end
assert(#MFO_WritData == 130)
local previous = 0
for _, w in ipairs(MFO_WritData) do
  assert(positive(w.id) and positive(w.questID))
  assert(not ids[w.id] and not quests[w.questID], "Duplicate Writ or quest")
  ids[w.id], quests[w.questID] = true, true
  assert(rewards[w.tier] and rewards[w.tier]==w.reputation)
  assert(w.id > previous and w.sourceKey == tostring(w.id))
  previous = w.id
  rows[w.id] = w
  assert(type(w.professions) == "table" and #w.professions > 0)
  local lastProfession = ""
  for _, profession in ipairs(w.professions) do
    assert(professions[profession] and profession > lastProfession)
    lastProfession = profession
  end
  assert(w.faction=="Both" or w.faction=="Alliance" or w.faction=="Horde")
  assert(w.daily == true)
  assert(type(w.items)=="table" and #w.items>0)
  local seen={}
  for _, item in ipairs(w.items) do
    assert(positive(item.id) and positive(item.qty) and item.id~=w.id and not seen[item.id])
    seen[item.id]=true
  end
end

assert(table.concat(rows[264065].professions, ",") == "Alchemy,Engineering")
assert(table.concat(rows[264069].professions, ",") == "Blacksmithing,Engineering")
assert(table.concat(rows[264144].professions, ",") == "Leatherworking,Tailoring")
assert(rows[264124].questID == 94324 and rows[264139].questID == 94339)
assert(not rows[264011] and not rows[264013], "Unresolved faction leaked into data")

dofile("MerchantsFavourOptimiser/WritCalculations.lua")
local fuel = rows[264065]
local result = assert(MFO_WritCalculations.calculate(fuel, function(id)
  if id == 264065 then return 100 end
  if id == 9061 then return 25 end
end))
assert(result.total == 125 and result.costPerRep == 1)
assert(result.shopping[264065] == 1 and result.shopping[9061] == 1)
print("Writ database and calculation validation passed: " .. #MFO_WritData)
