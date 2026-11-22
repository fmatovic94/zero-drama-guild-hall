local _,N=...
-- Live positions are the coordinates shared by each member's own addon. OpenMap
-- v0.7.5-beta uses WorldMapFrame too; only its documented coordinate API is used.
local M={pins={}};N.LiveMap=M
local elapsed,positionWait,lastGeometry=0,0,nil
local registeredAPI
local function finite(v)
 if type(v)~="number"then return false end
 if type(issecretvalue)=="function"and issecretvalue(v)then return false end
 return v==v and v~=math.huge and v~=-math.huge
end
local function invoke(fn,...)
 if type(fn)~="function"then return end
 local ok,a,b,c,d=pcall(fn,...);if ok then return a,b,c,d end
end
local function method(object,key,...)
 if not object then return end
 return invoke(object[key],object,...)
end
local function xy(vector)
 if type(vector)~="table"and type(vector)~="userdata"then return end
 local ok,x,y=pcall(function()
  if type(vector.GetXY)=="function"then return vector:GetXY()end
  return vector.x,vector.y
 end)
 if not ok then return end
 if finite(x)and finite(y)then return x,y end
end
local function valid(record)
 if type(record)~="table"or type(record.name)~="string"then return false end
 local member=N.members and N.members[record.name]
 if not member or member.online~=true then return false end
 if not finite(record.mapID)or record.mapID%1~=0 or record.mapID<=0 then return false end
 if not finite(record.x)or not finite(record.y)or record.x<0 or record.x>1 or record.y<0 or record.y>1 or(record.x==0 and record.y==0)then return false end
 local age=record.age
 if not finite(age)and finite(record.receivedAt)then
  local now=invoke(GetTime);if finite(now)then age=now-record.receivedAt end
 end
 return finite(age)and age>=0 and age<(N.Tracking and N.Tracking.TTL or 30),age
end
function M.IsEnabled()return not N.db or N.db.showGuildMap~=false end
function M.SetEnabled(enabled)
 if not N.db then return false end
 N.db.showGuildMap=enabled==true
 M.Refresh()
 if N.Army and N.Army.Draw then N.Army.Draw()end
 return true
end
local function stitched()
 local api=OpenMapAPI
 if type(api)~="table"then return false end
 -- An installed API that cannot report its mode is not evidence that the
 -- underlying artwork uses Blizzard coordinates. Hide until it can answer.
 local mode=invoke(api.IsStitched)
 if type(mode)=="boolean"then return mode end
end
-- Coordinates returned here are normalized on the *host canvas*. On OpenMap
-- they may legitimately lie beyond 0..1: neighbouring zones are stitched there.
function M.Project(record,shownID,isStitched)
 if type(record)~="table"or not finite(record.mapID)or not finite(shownID)or not finite(record.x)or not finite(record.y)then return end
 if record.x<0 or record.x>1 or record.y<0 or record.y>1 or(record.x==0 and record.y==0)then return end
 if isStitched then
  local api=OpenMapAPI
  if type(api)~="table"then return end
  local u,v=invoke(api.WorldFromMap,record.mapID,record.x,record.y)
  if not finite(u)or not finite(v)then return end
  local x,y=invoke(api.MapFromWorld,shownID,u,v)
  if finite(x)and finite(y)and math.abs(x)<1000000 and math.abs(y)<1000000 then return x,y end
  return -- Never substitute Blizzard coordinates over stitched artwork.
 end
 if record.mapID==shownID then return record.x,record.y end
 if not C_Map then return end
 -- The documented API returns a uiMapID followed by a Vector2, not two numbers.
 if type(CreateVector2D)=="function"then
  local vector=invoke(CreateVector2D,record.x,record.y)
  if vector then
   local continent,world=invoke(C_Map.GetWorldPosFromMapPos,record.mapID,vector)
   local wx,wy=xy(world)
   if finite(continent)and wx then
    local worldVector=invoke(CreateVector2D,wx,wy)
    local target,pos=invoke(C_Map.GetMapPosFromWorldPos,continent,worldVector,shownID)
    local x,y=xy(pos)
    if target==shownID and x and x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
   end
  end
 end
 -- Older clients can project a descendant rectangle onto a parent map.
 local id,visited=record.mapID,{}
 for _=1,12 do
  if not id or visited[id]then return end;visited[id]=true
  local info=invoke(C_Map.GetMapInfo,id)
  if type(info)~="table"then return end
  id=info.parentMapID
  if id==shownID then
   local l,r,t,b=invoke(C_Map.GetMapRectOnMap,record.mapID,shownID)
   if not finite(l)or not finite(r)or not finite(t)or not finite(b)or r<=l or b<=t then return end
   local x,y=l+record.x*(r-l),t+record.y*(b-t)
   if finite(x)and finite(y)and x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
   return
  end
  if not finite(id)or id<=0 then return end
 end
end
local function hide()
 for _,pin in ipairs(M.pins)do pin:Hide();pin.record=nil end
 for _,pin in ipairs(M.callPins or{})do pin:Hide();pin.request=nil end
 M.visibleCalls=0
 if M.overlay then M.overlay:Hide()end
 lastGeometry=nil;M.visibleCount=0
end
local function geometry()
 local map=WorldMapFrame
 if not N.db or not map or method(map,"IsShown")~=true then return end
 local canvas=method(map,"GetCanvas");local viewport=map.ScrollContainer
 if not canvas or not viewport then return end
 local shownID=method(map,"GetMapID")
 local cw,ch=method(canvas,"GetWidth"),method(canvas,"GetHeight")
 local cs=method(canvas,"GetEffectiveScale")
 local cl,ct=method(canvas,"GetLeft"),method(canvas,"GetTop")
 local vw,vh=method(viewport,"GetWidth"),method(viewport,"GetHeight")
 local vs=method(viewport,"GetEffectiveScale")
 local vl,vt=method(viewport,"GetLeft"),method(viewport,"GetTop")
 if not finite(shownID)or not finite(cw)or not finite(ch)or cw<=0 or ch<=0 or not finite(cs)or cs<=0 or not finite(cl)or not finite(ct)
  or not finite(vw)or not finite(vh)or vw<=0 or vh<=0 or not finite(vs)or vs<=0 or not finite(vl)or not finite(vt)then return end
 local mode=stitched();if mode==nil then return end
 return {map=map,canvas=canvas,viewport=viewport,mapID=shownID,cw=cw,ch=ch,cs=cs,cl=cl,ct=ct,vw=vw,vh=vh,vs=vs,vl=vl,vt=vt,stitched=mode}
end
local function color(member)
 local hex=N.ClassColor and N.ClassColor(member)or"CCCCCC"
 if type(hex)~="string"or not hex:match("^%x%x%x%x%x%x$")then hex="CCCCCC"end
 return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end
local function tooltip(self)
 local record=self.record;local ok,age=valid(record)
 if not ok or not GameTooltip then return end
 local member=N.members[record.name];local r,g,b=color(member)
 GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(N.Safe(record.name),r,g,b)
 GameTooltip:AddLine("Level "..tostring(member.level or"?").." "..N.Safe(member.class),1,1,1)
 GameTooltip:AddLine(N.Safe(N.DisplayRank and N.DisplayRank(member)or member.rank),1,0.82,0)
 local info=C_Map and invoke(C_Map.GetMapInfo,record.mapID)
 GameTooltip:AddLine(N.Safe(info and info.name or member.zone or"Unknown area")..string.format("  %.1f, %.1f",record.x*100,record.y*100),1,1,1)
 GameTooltip:AddLine("Position received "..math.floor(age).."s ago",0.6,0.9,0.6)
 GameTooltip:AddLine("Shared by this member's ZERO DRAMA addon.",0.7,0.7,0.7,true)
 GameTooltip:AddLine("Layer and phase are not verified.",0.7,0.7,0.7,true)
 GameTooltip:Show()
end
local function overlay(g)
 if not M.overlay then
  M.overlay=CreateFrame("Frame","NoDramaLiveMapOverlay",g.viewport)
  M.overlay:EnableMouse(false)
  if M.overlay.SetClipsChildren then M.overlay:SetClipsChildren(true)end
 end
 if M.viewport~=g.viewport then M.overlay:SetParent(g.viewport);M.viewport=g.viewport end
 M.overlay:ClearAllPoints();M.overlay:SetAllPoints(g.viewport)
 local level=(method(g.viewport,"GetFrameLevel")or 0)+50
 if g.stitched and type(OpenMapAPI)=="table"then
  local art=invoke(OpenMapAPI.ArtTopLevel);if finite(art)then level=math.max(level,art+15)end
 end
 if not(InCombatLockdown and InCombatLockdown())then M.overlay:SetFrameLevel(level)end
 M.overlay:Show()
 return M.overlay
end
local function pinAt(index,parent)
 local pin=M.pins[index]
 if pin then return pin end
 pin=CreateFrame("Button",nil,parent);M.pins[index]=pin
 pin:SetSize(18,18);pin:EnableMouse(true)
 pin.dot=pin:CreateTexture(nil,"ARTWORK");pin.dot:SetSize(12,12);pin.dot:SetPoint("CENTER")
 pin.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
 if pin.CreateMaskTexture and pin.dot.AddMaskTexture then
  local mask=pin:CreateMaskTexture(nil,"ARTWORK")
  if mask then
   mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");mask:SetAllPoints(pin.dot)
   pin.dot:AddMaskTexture(mask);pin.dotMask=mask
  end
 else pin.dot:SetTexture("Interface\\COMMON\\Indicator-Gray")end
 pin.halo=pin:CreateTexture(nil,"BACKGROUND");pin.halo:SetSize(18,18);pin.halo:SetPoint("CENTER")
 pin.halo:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center");pin.halo:SetVertexColor(0.9,0.72,0.25,0.8)
 pin:SetScript("OnEnter",tooltip)
 pin:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
 return pin
end
local function registerMenu()
 local api=OpenMapAPI
 if type(api)~="table"or registeredAPI==api or type(api.RegisterMenuToggle)~="function"then return end
 local ok=pcall(api.RegisterMenuToggle,"ZERO DRAMA",{id="guildMembers",label="ZERO DRAMA guild members",icon="Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga",get=M.IsEnabled,set=M.SetEnabled,section="Guild"})
 if ok then registeredAPI=api end
end
M.callPins={}
local function callTooltip(self)
 local r=self.request;if not r or not GameTooltip then return end
 local caller=N.members and N.members[r.caller]
 GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("Request Army!",1,0.35,0.1)
 GameTooltip:AddLine(N.Safe(r.caller:match("^[^-]+")or r.caller)..(caller and"  (level "..tostring(caller.level or"?").." "..N.Safe(caller.class)..")"or""),1,0.82,0)
 GameTooltip:AddLine(N.Safe(r.zone)..string.format("  %.1f, %.1f",r.x*100,r.y*100),1,1,1)
 local now=GetServerTime and GetServerTime()or time()
 local minutes=finite(r.created)and math.floor((now-r.created)/60)or nil
 if minutes then GameTooltip:AddLine(minutes<1 and"Called just now"or"Called "..minutes.." min ago",0.6,0.9,0.6)end
 GameTooltip:AddLine("Static rally point at the time of the call.",0.8,0.8,0.8,true)
 GameTooltip:AddLine("Active until the requester, an officer or GM cancels.",1,0.7,0.35,true)
 GameTooltip:AddLine("Layer and phase are not verified.",0.65,0.65,0.65,true)
 GameTooltip:Show()
end
local function callPinAt(index,parent)
 local pin=M.callPins[index]
 if pin then return pin end
 pin=CreateFrame("Button",nil,parent);M.callPins[index]=pin
 pin:SetSize(34,34);pin:EnableMouse(true)
 pin.glow=pin:CreateTexture(nil,"BACKGROUND");pin.glow:SetSize(54,54);pin.glow:SetPoint("CENTER")
 pin.glow:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center");pin.glow:SetVertexColor(1,0.25,0.1,0.9)
 pin.icon=pin:CreateTexture(nil,"ARTWORK");pin.icon:SetSize(30,30);pin.icon:SetPoint("CENTER")
 pin.icon:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\ArmyWarning.tga")
 pin.pulse=0
 pin:SetScript("OnUpdate",function(self,dt)
  self.pulse=self.pulse+(finite(dt)and dt or 0)
  local wave=0.5+0.5*math.sin(self.pulse*math.pi*1.5)
  self.glow:SetAlpha(0.35+0.65*wave);self.glow:SetSize(44+16*wave,44+16*wave)
 end)
 pin:SetScript("OnEnter",callTooltip)
 pin:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
 pin:SetScript("OnClick",function(self)local r=self.request;if r and N.Army and N.Army.Open then N.Army.Open(r.mapID,r.x,r.y)end end)
 return pin
end
local function place(g,x,y)
 local px=(g.cl*g.cs+x*g.cw*g.cs-g.vl*g.vs)/g.vs
 local py=(g.vt*g.vs-g.ct*g.cs+y*g.ch*g.cs)/g.vs
 if finite(px)and finite(py)and px>=0 and py>=0 and px<=g.vw and py<=g.vh then return px,py end
end
function M.Refresh(g)
 registerMenu()
 g=g or geometry()
 if not g then hide();return end
 local requests=N.Army and type(N.Army.ActiveRequests)=="function"and invoke(N.Army.ActiveRequests)or{}
 local records=M.IsEnabled()and N.Tracking and invoke(N.Tracking.GetPositions)or{}
 if type(records)~="table"then records={}end
 if #records==0 and #requests==0 then hide();return end
 local parent=overlay(g);local used=0
 local calls=0
 for _,r in ipairs(requests)do
  local x,y=M.Project(r,g.mapID,g.stitched)
  local px,py;if x then px,py=place(g,x,y)end
  if px then
   calls=calls+1;local pin=callPinAt(calls,parent);pin.request=r
   pin:SetFrameLevel(parent:GetFrameLevel()+10)
   pin:ClearAllPoints();pin:SetPoint("CENTER",parent,"TOPLEFT",px,-py);pin:Show()
  end
 end
 for index=calls+1,#M.callPins do M.callPins[index]:Hide();M.callPins[index].request=nil end
 M.visibleCalls=calls
 for _,record in ipairs(records)do
  if valid(record)then
   local x,y=M.Project(record,g.mapID,g.stitched)
   if x then
    -- GetLeft/GetTop are in each frame's own effective-scale units. Convert
    -- through screen coordinates so both zoom and pan retain the exact point.
    local px=(g.cl*g.cs+x*g.cw*g.cs-g.vl*g.vs)/g.vs
    local py=(g.vt*g.vs-g.ct*g.cs+y*g.ch*g.cs)/g.vs
    if finite(px)and finite(py)and px>=0 and py>=0 and px<=g.vw and py<=g.vh then
     used=used+1;local pin=pinAt(used,parent);pin.record=record
     pin:ClearAllPoints();pin:SetPoint("CENTER",parent,"TOPLEFT",px,-py)
     local r,green,b=color(N.members[record.name]);pin.dot:SetVertexColor(r,green,b,1);pin:Show()
    end
   end
  end
 end
 for index=used+1,#M.pins do M.pins[index]:Hide();M.pins[index].record=nil end
 M.visibleCount=used
 lastGeometry=table.concat({g.mapID,tostring(g.canvas),tostring(g.viewport),g.cw,g.ch,g.cs,g.cl,g.ct,g.vw,g.vh,g.vs,g.vl,g.vt,tostring(g.stitched)},"|")
end
function M.OnUpdate(dt)
 elapsed=elapsed+(finite(dt)and math.max(0,dt)or 0);positionWait=positionWait+(finite(dt)and math.max(0,dt)or 0)
 if elapsed<0.05 then return end;elapsed=0
 local g=geometry()
 if not g then hide();return end
 local key=table.concat({g.mapID,tostring(g.canvas),tostring(g.viewport),g.cw,g.ch,g.cs,g.cl,g.ct,g.vw,g.vh,g.vs,g.vl,g.vt,tostring(g.stitched)},"|")
 -- Data redraws twice a second. Geometry changes redraw immediately while a
 -- user pans/zooms; no map hooks, providers, protected scripts or CVars change.
 if positionWait>=0.5 or key~=lastGeometry then positionWait=0;M.Refresh(g)end
end
function M.ShowMember(name)
 if N.Full then name=N.Full(name)end
 local records=N.Tracking and invoke(N.Tracking.GetPositions)
 local record
 for _,candidate in ipairs(type(records)=="table"and records or{})do if candidate.name==name and valid(candidate)then record=candidate;break end end
 if not record then if N.Notify then N.Notify("This member has no recent shared position.")end;return false end
 if not N.Army or type(N.Army.Open)~="function"or N.Army.Open(record.mapID)~=true then return false end
 if stitched()then
  local u,v=invoke(OpenMapAPI.WorldFromMap,record.mapID,record.x,record.y)
  if finite(u)and finite(v)then invoke(OpenMapAPI.ShowWorld,u,v)end
 end
 M.Refresh();return true
end
if N.Tracking then
 local previous=N.Tracking.OnChanged
 N.Tracking.OnChanged=function(...)
  if type(previous)=="function"then previous(...)end
  M.Refresh()
 end
end
