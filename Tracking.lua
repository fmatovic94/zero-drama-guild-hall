local _,N=...
-- Live positions are transient, self-reported guild messages, never a location history.
-- GetPlayerMapPosition/GetBestMapForUnit are also used by the installed OpenMap.
local T={TTL=30,MOVE_INTERVAL=5,HEARTBEAT_INTERVAL=15}
N.Tracking=T
local scope,positions,states,buckets=nil,{},{},{}
local lastMono,fallbackClock,sampleAt=0,0,-1
local session,sequence,lastSent,nextPublish,published,pendingWithdrawal=nil,0,nil,0,false,nil
local ownRecord,ownReason=nil,"Unavailable"
local closing=false

local function finite(v)
 if type(v)~="number"then return false end
 if type(issecretvalue)=="function"then local ok,secret=pcall(issecretvalue,v);if not ok or secret then return false end end
 return v==v and v~=math.huge and v~=-math.huge
end
local function integer(v,minimum,maximum)return finite(v)and v%1==0 and v>=minimum and v<=maximum end
local function mono()
 local value
 if type(GetTime)=="function"then local ok,n=pcall(GetTime);if ok and finite(n)then value=n end end
 value=value or fallbackClock
 lastMono=math.max(lastMono,value)
 return lastMono
end
local function wall()
 local fn=type(GetServerTime)=="function"and GetServerTime or time
 if type(fn)~="function"then return end
 local ok,value=pcall(fn)
 if ok and integer(value,1,100000000000)then return value end
end
local function changed()
 if type(T.OnChanged)=="function"then pcall(T.OnChanged)end
end
local function character()
 if type(N.CharacterKey)~="function"then return end
 local ok,key=pcall(N.CharacterKey)
 return ok and type(key)=="string"and key~=""and key or nil
end
local function sharingPreference()
 local key=character()
 local saved=type(NoDramaDB)=="table"and NoDramaDB.trackingSharing
 return not(key and type(saved)=="table"and saved[key]==false)
end
function T.IsSharing()return sharingPreference()end
local function purgeQueuedPositions()
 if type(N.queue)~="table"then return end
 for i=#N.queue,1,-1 do
  local packet=N.queue[i]
  if type(packet)=="string"and(packet:sub(1,3)=="L1\t"or packet:sub(1,3)=="L0\t")then table.remove(N.queue,i)end
 end
end
local function context()
 local actual
 if type(GetGuildInfo)=="function"then local ok,name=pcall(GetGuildInfo,"player");if ok then actual=name end end
 if not N.db or type(actual)~="string"or actual==""or actual~=N.guild then return end
 if type(IsInGuild)~="function"then return end
 local ok,inGuild=pcall(IsInGuild);if not ok or inGuild~=true then return end
 return N.db,character(),actual
end
local function ensure()
 if closing then return false end
 local db,key,guild=context()
 local current=db and key and{db=db,key=key,guild=guild}or nil
 local same=scope and current and scope.db==current.db and scope.key==current.key and scope.guild==current.guild
 if not same and(scope or current)then
  purgeQueuedPositions()
  scope=current;positions={};states={};buckets={}
  ownRecord=nil;ownReason="Unavailable";lastSent=nil;sampleAt=-1;nextPublish=0;published=false;pendingWithdrawal=nil;sequence=0
  local stamp=wall()
  session=stamp and string.format("%d-%d-%d",stamp,math.floor(mono()*1000)%1000000,math.random(1,999999))or nil
  changed()
 end
 return scope~=nil
end
function T.OnScopeChanged()ensure()end
function T.OnLogin()closing=false;ensure()end
local function mapInfo(id)
 if not integer(id,1,10000000)or not C_Map or type(C_Map.GetMapInfo)~="function"then return end
 local ok,info=pcall(C_Map.GetMapInfo,id)
 -- Outdoor continent/zone maps only. Instance and micro-dungeon coordinates are not shared.
 if ok and type(info)=="table"and type(info.name)=="string"and(info.mapType==2 or info.mapType==3)then return info end
end
local function sample()
 if not scope or not T.IsSharing()then ownRecord=nil;ownReason="Not sharing";return end
 local me=type(N.Me)=="function"and N.Me()
 if not me or not N.members or not N.members[me]then ownRecord=nil;ownReason="Unavailable";return end
 if type(IsInInstance)~="function"or not C_Map or type(C_Map.GetBestMapForUnit)~="function"or type(C_Map.GetPlayerMapPosition)~="function"then ownRecord=nil;ownReason="Unavailable";return end
 local ok,record=pcall(function()
  if IsInInstance()~=false then return end
  local id=C_Map.GetBestMapForUnit("player");local info=mapInfo(id)
  if not info then return end
  local pos=C_Map.GetPlayerMapPosition(id,"player");if not pos then return end
  local x,y;if type(pos.GetXY)=="function"then x,y=pos:GetXY()else x,y=pos.x,pos.y end
  if not finite(x)or not finite(y)or x<0 or x>1 or y<0 or y>1 then return end
  local ix,iy=math.floor(x*10000+0.5),math.floor(y*10000+0.5)
  if ix==0 and iy==0 then return end
  return{name=me,mapID=id,x=ix/10000,y=iy/10000,zone=info.name,classFile=N.members[me].classFile,receivedAt=mono(),self=true}
 end)
 ownRecord=ok and record or nil;ownReason=ownRecord and"Live"or"Unavailable"
end
local function canSend()
 if not scope or not C_ChatInfo or type(C_ChatInfo.SendAddonMessage)~="function"or type(N.Send)~="function"then return false end
 local me=type(N.Me)=="function"and N.Me()
 if not me or not N.members or not N.members[me]then return false end
 -- Forever reports AreOutgoingAddonChatMessagesRestricted()==true even though guild
 -- addon messages are delivered, so only an explicit chat lockdown blocks sending.
 if type(C_ChatInfo.InChatMessagingLockdown)=="function"then
  local ok,locked=pcall(C_ChatInfo.InChatMessagingLockdown)
  if ok and locked==true then return false end
 end
 return wall()~=nil and session~=nil
end
local function jitter()
 local n=0;for i=1,#(scope and scope.key or"")do n=(n+string.byte(scope.key,i))%100 end
 return n/100
end
local function sendWithdrawal(reason,direct)
 if not canSend()then return false end
 sequence=sequence+1
 local stamp=wall()
 local ok
 if direct and type(N.Pack)=="function"then
  ok=pcall(C_ChatInfo.SendAddonMessage,N.prefix,N.Pack("L0",reason,stamp,session,sequence),"GUILD")
 else ok=N.Send("L0",reason,stamp,session,sequence)end
 if ok then published=false;pendingWithdrawal=nil;lastSent=nil end
 return ok
end
function T.SetSharing(enabled)
 if type(enabled)~="boolean"then return false end
 ensure();local key=character();if not key then return false end
 NoDramaDB=type(NoDramaDB)=="table"and NoDramaDB or{}
 NoDramaDB.trackingSharing=type(NoDramaDB.trackingSharing)=="table"and NoDramaDB.trackingSharing or{}
 NoDramaDB.trackingSharing[key]=enabled
 purgeQueuedPositions();ownRecord=nil;sampleAt=-1;nextPublish=0
 if not enabled then
  ownReason="Not sharing";pendingWithdrawal="S"
  sendWithdrawal("S")
 else pendingWithdrawal=nil;lastSent=nil;sample()end
 changed();return true
end
local function prune(now)
 local dirty=false
 for name,record in pairs(positions)do
  local member=N.members and N.members[name]
  if not member or member.online~=true or now-record.receivedAt+(record.sourceAge or 0)>=T.TTL then positions[name]=nil;dirty=true end
 end
 for name,state in pairs(states)do
  local member=N.members and N.members[name]
  if not member or member.online~=true or now-state.receivedAt>90 then states[name]=nil;buckets[name]=nil end
 end
 for name in pairs(buckets)do if not N.members or not N.members[name]then buckets[name]=nil end end
 if dirty then changed()end
end
function T.OnUpdate(elapsed)
 if finite(elapsed)and elapsed>0 then fallbackClock=fallbackClock+elapsed end
 if not ensure()then return end
 local now=mono();prune(now)
 if sampleAt>=0 and now-sampleAt<0.5 then return end
 sampleAt=now
 local previous=ownRecord
 sample()
 if not ownRecord and(previous or published)then
  purgeQueuedPositions();pendingWithdrawal=T.IsSharing()and"U"or"S"
  changed()
 end
 if ownRecord and(not previous or previous.mapID~=ownRecord.mapID or previous.x~=ownRecord.x or previous.y~=ownRecord.y)then changed()end
 if pendingWithdrawal then
  if sendWithdrawal(pendingWithdrawal)then nextPublish=now+1 end
  return
 end
 if not ownRecord or not canSend()or now<nextPublish then return end
 -- Never bury current positions behind a long backlog of moderation/poll traffic.
 if type(N.queue)~="table"or #N.queue>8 then nextPublish=now+1;return end
 local moved=not lastSent or lastSent.mapID~=ownRecord.mapID or lastSent.x~=ownRecord.x or lastSent.y~=ownRecord.y
 local due=not lastSent or now-lastSent.at>=(moved and T.MOVE_INTERVAL+jitter()/10 or T.HEARTBEAT_INTERVAL+jitter())
 if not due then return end
 purgeQueuedPositions();sequence=sequence+1
 if N.Send("L1",ownRecord.mapID,math.floor(ownRecord.x*10000+0.5),math.floor(ownRecord.y*10000+0.5),wall(),session,sequence)then
  lastSent={mapID=ownRecord.mapID,x=ownRecord.x,y=ownRecord.y,at=now};published=true;nextPublish=now+T.MOVE_INTERVAL+jitter()/10
 else nextPublish=now+1 end
end
local function wireInteger(value,minimum,maximum)
 if type(value)~="string"or #value>12 or not value:match("^%d+$")then return end
 local n=tonumber(value);if integer(n,minimum,maximum)then return n end
end
local function acceptOrder(sender,stamp,token,seq,now,sourceAge)
 if type(token)~="string"or #token<3 or #token>48 or not token:match("^[%w%-]+$")then return false end
 local old=states[sender]
 if old then
  if old.session==token then if seq<=old.seq then return false end
  else
   if stamp<old.stamp then return false end
   for _,retired in ipairs(old.retired or{})do if retired==token then return false end end
  end
 end
 local retired=old and old.retired or{}
 if old and old.session~=token then retired[#retired+1]=old.session;while #retired>4 do table.remove(retired,1)end end
 states[sender]={session=token,seq=seq,stamp=stamp,receivedAt=now,sourceAge=sourceAge,retired=retired}
 return true
end
function T.Receive(op,p,sender)
 if(op~="L1"and op~="L0")or not ensure()or type(p)~="table"or type(sender)~="string"then return false end
 local member=N.members and N.members[sender]
 if not member or member.online~=true or sender==N.Me()then return false end
 local now=mono();local bucket=buckets[sender]
 if not bucket or now-bucket.at>=1 then bucket={at=now,count=0};buckets[sender]=bucket end
 bucket.count=bucket.count+1;if bucket.count>5 then return false end
 local stamp,token,seq,id,x,y,info,reason
 if op=="L1"then
  if #p~=7 then return false end
  id=wireInteger(p[2],1,10000000);x=wireInteger(p[3],0,10000);y=wireInteger(p[4],0,10000)
  stamp=wireInteger(p[5],1,100000000000);token=p[6];seq=wireInteger(p[7],1,1000000000)
  if not id or not x or not y or(x==0 and y==0)then return false end
  info=mapInfo(id);if not info then return false end
 else
  if #p~=5 or(p[2]~="S"and p[2]~="U")then return false end
  reason=p[2];stamp=wireInteger(p[3],1,100000000000);token=p[4];seq=wireInteger(p[5],1,1000000000)
 end
 local epoch=wall()
 if not stamp or not epoch or not seq or stamp>epoch+10 or epoch-stamp>=T.TTL then return false end
 local sourceAge=math.max(0,epoch-stamp)
 if not acceptOrder(sender,stamp,token,seq,now,sourceAge)then return false end
 if op=="L1"then
  positions[sender]={name=sender,mapID=id,x=x/10000,y=y/10000,zone=info.name,classFile=member.classFile,receivedAt=now,sourceAge=sourceAge,sourceTime=stamp}
 else positions[sender]=nil;states[sender].reason=reason end
 changed();return true
end
function T.GetPositions()
 if not ensure()then return{}end
 local now=mono();prune(now)
 if sampleAt<0 or now-sampleAt>=1 then sample();sampleAt=now end
 local list={}
 for name,record in pairs(positions)do
  local member=N.members[name]
  local copy={name=name,mapID=record.mapID,x=record.x,y=record.y,zone=record.zone,receivedAt=record.receivedAt,age=math.max(0,now-record.receivedAt+(record.sourceAge or 0)),classFile=member.classFile,sourceTime=record.sourceTime}
  list[#list+1]=copy
 end
 if ownRecord then
  local own={};for key,value in pairs(ownRecord)do own[key]=value end
  own.age=0;list[#list+1]=own
 end
 table.sort(list,function(a,b)return a.name<b.name end)
 return list
end
function T.GetStatus(name)
 if not ensure()then return"Unavailable"end
 if name==N.Me()then if not T.IsSharing()then return"Not sharing"end;sample();return ownReason,0 end
 local member=N.members and N.members[name]
 if member and member.online~=true then return"Offline"end
 local now=mono();prune(now)
 local record=positions[name];if record then return"Live",math.max(0,now-record.receivedAt+(record.sourceAge or 0))end
 local state=states[name]
 if state and now-state.receivedAt+(state.sourceAge or 0)<T.TTL then
  if state.reason=="S"then return"Not sharing",now-state.receivedAt+(state.sourceAge or 0)end
  if state.reason=="U"then return"Unavailable",now-state.receivedAt+(state.sourceAge or 0)end
 end
 return"No signal"
end
function T.OnLogout()
 if ensure()then purgeQueuedPositions();if published then sendWithdrawal("U",true)end end
 closing=true
 positions={};states={};buckets={};ownRecord=nil;scope=nil
 changed()
end
