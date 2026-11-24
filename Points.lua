local _,N=...
-- Guild points. Only officers and the GM change them; they are exempt from scoring.
-- Each member's total is an absolute value with a (stamp, seq, by) version, so replays and
-- late snapshots never undo a newer change. Snapshots are accepted from officers only.
N.Points={};local P=N.Points
P.LIMIT=1000000
local MAX_DELTA=100000
local HISTORY=10
local SNAPSHOT_THROTTLE=60
local unpack=unpack or table.unpack
local function clock()return GetServerTime and GetServerTime()or time()end
local function integer(v,low,high)
 v=tonumber(v);if not v or v~=v or v%1~=0 or v<low or v>high then return end
 return v
end
local function store()
 if not N.db then return end
 N.db.points=type(N.db.points)=="table"and N.db.points or{}
 return N.db.points
end
local function newer(a,b)
 if not b then return true end
 if a.stamp~=b.stamp then return a.stamp>b.stamp end
 if a.seq~=b.seq then return a.seq>b.seq end
 return tostring(a.by)>tostring(b.by)
end
local function changed()
 if N.window and N.window:IsShown()and N.page=="Roster"and N.Render then N.Render()end
end
function P.IsExempt(name)return N.IsOfficer(name)end
function P.CanEdit()return N.db~=nil and N.members[N.Me()]~=nil and N.IsOfficer(N.Me())end
function P.Record(name)
 local list=store();local r=list and list[N.Full(name)]
 if type(r)=="table"and integer(r.points,-P.LIMIT,P.LIMIT)then return r end
end
function P.Get(name)
 if P.IsExempt(name)then return end
 local r=P.Record(name);return r and r.points or 0
end
function P.SortValue(m)return P.Get(m.name)or-P.LIMIT-1 end
function P.Display(m)
 local points=P.Get(m.name)
 if not points then return"|cff777777Exempt|r"end
 return(points<0 and"|cffff6060"or(points>0 and"|cffffd100"or"|cffb0b0b0"))..points.."|r"
end
local function ago(stamp)
 local seconds=math.max(0,clock()-(stamp or clock()))
 if seconds<3600 then return math.max(1,math.floor(seconds/60)).." min ago"end
 if seconds<86400 then return math.floor(seconds/3600).." h ago"end
 return math.floor(seconds/86400).." days ago"
end
local function short(name)local safe=N.Safe(name);return safe:match("^[^-]+")or safe end
function P.DetailText(m)
 local points=P.Get(m.name)
 if not points then return"Points: exempt (officers and the GM are not scored)"end
 local lines={"Points: |cffffd100"..points.."|r"}
 local r=P.Record(m.name)
 for i=1,math.min(3,r and type(r.history)=="table"and #r.history or 0)do
  local h=r.history[i]
  lines[#lines+1]=(h.delta>0 and"+"or"")..h.delta.." by "..short(h.by)..(h.reason~=""and": "..N.Safe(h.reason)or"").." ("..ago(h.stamp)..")"
 end
 return table.concat(lines,"\n")
end
local function apply(target,points,stamp,seq,by,delta,reason)
 local list=store();if not list then return false end
 local old=list[target];local record={points=points,stamp=stamp,seq=seq,by=by}
 if type(old)=="table"and integer(old.points,-P.LIMIT,P.LIMIT)and not newer(record,old)then return false end
 record.history=type(old)=="table"and type(old.history)=="table"and old.history or{}
 if delta then
  table.insert(record.history,1,{delta=delta,by=by,reason=reason or"",stamp=stamp})
  while #record.history>HISTORY do table.remove(record.history)end
 end
 list[target]=record
 return true
end
function P.Adjust(name,delta,reason)
 local target=N.Full(name);delta=integer(delta,-MAX_DELTA,MAX_DELTA)
 if not P.CanEdit()or not N.members[target]or P.IsExempt(target)or not delta or delta==0 then return false end
 local points=math.max(-P.LIMIT,math.min(P.LIMIT,(P.Get(target)or 0)+delta))
 N.db.pointsSeq=(integer(N.db.pointsSeq,0,1000000000)or 0)+1
 local stamp,seq=clock(),N.db.pointsSeq
 reason=N.Clip(N.Safe(reason or""):gsub("^%s+",""):gsub("%s+$",""),60)
 if not N.Send("S1",target,points,stamp,seq,delta,reason)then N.Notify("The addon message queue is full. Try again in a moment.");return false end
 apply(target,points,stamp,seq,N.Me(),delta,reason)
 N.Notify((delta>0 and"Gave "or"Took ")..math.abs(delta).." points "..(delta>0 and"to "or"from ")..short(target)..". New total: "..points..".")
 changed();return true
end
local outbox={}
local function snapshot(since)
 local list=store();if not list then return end
 local entries={}
 for name,r in pairs(list)do
  if N.members[name]and not P.IsExempt(name)and integer(r.points,-P.LIMIT,P.LIMIT)and(r.stamp or 0)>since then entries[#entries+1]={name,r.points,r.stamp,r.seq,r.by}end
 end
 table.sort(entries,function(a,b)return a[3]<b[3]end)
 local fields={}
 local function flush()if #fields>0 then outbox[#outbox+1]=N.Pack("SS",unpack(fields));fields={}end end
 for _,e in ipairs(entries)do
  local candidate=N.Pack("SS",unpack(fields))
  if #fields>0 and #candidate+#N.Pack(unpack(e))+1>240 then flush()end
  for _,v in ipairs(e)do fields[#fields+1]=v end
 end
 flush()
end
local replyAt,replySince,heardSnapshotAt,lastReplyTo=nil,nil,0,{}
function P.Receive(op,p,sender)
 local list=store();if not list or not N.members[sender]then return end
 if op=="S1"and #p==7 then
  local target=N.Full(p[2]);local points=integer(p[3],-P.LIMIT,P.LIMIT);local stamp=integer(p[4],1,100000000000)
  local seq=integer(p[5],1,1000000000);local delta=integer(p[6],-MAX_DELTA,MAX_DELTA)
  if not N.IsOfficer(sender)or not N.members[target]or P.IsExempt(target)or not points or not stamp or not seq or not delta or stamp>clock()+300 then return end
  local reason=N.Clip(N.Safe(p[7]),60)
  if apply(target,points,stamp,seq,sender,delta,reason)then
   if target==N.Me()and sender~=N.Me()then
    N.Notify(short(sender)..(delta>0 and" gave you "or" took ")..math.abs(delta).." points"..(delta<0 and" from you"or"")..(reason~=""and": "..reason or"")..". You now have "..points..".")
   end
   changed()
  end
 elseif op=="SS"and(#p-1)%5==0 and #p>1 then
  if not N.IsOfficer(sender)then return end
  if sender~=N.Me()then heardSnapshotAt=clock()end
  local dirty=false
  for i=2,#p,5 do
   local target=N.Full(p[i]);local points=integer(p[i+1],-P.LIMIT,P.LIMIT);local stamp=integer(p[i+2],1,100000000000)
   local seq=integer(p[i+3],1,1000000000);local by=N.Full(p[i+4])
   if N.members[target]and not P.IsExempt(target)and points and stamp and seq and stamp<=clock()+300 then
    if apply(target,points,stamp,seq,by)then dirty=true end
   end
  end
  if dirty then changed()end
 elseif op=="SQ"and #p==2 and sender~=N.Me()then
  local since=integer(p[2],0,100000000000);if not since or not P.CanEdit()then return end
  local now=clock()
  if lastReplyTo[sender]and now-lastReplyTo[sender]<SNAPSHOT_THROTTLE then return end
  lastReplyTo[sender]=now
  replySince=math.min(replySince or since,since)
  -- A random delay lets one online officer answer while the others hear it and stay quiet.
  replyAt=replyAt or now+2+math.random(0,4)
 end
end
function P.Newest()
 local newest=0;local list=store()
 for _,r in pairs(list or{})do if type(r)=="table"and(tonumber(r.stamp)or 0)>newest then newest=tonumber(r.stamp)end end
 return newest
end
local queryAt
function P.OnLogin()queryAt=clock()+15 end
function P.Tick()
 if not N.db then return end
 local now=clock()
 if queryAt and now>=queryAt then queryAt=nil;N.Send("SQ",P.Newest())end
 if replyAt and now>=replyAt then
  if now-heardSnapshotAt>8 then snapshot(replySince or 0)end
  replyAt,replySince=nil,nil
 end
 while #outbox>0 and N.queue and #N.queue<80 do N.queue[#N.queue+1]=table.remove(outbox,1)end
end
local driver=CreateFrame("Frame");local wait=0
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent",function()P.OnLogin();driver:UnregisterEvent("PLAYER_ENTERING_WORLD")end)
driver:SetScript("OnUpdate",function(_,dt)wait=wait+dt;if wait>=1 then wait=0;P.Tick()end end)
