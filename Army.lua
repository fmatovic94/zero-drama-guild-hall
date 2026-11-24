local _,N=...
-- Guild census plus explicit, persistent help requests. A call shares one static rally point.
N.Army={}; local A=N.Army
local zones, pins = nil, {}
local function clock()return GetServerTime and GetServerTime()or time()end
local function finite(n)return type(n)=="number"and n==n and n~=math.huge and n~=-math.huge end
local function requestID(id)
 if type(id)~="string"or #id>150 then return end
 local caller,created,sequence=id:match("^(.-):(%d+):(%d+)$")
 created,sequence=tonumber(created),tonumber(sequence)
 if not caller or caller==""or not finite(created)or not finite(sequence)or created%1~=0 or created<1 or created>100000000000 or sequence<1 or sequence>1000000000 then return end
 return caller,created,sequence
end
local function newer(a,b)return not b or a.created>b.created or(a.created==b.created and a.sequence>b.sequence)end
A.FOLLOW_SECONDS=1800
-- Answers are this character's own choice and are never broadcast as addon data.
local function responses()
 if not N.db then return end
 N.db.armyResponses=type(N.db.armyResponses)=="table"and N.db.armyResponses or{}
 return N.db.armyResponses
end
local function changed()
 A.requestDrawKey=nil
 if type(A.OnRequestsChanged)=="function"then A.OnRequestsChanged()
 elseif N.Render then N.Render()end
 if A.DrawRequestPins then A.DrawRequestPins()end
end
function A.EnsureState()
 if A.scope==N.db then return N.db end
 A.scope=N.db;A.cancelByCaller={};A.receivedAt={};A.syncPeers={};A.syncCursor=1;A.requestDrawKey=nil;A.lastSync=nil;A.lastResponse=nil;A.replyAt=nil;A.lastHeardSync=nil
 if not N.db then A.scopeChanged=true;return end
 -- Zone totals are an optional local overlay, including for pre-0.13 saves.
 -- Do not inherit the old shared map-pin preference: live positions keep it.
 N.db.showGuildCensus=N.db.showGuildCensus==true
 N.db.armyRequests=type(N.db.armyRequests)=="table"and N.db.armyRequests or{}
 N.db.armyCancelled=type(N.db.armyCancelled)=="table"and N.db.armyCancelled or{}
 local sequence=tonumber(N.db.armySequence);N.db.armySequence=finite(sequence)and sequence>=0 and sequence<1000000000 and math.floor(sequence)or 0
 for id,value in pairs(N.db.armyCancelled)do
  local caller,created,sequence=requestID(id)
  if not caller then N.db.armyCancelled[id]=nil
  else
   local record={id=id,caller=caller,created=created,sequence=sequence,by=type(value)=="table"and value.by or caller,stamp=type(value)=="table"and value.stamp or nil}
   if newer(record,A.cancelByCaller[caller])then A.cancelByCaller[caller]=record end
  end
 end
 -- One persistent cancellation watermark per caller rejects every older replay.
 N.db.armyCancelled={};for _,record in pairs(A.cancelByCaller)do N.db.armyCancelled[record.id]=record end
 local callers={}
 for id,r in pairs(N.db.armyRequests)do
  local caller,created,sequence=requestID(id)
  local cancelled=caller and A.cancelByCaller[caller]
  if type(r)~="table"or not caller or r.caller~=caller or not finite(r.mapID)or r.mapID%1~=0 or r.mapID<1 or r.mapID>10000000 or not finite(r.x)or not finite(r.y)or r.x<0 or r.x>1 or r.y<0 or r.y>1 or(cancelled and not newer({created=created,sequence=sequence},cancelled))then
   N.db.armyRequests[id]=nil
  else
   r.id=id;r.created=created;r.sequence=sequence;r.zone=N.Safe(r.zone)
   local other=callers[caller]
   if other then
    if newer(r,other)then N.db.armyRequests[other.id]=nil;callers[caller]=r else N.db.armyRequests[id]=nil end
   else callers[caller]=r end
  end
 end
 local answered=responses();for id in pairs(answered)do if not N.db.armyRequests[id]then answered[id]=nil end end
 A.syncAt=clock()+3;A.publishAt=clock()+60+(#N.Me()%15);A.scopeChanged=true
 return N.db
end
function A.ActiveRequests()
 local db=A.EnsureState();local list={}
 if db then for _,r in pairs(db.armyRequests)do list[#list+1]=r end end
 table.sort(list,function(a,b)if a.created==b.created then return a.id<b.id end;return a.created<b.created end)
 return list
end
function A.CanCancel(r)
 return r and N.db and N.members[N.Me()]and(r.caller==N.Me()or N.IsOfficer(N.Me()))or false
end
local function maySend(quiet)
 if not N.db or not IsInGuild or not IsInGuild()or not N.members[N.Me()]then return false end
 if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage)~="function"then
  if not quiet then N.Notify("Guild addon messages are unavailable here.")end;return false
 end
 -- AreOutgoingAddonChatMessagesRestricted is not checked: Forever reports true while guild sends still succeed.
 for _,name in ipairs({"InChatMessagingLockdown"})do
  if type(C_ChatInfo[name])=="function"then
   local ok,restricted=pcall(C_ChatInfo[name])
   if ok and restricted==true then if not quiet then N.Notify("Guild addon messages are restricted right now ("..name.."). Try again when the restriction ends.")end;return false end
  end
 end
 return true
end
local function enqueue(messages)
 if not N.queue or #N.queue+#messages>100 then return false end
 for _,msg in ipairs(messages)do if #msg>240 then return false end end
 for _,msg in ipairs(messages)do N.queue[#N.queue+1]=msg end
 return true
end
local function requestPacket(r)return N.Pack("H1",r.id,r.mapID,math.floor(r.x*10000+0.5),math.floor(r.y*10000+0.5),r.zone)end
local function recordCancel(id,by)
 local caller,created,sequence=requestID(id);if not caller then return false end
 local record={id=id,caller=caller,created=created,sequence=sequence,by=by,stamp=clock()}
 local old=A.cancelByCaller[caller]
 if newer(record,old)then
  if old then N.db.armyCancelled[old.id]=nil end
  A.cancelByCaller[caller]=record;N.db.armyCancelled[id]=record
 end
 local dirty=false
 for key,r in pairs(N.db.armyRequests)do
  if r.caller==caller and not newer(r,record)then N.db.armyRequests[key]=nil;dirty=true end
 end
 return dirty
end
function A.RequestHelp()
 if not A.EnsureState()or not maySend(false)then return false end
 local caller=N.Me();local now=clock()
 for _,r in pairs(N.db.armyRequests)do if r.caller==caller then N.Notify("Your army request is already active. Cancel it before calling again.");return false end end
 local last=tonumber(N.db.armyLastRequestAt)
 if last and now-last<60 then N.Notify("Request Army is on cooldown for "..math.max(1,60-(now-last)).." seconds.");return false end
 if type(IsInInstance)~="function"then N.Notify("Your outdoor location cannot be verified.");return false end
 local ok,inside=pcall(IsInInstance)
 if not ok or inside~=false then N.Notify("Request Army is available in the outdoor world, not instances.");return false end
 if not C_Map or type(C_Map.GetBestMapForUnit)~="function"or type(C_Map.GetPlayerMapPosition)~="function"or type(C_Map.GetMapInfo)~="function"then N.Notify("Your location is unavailable in this client.");return false end
 local worked,mapID,info,x,y=pcall(function()
  local id=C_Map.GetBestMapForUnit("player");if not id then return end
  local details=C_Map.GetMapInfo(id);local pos=C_Map.GetPlayerMapPosition(id,"player");if not details or not pos then return end
  local px,py;if pos.GetXY then px,py=pos:GetXY()else px,py=pos.x,pos.y end
  if not finite(id)or id%1~=0 or id<1 or not finite(px)or not finite(py)or px<0 or px>1 or py<0 or py>1 or(px==0 and py==0)then return end
  return id,details,px,py
 end)
 if not worked or not mapID then N.Notify("Your exact map position is unavailable. No request was sent.");return false end
 N.db.armySequence=N.db.armySequence+1
 local id=caller..":"..now..":"..N.db.armySequence
 local r={id=id,caller=caller,mapID=mapID,x=x,y=y,zone=N.Clip(N.Safe(info.name),60),created=now,sequence=N.db.armySequence}
 local cancelled=A.cancelByCaller[caller]
 if cancelled and not newer(r,cancelled)then N.Notify("Your request clock is behind the last cancellation. Try again after the clock updates.");return false end
 local messages={}
 if cancelled then messages[#messages+1]=N.Pack("HC",cancelled.id)end
 messages[#messages+1]=requestPacket(r)
 if not enqueue(messages)then N.Notify("The addon message queue is full. Try Request Army again shortly.");return false end
 N.db.armyRequests[id]=r;N.db.armyLastRequestAt=now;A.receivedAt[caller]=now;changed()
 return id
end
function A.CancelHelp(id)
 if not A.EnsureState()then return false end
 local r=N.db.armyRequests[id]
 if not r or not A.CanCancel(r)or not maySend(false)then return false end
 if not N.Send("HC",id)then N.Notify("The addon message queue is full. The request is still active.");return false end
 recordCancel(id,N.Me());changed();return true
end
function A.Response(r)
 local list=r and responses();local entry=list and list[r.id]
 if type(entry)~="table"or(entry.choice~="coming"and entry.choice~="busy")or not finite(entry.at)then return end
 return entry.choice,entry.at
end
function A.IsFollowing(r)
 local choice,at=A.Response(r)
 return choice=="coming"and clock()-at<A.FOLLOW_SECONDS
end
function A.IsMuted(r)return(A.Response(r))=="busy"end
function A.NeedsAnswer(r)return r~=nil and r.caller~=N.Me()and A.Response(r)==nil end
local function short(name)local safe=N.Safe(name);return safe:match("^[^-]+")or safe end
function A.ComingMessage(r)
 return N.Clip(string.format("[ZERO DRAMA auto-message] On my way to help %s in %s (%.1f, %.1f)! For the Horde!",short(r.caller),N.Safe(r.zone),(r.x or 0)*100,(r.y or 0)*100),255)
end
function A.LivePosition(r)
 if not A.IsFollowing(r)or not N.Tracking or type(N.Tracking.GetPositions)~="function"then return end
 for _,p in ipairs(N.Tracking.GetPositions())do if p.name==r.caller then return p end end
end
function A.Respond(id,choice)
 if not A.EnsureState()or(choice~="coming"and choice~="busy")then return false end
 local r=N.db.armyRequests[id];if not r or r.caller==N.Me()then return false end
 local announce=choice=="coming"and not A.IsFollowing(r)
 responses()[id]={choice=choice,at=clock()}
 if announce and type(SendChatMessage)=="function"and IsInGuild and IsInGuild()then pcall(SendChatMessage,A.ComingMessage(r),"GUILD")end
 if choice=="coming"then N.Notify("On your way to "..short(r.caller)..". Their live position is marked on your map for 30 minutes.")
 else N.Notify("You won't get alerts for "..short(r.caller).."'s call. You can still answer it on the Army page.")end
 changed();return true
end
function A.Sync()
 if not A.EnsureState()or not maySend(true)then return false end
 local now=clock();if A.lastSync and now-A.lastSync<30 then return false end
 if not N.Send("HS")then return false end
 A.lastSync=now;return true
end
function A.ReceiveRequest(op,p,sender)
 if not A.EnsureState()or not N.members[sender]then return end
 if op=="H1"and #p==6 then
  local caller,created,sequence=requestID(p[2]);local mapID,x,y=tonumber(p[3]),tonumber(p[4]),tonumber(p[5])
  if not caller or not N.members[caller]or(sender~=caller and not N.IsOfficer(sender))or created>clock()+120 then return end
  if not finite(mapID)or mapID%1~=0 or mapID<1 or mapID>10000000 or not finite(x)or not finite(y)or x%1~=0 or y%1~=0 or x<0 or x>10000 or y<0 or y>10000 or(x==0 and y==0)or #p[6]>60 then return end
  if not C_Map or type(C_Map.GetMapInfo)~="function"then return end
  local mapped,info=pcall(C_Map.GetMapInfo,mapID);if not mapped or type(info)~="table"or not info.name then return end
  local cancelled=A.cancelByCaller[caller]
  local r={id=p[2],caller=caller,mapID=mapID,x=x/10000,y=y/10000,zone=N.Safe(p[6]),created=created,sequence=sequence}
  if cancelled and not newer(r,cancelled)then return end
  if N.db.armyRequests[r.id]then return end -- Replay cannot relocate an existing request.
  for _,active in pairs(N.db.armyRequests)do if active.caller==caller then return end end
  local last=A.receivedAt[caller];if last and clock()-last<60 then return end
  N.db.armyRequests[r.id]=r;A.receivedAt[caller]=clock();changed()
 elseif op=="HC"and #p==2 then
  local caller,created=requestID(p[2])
  if not caller or created>clock()+120 or(sender~=caller and not N.IsOfficer(sender))then return end
  local dirty=recordCancel(p[2],sender);if dirty then changed()end
 elseif op=="HS"and #p==1 and sender~=N.Me()then
  local now=clock();A.lastHeardSync=now;if A.lastResponse and now-A.lastResponse<30 then return end
  if A.syncPeers[sender]and now-A.syncPeers[sender]<60 then return end
  A.syncPeers[sender]=now;A.lastResponse=now;A.replyAt=now+1+(#N.Me()%3)
 end
end
function A.ReplySync(ownOnly)
 if not A.EnsureState()or not maySend(true)then return false end
 local messages={};local officer=not ownOnly and N.IsOfficer(N.Me())
 local cancelled={};for id,r in pairs(N.db.armyCancelled)do if officer or r.caller==N.Me()then cancelled[#cancelled+1]=id end end;table.sort(cancelled)
 for _,id in ipairs(cancelled)do messages[#messages+1]=N.Pack("HC",id)end
 for _,r in ipairs(A.ActiveRequests())do if officer or r.caller==N.Me()then messages[#messages+1]=requestPacket(r)end end
 if #messages==0 then return true end
 local start=A.syncCursor or 1;local sent=0
 for offset=0,#messages-1 do
  local i=((start+offset-1)%#messages)+1
  if not enqueue({messages[i]})then A.syncCursor=i;return sent>0 end
  sent=sent+1
 end
 A.syncCursor=1;return true
end
function A.RequestPosition(r,shownID)
 if not r or not finite(r.x)or not finite(r.y)or r.x<0 or r.x>1 or r.y<0 or r.y>1 then return end
 if r.mapID==shownID then return r.x,r.y end
 if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapRectOnMap then return end
 local id=r.mapID;local visited={};local ancestor=false
 for _=1,12 do
  if not id or visited[id]then break end;visited[id]=true
  local info=C_Map.GetMapInfo(id);if not info then break end
  id=info.parentMapID;if id==shownID then ancestor=true;break end
 end
 if not ancestor then return end
 local ok,minX,maxX,minY,maxY=pcall(C_Map.GetMapRectOnMap,r.mapID,shownID)
 if not ok or not finite(minX)or not finite(maxX)or not finite(minY)or not finite(maxY)then return end
 local x,y=minX+r.x*(maxX-minX),minY+r.y*(maxY-minY)
 if not finite(x)or not finite(y)or x<0 or x>1 or y<0 or y>1 then return end
 return x,y
end
function A.IndexZones()
 if zones then return zones end
 zones={}
 if not C_Map or not C_Map.GetMapInfo then return zones end
 local visited={}
 local function walk(id,depth)
  if visited[id] or depth>8 then return end
  visited[id]=true
  local info=C_Map.GetMapInfo(id)
  if info and info.name and info.mapType and info.mapType>=3 then
   -- An ambiguous localized name must never place members on an arbitrary map.
   if zones[info.name] and zones[info.name]~=id then zones[info.name]=false
   elseif zones[info.name]==nil then zones[info.name]=id end
  end
  if C_Map.GetMapChildrenInfo then
   local ok,children=pcall(C_Map.GetMapChildrenInfo,id)
   if ok and children then for _,child in ipairs(children) do walk(child.mapID,depth+1) end end
  end
 end
 walk(947,0) -- Azeroth. Client supplies localized zone names and map hierarchy.
 return zones
end
function A.Summary()
 local result={zones={},online=0,unknown=0,offline=0,mapped=0}; local byZone={}
 local index=A.IndexZones()
 for _,m in pairs(N.members) do
  if m.online then
   result.online=result.online+1
   if not m.zone or m.zone=="" then result.unknown=result.unknown+1
   else
    local z=byZone[m.zone]
    if not z then z={name=m.zone,mapID=index[m.zone] or nil,members={}}; byZone[m.zone]=z; result.zones[#result.zones+1]=z end
    z.members[#z.members+1]=m.name
    if z.mapID then result.mapped=result.mapped+1 end
   end
  else result.offline=result.offline+1 end
 end
 for _,z in ipairs(result.zones) do table.sort(z.members); z.count=#z.members end
 table.sort(result.zones,function(a,b) if a.count==b.count then return a.name<b.name end return a.count>b.count end)
 return result
end
function A.Project(zoneID,shownID)
 if zoneID==shownID then return 0.5,0.5 end
 if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapRectOnMap then return end
 -- Only project descendants; a nearby zone or another layer is not the same place.
 local ancestor=zoneID; local seen={}; local found=false
 for _=1,12 do
  if seen[ancestor] then break end; seen[ancestor]=true
  local info=C_Map.GetMapInfo(ancestor)
  if not info or not info.parentMapID or info.parentMapID==0 then break end
  ancestor=info.parentMapID
  if ancestor==shownID then found=true; break end
 end
 if not found then return end
 local ok,minX,maxX,minY,maxY=pcall(C_Map.GetMapRectOnMap,zoneID,shownID)
 if not ok or type(minX)~="number" or type(maxX)~="number" or type(minY)~="number" or type(maxY)~="number" then return end
 local x,y=(minX+maxX)/2,(minY+maxY)/2
 if x~=x or y~=y or x<0 or x>1 or y<0 or y>1 then return end
 return x,y
end
function A.Tooltip(owner,z)
 GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
 GameTooltip:SetText(N.Safe(z.name),1,0.82,0)
 GameTooltip:AddLine(z.count.." ZERO DRAMA members in this zone",1,1,1)
 for i=1,math.min(16,#z.members) do GameTooltip:AddLine(N.Safe(z.members[i]),0.8,0.8,0.8) end
 if #z.members>16 then GameTooltip:AddLine("+ "..(#z.members-16).." more",0.8,0.8,0.8) end
 GameTooltip:AddLine("Zone count from the guild roster, not exact player positions.",0.8,0.65,0.4,true)
 GameTooltip:AddLine("Members may be on different layers. Roster data can be delayed.",0.65,0.65,0.65,true)
 GameTooltip:Show()
end
function A.Open(mapID,x,y)
 if mapID and C_Map and C_Map.GetMapInfo then
  local ok,info=pcall(C_Map.GetMapInfo,mapID)
  if not ok or not info then N.Notify("This map is not available in the current client.");return end
 end
 if not WorldMapFrame then
  local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
  if loader then pcall(loader,"Blizzard_WorldMap") end
 end
 if not WorldMapFrame or not WorldMapFrame.SetMapID then N.Notify("World map is unavailable in this client."); return end
 local ok=pcall(function()
  if not WorldMapFrame:IsShown()then
   if ShowUIPanel and not(InCombatLockdown and InCombatLockdown())then ShowUIPanel(WorldMapFrame)else WorldMapFrame:Show()end
  end
  WorldMapFrame:SetMapID(mapID or 947)
 end)
 if not ok or not WorldMapFrame:IsShown()then N.Notify("The map cannot open right now. The rally coordinates remain in the help alert.");return false end
 if N.window then N.window:Hide() end
 if mapID and finite(x)and finite(y)and type(OpenMapAPI)=="table"then
  pcall(function()
   if OpenMapAPI.IsStitched()then
    local u,v=OpenMapAPI.WorldFromMap(mapID,x,y)
    if finite(u)and finite(v)then OpenMapAPI.ShowWorld(u,v)end
   end
  end)
 end
 A.Draw()
 return true
end
function A.IsCensusEnabled()
 return N.db~=nil and N.db.showGuildCensus==true
end
function A.SetCensusEnabled(enabled)
 if not N.db then return false end
 N.db.showGuildCensus=enabled==true
 A.drawKey=nil;A.DrawCensus()
 return true
end
function A.DrawCensus()
 if not A.IsCensusEnabled() or N.db.showGuildMap==false or not WorldMapFrame or not WorldMapFrame:IsShown() or not WorldMapFrame.GetCanvas then
  for _,p in ipairs(pins) do p:Hide() end
  A.drawKey=nil; return
 end
 local canvas=WorldMapFrame:GetCanvas(); local shown=WorldMapFrame:GetMapID()
 if not canvas or not shown then return end
 local width,height=canvas:GetWidth(),canvas:GetHeight()
 if width<=0 or height<=0 then return end
 local sc=WorldMapFrame.ScrollContainer
 local scale=sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
 if type(scale)~="number" or scale<=0 then scale=1 end
 local summary=A.Summary()
 local parts={tostring(N.db),shown,width,height,scale}
 for _,z in ipairs(summary.zones) do parts[#parts+1]=z.name..":"..table.concat(z.members,",") end
 local key=table.concat(parts,"|")
 if A.drawKey==key and A.canvas==canvas then return end
 A.drawKey=key; A.canvas=canvas
 for _,p in ipairs(pins) do p:Hide() end
 local used=0
 for _,z in ipairs(summary.zones) do
  local x,y
  if z.mapID then x,y=A.Project(z.mapID,shown) end
  if x then
   used=used+1; local p=pins[used]
   if not p then
    p=CreateFrame("Button",nil,canvas,"BackdropTemplate"); pins[used]=p
    p:SetSize(32,32)
    p:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    p:SetBackdropColor(0.28,0.025,0.02,0.97); p:SetBackdropBorderColor(0.95,0.74,0.32,1)
    p.label=p:CreateFontString(nil,"OVERLAY","GameFontNormal"); p.label:SetPoint("CENTER")
    p:SetScript("OnEnter",function(self) A.Tooltip(self,self.zone) end)
    p:SetScript("OnLeave",function() GameTooltip:Hide() end)
    p:SetScript("OnClick",function(self) if WorldMapFrame:GetMapID()~=self.zone.mapID then WorldMapFrame:SetMapID(self.zone.mapID); A.Draw() end end)
   end
   p.zone=z; p:SetParent(canvas); p:SetFrameLevel(canvas:GetFrameLevel()+50)
   p:SetScale(1/scale); p:ClearAllPoints(); p:SetPoint("CENTER",canvas,"TOPLEFT",x*width*scale,-y*height*scale)
   p.label:SetText(tostring(z.count)); p:Show()
  end
 end
end
function A.DrawRequestPins()
 if N.LiveMap and N.LiveMap.Refresh then N.LiveMap.Refresh()end
end
function A.Draw()A.DrawCensus();A.DrawRequestPins()end
local driver=CreateFrame("Frame"); local elapsed,request=0,0
driver:SetScript("OnUpdate",function(_,dt)
 elapsed=elapsed+dt; request=request+dt
 if elapsed>=1 then
  elapsed=0;A.EnsureState()
  if A.scopeChanged then A.scopeChanged=nil;changed()end
  local now=clock()
  if A.replyAt and now>=A.replyAt then A.replyAt=nil;A.ReplySync()end
  if N.db and A.syncAt and now>=A.syncAt then
   local sent=true;if not A.lastHeardSync or now-A.lastHeardSync>20 then sent=A.Sync()end
   A.syncAt=not sent and now+10 or(#A.ActiveRequests()>0 and now+90+(#N.Me()%20)or nil)
  end
  if N.db and A.publishAt and now>=A.publishAt then
   local ownActive=false;for _,r in ipairs(A.ActiveRequests())do if r.caller==N.Me()then ownActive=true;break end end
   local cancelled=A.cancelByCaller[N.Me()]
   if ownActive or(cancelled and finite(cancelled.stamp)and now-cancelled.stamp<300)then A.ReplySync(true)end
   A.publishAt=now+60+(#N.Me()%15)
  end
  A.Draw()
 end
 if request>=30 then
  request=0
  if N.db and ((N.window and N.window:IsShown()) or (WorldMapFrame and WorldMapFrame:IsShown())) then N.Call("GuildRoster","GuildRoster") end
 end
end)
