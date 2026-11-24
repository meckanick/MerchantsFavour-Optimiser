-- Run from repository root: lua5.1 tests/writ-data-regression.lua
dofile("MerchantsFavourOptimiser/WritData.lua")
local ids, quests = {}, {}
local rewards = {Journeyman=75, Expert=125, Artisan=200}
local professions = {Alchemy=true, Blacksmithing=true, Engineering=true, Leatherworking=true, Tailoring=true}
local function positive(n) return type(n)=="number" and n>0 and n<math.huge and n==math.floor(n) end
assert(#MFO_WritData>0)
for _, w in ipairs(MFO_WritData) do
  assert(positive(w.id) and positive(w.questID))
  assert(not ids[w.id] and not quests[w.questID], "Duplicate Writ or quest")
  ids[w.id], quests[w.questID] = true, true
  assert(rewards[w.tier] and rewards[w.tier]==w.reputation)
  assert(professions[w.profession])
  assert(w.faction=="Both" or w.faction=="Alliance" or w.faction=="Horde")
  assert(w.daily==true and type(w.sourceKey)=="string" and #w.sourceKey>0)
  assert(type(w.items)=="table" and #w.items>0)
  local seen={}
  for _, item in ipairs(w.items) do
    assert(positive(item.id) and positive(item.qty) and item.id~=w.id and not seen[item.id])
    seen[item.id]=true
  end
end
print("Writ database validation passed: "..#MFO_WritData)
