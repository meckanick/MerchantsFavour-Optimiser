-- Stage 1: pure crate readiness model. No UI or game API dependencies.
MFO_CrateTracking = {}
local T=MFO_CrateTracking
local function quantity(value)
 value=tonumber(value) or 0
 if value~=value or value<0 then return 0 end
 return math.floor(value)
end
-- Entries: {crateID, quantity, materialID, materialQty}.
-- The caller supplies an explicit bundle; never infer one from a shopping row.
-- Allocation is deterministic and never reuses the same inventory.
function T.Evaluate(entries,bags,bank,bankScanTime)
 local output,bagLeft,bankLeft={}, {}, {}
 bags=bags or {};bank=bank or {}
 local ordered={}
 for i,entry in ipairs(entries or {}) do
  if type(entry)=="table" then
   ordered[#ordered+1]={entry=entry,sequence=i}
  end
 end
 table.sort(ordered,function(a,b)
  local ai,bi=quantity(a.entry.crateID),quantity(b.entry.crateID)
  if ai~=bi then return ai<bi end
  return a.sequence<b.sequence
 end)
 local function take(source,left,id,need)
  if not id or need<=0 then return 0 end
  if left[id]==nil then left[id]=quantity(source[id]) end
  local used=math.min(need,left[id])
  left[id]=left[id]-used
  return used
 end
 for _,record in ipairs(ordered) do
  local e=record.entry
  local id,mat=quantity(e.crateID),quantity(e.materialID)
  local count,per=quantity(e.quantity),quantity(e.materialQty)
  if id>0 and mat>0 and count>0 and per>0 then
   for n=1,count do
    local crateBag=take(bags,bagLeft,id,1)
    local crateBank=crateBag==0 and take(bank,bankLeft,id,1) or 0
    local matBag=take(bags,bagLeft,mat,per)
    local matBank=take(bank,bankLeft,mat,per-matBag)
    local haveCrate=crateBag+crateBank>0
    local missing=per-matBag-matBank
    local state
    if not haveCrate then state="missing_crate"
    elseif missing>0 then state="needs_materials"
    elseif crateBank>0 or matBank>0 then state="bank_stock"
    else state="ready_to_fill" end
    output[#output+1]={crateID=id,materialID=mat,unit=n,status=state,
     crateInBags=crateBag,crateInBank=crateBank,
     materialsInBags=matBag,materialsInBank=matBank,
     materialsRequired=per,materialsMissing=missing,
     bankSnapshot=bankScanTime}
   end
  end
 end
 return output
end
-- Never infer a filled/turn-in-ready crate from ordinary item ownership.
-- Filled crate detection remains unverified until a Forever-specific signal is validated.
function T.FilledStatus() return "unverified" end
