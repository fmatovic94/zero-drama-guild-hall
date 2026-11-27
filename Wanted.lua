local _,N=...
-- Kill list and wanted levels for enemy players who kill guild members.
-- WoW Forever closes the combat log to addons, so a death is credited to the
-- enemy players who were targeting the victim in the seconds before it; each
-- victim reports their own death. Officers keep a separate kill-on-sight list.
local W={};N.Wanted=W
W.MAX_STARS=6
W.HALF_LIFE=7*86400
W.CAMP_WINDOW=15*60
W.CAMP_FACTOR=1.5
W.REVENGE_WEIGHT=0.5
W.STAR_BASE=1.8
local KEEP=60*86400
local MAX_EVENTS=1000
local ATTACK_WINDOW=8
local ALERT_STARS=3
local ALERT_REPEAT=300
local SIGHTING_REPEAT=120
local SYNC_THROTTLE=60
local unpack=unpack or table.unpack
local STAR="Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local SKULL="Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
W.STAR,W.SKULL=STAR,SKULL
-- Heat needed for each star: 1.8^n - 1, so every star takes about 1.8x the last.
W.thresholds={}
for n=1,W.MAX_STARS do W.thresholds[n]=W.STAR_BASE^n-1 end

local function clock()return GetServerTime and GetServerTime()or time()end
local function plain(v)if type(issecretvalue)=="function"and issecretvalue(v)then return nil end;return v end
local function integer(v,low,high)
 v=tonumber(v);if not v or v~=v or v%1~=0 or v<low or v>high then return end
 return v
end
local function clean(s,limit)return(N.Clip(N.Safe(s or""),limit or 40):gsub("[,;]",""))end
local function store()
 if not N.db then return end
 local s=type(N.db.wanted)=="table"and N.db.wanted or{}
 s.events=type(s.events)=="table"and s.events or{}
 s.kos=type(s.kos)=="table"and s.kos or{}
 s.info=type(s.info)=="table"and s.info or{}
 N.db.wanted=s
 return s
end
local function changed()
 if N.window and N.window:IsShown()and N.page=="Kill list"and N.Render then N.Render()end
 if W.RefreshPlates then W.RefreshPlates()end
end
local function short(name)return(name or""):match("^[^-]+")or name or""end
W.Short=short
local function fullFromUnit(unit)
 local name,realm=plain(UnitName(unit))
 if type(name)~="string"or name==""or name==UNKNOWNOBJECT then return end
 realm=plain(realm)
 return N.Full(type(realm)=="string"and realm~=""and name.."-"..realm or name)
end
local function enemyPlayer(unit)
 if not plain(UnitExists(unit))or not plain(UnitIsPlayer(unit))or not plain(UnitCanAttack("player",unit))then return end
 local full=fullFromUnit(unit)
 if full and not N.members[full]then return full end
end
local function noteInfo(full,unit)
 local s=store();if not s or not full then return end
 local info=s.info[full]or{}
 if unit then
  local _,classFile=UnitClass(unit);local race=UnitRace(unit);local level=plain(UnitLevel(unit))
  info.class=plain(classFile)or info.class;info.race=plain(race)or info.race
  if type(level)=="number"and level>0 then info.level=level end
 end
 s.info[full]=info
 return info
end

function W.Status(full)
 local s=store();if not s or not full then return{heat=0,stars=0}end
 local now=clock();local kills,victims,lastBy,raw,camps,revenge,lastKill={},{},{},0,0,0,nil
 for _,e in pairs(s.events)do
  if e.killer==full then
   if e.kind=="K"then kills[#kills+1]=e else revenge=revenge+0.5^((now-e.stamp)/W.HALF_LIFE)end
  end
 end
 table.sort(kills,function(a,b)return a.stamp<b.stamp end)
 local count,credit=0,0
 for _,e in ipairs(kills)do
  local weight=(e.credit or 1000)/1000*0.5^((now-e.stamp)/W.HALF_LIFE)
  if lastBy[e.by]and e.stamp-lastBy[e.by]<=W.CAMP_WINDOW then weight=weight*W.CAMP_FACTOR;camps=camps+1 end
  lastBy[e.by]=e.stamp;victims[e.by]=true
  raw=raw+weight;count=count+1;credit=credit+(e.credit or 1000)/1000;lastKill=e
 end
 local distinct=0;for _ in pairs(victims)do distinct=distinct+1 end
 local spread=math.min(2,1+0.15*math.max(0,distinct-1))
 local heat=math.max(0,raw*spread-W.REVENGE_WEIGHT*revenge)
 local stars=0
 for n=1,W.MAX_STARS do if heat>=W.thresholds[n]-1e-9 then stars=n end end
 local kos=s.kos[full];kos=type(kos)=="table"and kos.active and kos or nil
 return{heat=heat,stars=stars,kills=count,credit=credit,victims=distinct,spread=spread,raw=raw,camps=camps,revenge=revenge,last=lastKill,kos=kos,info=s.info[full]or{}}
end
function W.StarText(stars,size)
 size=size or 12;local parts={}
 for n=1,W.MAX_STARS do
  parts[n]="|T"..STAR..":"..size..":"..size..":0:0:64:64:0:64:0:64"..(n<=stars and""or":70:70:70").."|t"
 end
 return table.concat(parts)
end
function W.List()
 local s=store();if not s then return{}end
 local names={}
 for _,e in pairs(s.events)do names[e.killer]=true end
 for name,k in pairs(s.kos)do if type(k)=="table"and k.active then names[name]=true end end
 local list={}
 for name in pairs(names)do
  local st=W.Status(name);st.name=name
  if st.kos or st.kills>0 then list[#list+1]=st end
 end
 table.sort(list,function(a,b)
  if(a.kos~=nil)~=(b.kos~=nil)and a.stars==b.stars then return a.kos~=nil end
  if a.stars~=b.stars then return a.stars>b.stars end
  if math.abs(a.heat-b.heat)>1e-9 then return a.heat>b.heat end
  return a.name<b.name
 end)
 return list
end
function W.Events(full)
 local s=store();local list={}
 for _,e in pairs(s and s.events or{})do if e.killer==full then list[#list+1]=e end end
 table.sort(list,function(a,b)return a.stamp>b.stamp end)
 return list
end
function W.Age(stamp)
 local sec=math.max(0,clock()-(stamp or clock()))
 if sec<60 then return"just now"elseif sec<3600 then return math.floor(sec/60).." min ago"elseif sec<86400 then return math.floor(sec/3600).." h ago"end
 return math.floor(sec/86400).." d ago"
end
local function prune(s)
 local now,list=clock(),{}
 for id,e in pairs(s.events)do if now-e.stamp>KEEP then s.events[id]=nil else list[#list+1]=e end end
 if #list>MAX_EVENTS then
  table.sort(list,function(a,b)return a.stamp<b.stamp end)
  for i=1,#list-MAX_EVENTS do s.events[list[i].id]=nil end
 end
end
local function addEvent(e)
 local s=store();if not s then return false end
 if not N.members[e.by]or N.members[e.killer]or e.stamp>clock()+300 or clock()-e.stamp>KEEP then return false end
 e.id=e.by..":"..e.stamp..":"..e.kind..":"..e.killer
 if s.events[e.id]then return false end
 s.events[e.id]=e
 local info=s.info[e.killer]or{};info.class=info.class or e.class;info.race=info.race or e.race;s.info[e.killer]=info
 prune(s)
 return true
end

local function position()
 local zone=plain(GetZoneText and GetZoneText())or""
 local x,y=0,0
 if C_Map and C_Map.GetBestMapForUnit then
  local map=C_Map.GetBestMapForUnit("player")
  local pos=map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map,"player")
  if pos then x,y=math.floor((plain(pos.x)or 0)*1000),math.floor((plain(pos.y)or 0)*1000)end
 end
 return clean(zone,40),x,y
end
local function eventFields(e)return e.kind,e.killer,e.class or"",e.race or"",e.stamp,e.zone or"",e.x or 0,e.y or 0,e.credit or 1000 end
local function report(e)
 if addEvent(e)then N.Send("K1",eventFields(e));changed();return true end
end

local attackers={}
local function scanUnit(unit)
 local full=enemyPlayer(unit)
 if not full then return end
 noteInfo(full,unit)
 if plain(UnitIsUnit(unit.."target","player"))then attackers[full]={at=GetTime(),unit=unit}end
end
local function scanAll()
 for _,unit in ipairs({"target","focus","mouseover"})do scanUnit(unit)end
 if C_NamePlate and C_NamePlate.GetNamePlates then
  for _,plate in ipairs(C_NamePlate.GetNamePlates()or{})do
   local unit=plate.namePlateUnitToken or(plate.UnitFrame and plate.UnitFrame.unit)
   if unit then scanUnit(unit)end
  end
 end
end
W.ScanAttackers=scanAll
local function inBattleground()
 local inside,kind=IsInInstance()
 return inside and(kind=="pvp"or kind=="arena")
end
function W.OnDeath()
 if not N.db or inBattleground()then return end
 scanAll()
 local now=GetTime();local list={}
 for full,a in pairs(attackers)do if now-a.at<=ATTACK_WINDOW then list[#list+1]=full end end
 attackers={}
 if #list==0 then return end
 table.sort(list)
 while #list>5 do table.remove(list)end
 local zone,x,y=position();local stamp=clock();local s=store()
 local credit=math.floor(1000/#list)
 for _,full in ipairs(list)do
  local info=s.info[full]or{}
  report({kind="K",killer=full,by=N.Me(),stamp=stamp,zone=zone,x=x,y=y,credit=credit,class=info.class,race=info.race})
 end
 local names={}
 for i,full in ipairs(list)do local st=W.Status(full);names[i]=short(full).." "..W.StarText(st.stars,10)end
 N.Notify("|cffff4040Killed by "..table.concat(names,", ").."|r. Added to the guild kill list.")
end
function W.OnPartyKill(attacker,target)
 attacker,target=plain(attacker),plain(target)
 if not N.db or attacker~=plain(UnitGUID("player"))or type(target)~="string"or not target:find("^Player%-")or inBattleground()then return end
 local _,classFile,_,race,_,name,realm=GetPlayerInfoByGUID(target)
 name,realm=plain(name),plain(realm)
 if type(name)~="string"then return end
 local full=N.Full(type(realm)=="string"and realm~=""and name.."-"..realm or name)
 local st=W.Status(full)
 if st.kills==0 and not st.kos then return end
 local zone,x,y=position()
 if report({kind="R",killer=full,by=N.Me(),stamp=clock(),zone=zone,x=x,y=y,credit=1000,class=plain(classFile),race=plain(race)})then
  N.Notify("|cff40ff40Revenge!|r You took down "..short(full).." "..W.StarText(st.stars,10)..(st.kos and" (kill on sight)"or"")..".")
 end
end
function W.CanEdit()return N.db~=nil and N.members[N.Me()]~=nil and N.IsOfficer(N.Me())end
function W.SetKOS(full,active,reason)
 local s=store();full=full and N.Full(full)
 if not s or not W.CanEdit()or not full or N.members[full]then return false end
 reason=clean(reason,80);local stamp=clock()
 local old=s.kos[full];if type(old)=="table"and old.stamp>=stamp then stamp=old.stamp+1 end
 if not N.Send(active and"KL"or"KX",full,reason,stamp)then return false end
 s.kos[full]={active=active,reason=reason,by=N.Me(),stamp=stamp}
 changed();return true
end
function W.TargetName()return enemyPlayer("target")end

local sightings={}
local function shareSighting(full)
 local st=W.Status(full)
 if st.stars==0 and not st.kos then return end
 if sightings[full]and GetTime()-sightings[full]<SIGHTING_REPEAT then return end
 sightings[full]=GetTime()
 local zone,x,y=position();local stamp=clock()
 local info=noteInfo(full);info.seen,info.zone,info.x,info.y,info.seenBy=stamp,zone,x,y,N.Me()
 N.Send("K4",full,stamp,zone,x,y)
end
local alerted={}
local function alert(full)
 local st=W.Status(full)
 if not(st.kos or st.stars>=ALERT_STARS)then return end
 if alerted[full]and GetTime()-alerted[full]<ALERT_REPEAT then return end
 alerted[full]=GetTime()
 local info=st.info;local who=short(full)..(info.race and" ("..info.race..(info.level and" "..info.level or"")..")"or"")
 N.Notify("|cffff2020WANTED|r "..W.StarText(st.stars,12).." "..who..(st.kos and" |cffff2020KILL ON SIGHT|r"or"").." is near you!")
 if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound,SOUNDKIT.RAID_WARNING)end
end

-- Nameplates: stars and a skull above wanted enemies' names.
local overlays={}
local function overlay(plate)
 local o=overlays[plate]
 if o then return o end
 o=CreateFrame("Frame",nil,plate);o:SetSize(110,16);o:SetPoint("BOTTOM",plate,"TOP",0,2)
 o.stars={}
 for n=1,W.MAX_STARS do local t=o:CreateTexture(nil,"OVERLAY");t:SetTexture(STAR);t:SetSize(13,13);o.stars[n]=t end
 o.skull=o:CreateTexture(nil,"OVERLAY");o.skull:SetTexture(SKULL);o.skull:SetSize(16,16)
 o.text=o:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");o.text:SetPoint("BOTTOM",o,"TOP",0,0)
 if N.SetFont then N.SetFont(o.text,9,"OUTLINE")end
 overlays[plate]=o
 return o
end
local function paint(o,stars,kos)
 local width=(stars>0 and W.MAX_STARS*13 or 0)+(kos and 18 or 0)
 local x=-width/2
 if kos then o.skull:ClearAllPoints();o.skull:SetPoint("LEFT",o,"CENTER",x,0);o.skull:Show();x=x+18 else o.skull:Hide()end
 for n,t in ipairs(o.stars)do
  t:ClearAllPoints();t:SetPoint("LEFT",o,"CENTER",x+(n-1)*13,0)
  t:SetShown(stars>0);t:SetDesaturated(n>stars);t:SetAlpha(n>stars and 0.35 or 1)
 end
 o.text:SetText(kos and"|cffff2020KILL ON SIGHT|r"or"|cffffd100WANTED|r")
 o:Show()
end
local function plateFor(unit)
 return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
end
local function decorate(unit)
 local plate=plateFor(unit);if not plate then return end
 local full=enemyPlayer(unit)
 local st=full and W.Status(full)
 if st and(st.stars>0 or st.kos)then
  paint(overlay(plate),st.stars,st.kos~=nil)
  noteInfo(full,unit);shareSighting(full);alert(full)
 elseif overlays[plate]and not overlays[plate].preview then overlays[plate]:Hide()end
end
W.Decorate=decorate
function W.RefreshPlates()
 if not(C_NamePlate and C_NamePlate.GetNamePlates)then return end
 for _,plate in ipairs(C_NamePlate.GetNamePlates()or{})do
  local unit=plate.namePlateUnitToken or(plate.UnitFrame and plate.UnitFrame.unit)
  if unit then decorate(unit)end
 end
end
function W.Preview()
 local plate=plateFor("target")
 if not plate then N.Notify("Target someone whose nameplate is showing. Press V (enemies) or Shift+V (friends) to turn nameplates on.");return end
 local o=overlay(plate);o.preview=true;paint(o,W.MAX_STARS,true)
 N.Notify("Showing a test wanted marker above your target for 20 seconds.")
 if C_Timer and C_Timer.After then C_Timer.After(20,function()o.preview=nil;o:Hide();W.RefreshPlates()end)end
end
function W.TooltipLine(tooltip,unit)
 local full=unit and enemyPlayer(unit);if not full then return end
 local st=W.Status(full)
 if st.stars==0 and not st.kos then return end
 tooltip:AddLine((st.kos and"|cffff2020KILL ON SIGHT|r  "or"").."|cffffd100WANTED|r "..W.StarText(st.stars,12))
 tooltip:AddLine(st.kills.." guild kills, "..st.victims.." victims",1,0.6,0.6)
 tooltip:Show()
end

local outbox,replyAt,replySince,heardAt,lastReplyTo={},nil,nil,-100,{}
local function batch(op,entries)
 local chunk={}
 for _,entry in ipairs(entries)do
  if #chunk>0 and #N.Pack(op,table.concat(chunk,";")..";"..entry)>240 then outbox[#outbox+1]=N.Pack(op,table.concat(chunk,";"));chunk={}end
  chunk[#chunk+1]=entry
 end
 if #chunk>0 then outbox[#outbox+1]=N.Pack(op,table.concat(chunk,";"))end
end
local function snapshot(since)
 local s=store();if not s then return end
 local events={}
 for _,e in pairs(s.events)do if e.stamp>since then events[#events+1]=e end end
 table.sort(events,function(a,b)return a.stamp>b.stamp end)
 while #events>150 do table.remove(events)end
 local entries={}
 for i,e in ipairs(events)do entries[i]=table.concat({e.kind,e.killer,clean(e.class,20),clean(e.race,20),e.by,e.stamp,clean(e.zone,40),e.x or 0,e.y or 0,e.credit or 1000},",")end
 batch("K2",entries)
 local kos={}
 for name,k in pairs(s.kos)do if type(k)=="table"and k.stamp>since then kos[#kos+1]=table.concat({name,k.active and 1 or 0,k.stamp,k.by,clean(k.reason,80)},",")end end
 batch("K3",kos)
end
function W.Newest()
 local s=store();local newest=0
 for _,e in pairs(s and s.events or{})do newest=math.max(newest,e.stamp)end
 for _,k in pairs(s and s.kos or{})do if type(k)=="table"then newest=math.max(newest,k.stamp or 0)end end
 return newest
end
local function parseEvent(kind,killer,class,race,by,stamp,zone,x,y,credit)
 stamp,x,y,credit=integer(stamp,1,1e11),integer(x,0,1000),integer(y,0,1000),integer(credit,1,1000)
 if(kind~="K"and kind~="R")or not stamp or not x or not y or not credit then return end
 return{kind=kind,killer=N.Full(clean(killer,60)),class=clean(class,20),race=clean(race,20),by=N.Full(by),stamp=stamp,zone=clean(zone,40),x=x,y=y,credit=credit}
end
local function applyKOS(name,active,reason,stamp,by)
 local s=store();name=N.Full(clean(name,60))
 if N.members[name]then return false end
 local old=s.kos[name]
 if type(old)=="table"and old.stamp>=stamp then return false end
 s.kos[name]={active=active,reason=clean(reason,80),by=by,stamp=stamp}
 return true
end
function W.Receive(op,p,sender)
 local s=store();if not s or not N.members[sender]or sender==N.Me()then return end
 if op=="K1"and #p==10 then
  local e=parseEvent(p[2],p[3],p[4],p[5],sender,p[6],p[7],p[8],p[9],p[10])
  if e and addEvent(e)then
   if e.kind=="K"then
    local st=W.Status(e.killer)
    N.Notify(short(sender).." was killed by "..short(e.killer).." "..W.StarText(st.stars,10).." in "..(e.zone~=""and e.zone or"the world")..".")
   end
   changed()
  end
 elseif op=="K2"and #p==2 then
  heardAt=GetTime()
  local dirty=false
  for entry in p[2]:gmatch("[^;]+")do
   local f={};for v in(entry..","):gmatch("(.-),")do f[#f+1]=v end
   if #f==10 then local e=parseEvent(unpack(f));if e and addEvent(e)then dirty=true end end
  end
  if dirty then changed()end
 elseif op=="K3"and #p==2 then
  heardAt=GetTime()
  local dirty=false
  for entry in p[2]:gmatch("[^;]+")do
   local f={};for v in(entry..","):gmatch("(.-),")do f[#f+1]=v end
   local stamp,by=integer(f[3],1,1e11),f[4]and N.Full(f[4])
   if #f==5 and stamp and stamp<=clock()+300 and N.IsOfficer(by)and applyKOS(f[1],f[2]=="1",f[5],stamp,by)then dirty=true end
  end
  if dirty then changed()end
 elseif(op=="KL"or op=="KX")and #p==4 then
  local stamp=integer(p[4],1,1e11)
  if stamp and stamp<=clock()+300 and N.IsOfficer(sender)and applyKOS(p[2],op=="KL",p[3],stamp,sender)then changed()end
 elseif op=="K4"and #p==6 then
  local full=N.Full(clean(p[2],60));local stamp,x,y=integer(p[3],1,1e11),integer(p[5],0,1000),integer(p[6],0,1000)
  if not stamp or not x or not y or stamp>clock()+300 or N.members[full]then return end
  local st=W.Status(full);if st.kills==0 and not st.kos then return end
  local info=s.info[full]or{}
  if(info.seen or 0)<stamp then info.seen,info.zone,info.x,info.y,info.seenBy=stamp,clean(p[4],40),x,y,sender;s.info[full]=info;changed()end
 elseif op=="KQ"and #p==2 then
  local since=integer(p[2],0,1e11);if not since then return end
  if lastReplyTo[sender]and GetTime()-lastReplyTo[sender]<SYNC_THROTTLE then return end
  lastReplyTo[sender]=GetTime()
  replySince=math.min(replySince or since,since)
  -- A random delay lets one member answer while the others hear it and stay quiet.
  replyAt=replyAt or GetTime()+2+math.random(0,4)
 end
end

local queryAt
local driver=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_DEAD","PARTY_KILL","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","UNIT_TARGET"})do pcall(driver.RegisterEvent,driver,event)end
driver:SetScript("OnEvent",function(_,event,a,b)
 if event=="PLAYER_ENTERING_WORLD"then queryAt=queryAt or GetTime()+25
 elseif event=="PLAYER_DEAD"then W.OnDeath()
 elseif event=="PARTY_KILL"then W.OnPartyKill(a,b)
 elseif event=="NAME_PLATE_UNIT_ADDED"then decorate(a)
 elseif event=="NAME_PLATE_UNIT_REMOVED"then
  local plate=plateFor(a);if plate and overlays[plate]then overlays[plate].preview=nil;overlays[plate]:Hide()end
 elseif event=="PLAYER_TARGET_CHANGED"then scanUnit("target");decorate("target")
 elseif event=="UPDATE_MOUSEOVER_UNIT"then scanUnit("mouseover")
 elseif event=="UNIT_TARGET"and type(a)=="string"then scanUnit(a)end
end)
local wait=0
driver:SetScript("OnUpdate",function(_,dt)
 wait=wait+dt;if wait<0.5 then return end;wait=0
 if plain(UnitAffectingCombat("player"))then scanAll()end
 if not N.db then return end
 local now=GetTime()
 if queryAt and now>=queryAt then queryAt=nil;N.Send("KQ",W.Newest())end
 if replyAt and now>=replyAt then
  if now-heardAt>8 then snapshot(replySince or 0)end
  replyAt,replySince=nil,nil
 end
 while #outbox>0 and N.queue and #N.queue<80 do N.queue[#N.queue+1]=table.remove(outbox,1)end
end)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
 TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,function(tooltip)
  if tooltip~=GameTooltip then return end
  local _,unit=tooltip:GetUnit();W.TooltipLine(tooltip,plain(unit))
 end)
elseif GameTooltip and GameTooltip.HookScript then
 GameTooltip:HookScript("OnTooltipSetUnit",function(tooltip)local _,unit=tooltip:GetUnit();W.TooltipLine(tooltip,plain(unit))end)
end
