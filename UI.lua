local _,N=...
-- Spacious native guild hall: split command pages and a full-width guild roster.
local GOLD={1,0.82,0}; local WHITE={1,1,1}; local MUTED={0.65,0.65,0.65}
local layout={windowWidth=850,windowHeight=520,panelX=10,panelWidth=550,fullWidth=830,detailX=568,detailWidth=248,contentInset=6,scrollGap=3,scrollbarWidth=16,chatX=210,chatWidth=630,chatRailWidth=190,chatY=132,chatHeight=302}
N.UILayout=layout
-- These preferences belong to this character, never to the guild's shared state.
local anchors={TOPLEFT={0,1},TOP={0.5,1},TOPRIGHT={1,1},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,0},BOTTOM={0.5,0},BOTTOMRIGHT={1,0}}
local movableFrames={};local frameBounds={};local restoredFor
local function finite(value)
 if type(issecretvalue)=="function"and issecretvalue(value)then return false end
 return type(value)=="number"and value==value and value~=math.huge and value~=-math.huge
end
local function positionStore()
 if type(NoDramaDB)~="table"or(IsLoggedIn and not IsLoggedIn())then return end
 local me=N.CharacterKey();if type(me)~="string"or me==""then return end
 if type(NoDramaDB.uiPositions)~="table"then NoDramaDB.uiPositions={}end
 if type(NoDramaDB.uiPositions[me])~="table"then NoDramaDB.uiPositions[me]={}end
 return NoDramaDB.uiPositions[me],me
end
local function boundedPosition(frame,p)
 if type(p)~="table"or not anchors[p.point]or not anchors[p.relativePoint]or not finite(p.x)or not finite(p.y)then return end
 local screenW,screenH=UIParent:GetWidth(),UIParent:GetHeight()
 local point,relative=anchors[p.point],anchors[p.relativePoint]
 local width,height=frame:GetWidth(),frame:GetHeight()
 local bounds=frameBounds[frame]or{}
 local left=relative[1]*screenW+p.x-point[1]*width
 local bottom=relative[2]*screenH+p.y-point[2]*height
 left=math.max(bounds.left or 0,math.min(math.max(0,screenW-width-(bounds.right or 0)),left))
 bottom=math.max(bounds.bottom or 0,math.min(math.max(0,screenH-height-(bounds.top or 0)),bottom))
 return {point=p.point,relativePoint=p.relativePoint,x=left+point[1]*width-relative[1]*screenW,y=bottom+point[2]*height-relative[2]*screenH}
end
local function applyPosition(frame,p)
 p=boundedPosition(frame,p);if not p then return false end
 frame:ClearAllPoints();frame:SetPoint(p.point,UIParent,p.relativePoint,p.x,p.y);return true
end
local function savePosition(frame,key)
 local store=positionStore();if not store then return end
 local point,relative,relativePoint,x,y=frame:GetPoint(1)
 if relative and relative~=UIParent then return end
 local p=boundedPosition(frame,{point=point,relativePoint=relativePoint,x=x,y=y})
 if p then store[key]=p;applyPosition(frame,p)end
end
local function movable(frame,key,default,handle,bounds)
 movableFrames[key]={frame=frame,default=default}
 frameBounds[frame]=bounds
 frame:SetMovable(true);frame:SetClampedToScreen(true)
 handle=handle or frame;handle:EnableMouse(true);handle:RegisterForDrag("LeftButton")
 handle:SetScript("OnDragStart",function(self)self.ndDragged=true;frame:StartMoving()end)
 handle:SetScript("OnDragStop",function()frame:StopMovingOrSizing();savePosition(frame,key)end)
 applyPosition(frame,default)
end
function N.RestoreUIPositions(force)
 local store,me=positionStore();if not store or(restoredFor==me and not force)then return end
 for key,entry in pairs(movableFrames)do
  if not applyPosition(entry.frame,store[key])then store[key]=nil;applyPosition(entry.frame,entry.default)end
 end
 restoredFor=me
end
function N.ResetUIPositions()
 local store=positionStore();if not store then return end
 for key in pairs(movableFrames)do store[key]=nil end
 N.RestoreUIPositions(true);N.Notify("Window, Army button, and alert positions reset.")
end
-- SetFont with a single file drops the game font's Cyrillic, Korean and Chinese
-- members, so those names rendered as boxes. A font family keeps every alphabet.
local fontFamilies={}
function N.SetFont(fs,size,flags)
 flags=flags or""
 local key=size.."|"..flags
 local family=fontFamilies[key]
 if family==nil then
  family=false
  if type(CreateFontFamily)=="function"then
   local function member(alphabet,file,height)return{alphabet=alphabet,file=file,height=height,flags=flags}end
   local ok,made=pcall(CreateFontFamily,"NoDramaFont"..size..flags:gsub("%W",""),{
    member("roman","Fonts\\FRIZQT__.TTF",size),member("korean","Fonts\\2002.TTF",size+1),
    member("simplifiedchinese","Fonts\\ARKai_T.ttf",size+2),member("traditionalchinese","Fonts\\blei00d.TTF",size+2),
    member("russian","Fonts\\FRIZQT___CYR.TTF",size)})
   if ok and made then family=made end
  end
  fontFamilies[key]=family
 end
 if not family then fs:SetFont("Fonts\\FRIZQT___CYR.TTF",size,flags);return end
 local r,g,b,a=fs:GetTextColor();local sx,sy=fs:GetShadowOffset();local sr,sg,sb,sa=fs:GetShadowColor()
 fs:SetFontObject(family)
 if r then fs:SetTextColor(r,g,b,a)end
 if sx then fs:SetShadowOffset(sx,sy)end
 if sr then fs:SetShadowColor(sr,sg,sb,sa)end
end
local function label(parent,font,x,y,w)
 local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
 t:SetPoint("TOPLEFT",x,y); t:SetWidth(w); t:SetJustifyH("LEFT"); t:SetJustifyV("TOP")
 return t
end
local function nativeFrame(kind,name,parent,template,fallback)
 local ok,f=pcall(CreateFrame,kind,name,parent,template)
 -- Some Forever templates return an empty frame instead of raising an error.
 if ok and f and (template~="PortraitFrameTemplate" or f.CloseButton) then return f end
 if ok and f then f:Hide() end
 return CreateFrame(kind,name and name.."Fallback" or nil,parent,fallback)
end
local function inset(parent,x,y,w,h)
 local f=nativeFrame("Frame",nil,parent,"InsetFrameTemplate","BackdropTemplate")
 f:SetPoint("TOPLEFT",x,y); f:SetSize(w,h)
 if f.Bg and f.Bg.SetVertexColor then f.Bg:SetVertexColor(0.12,0.12,0.12) end
 return f
end
local function button(parent,text,x,y,w,fn)
 local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
 b:SetSize(w,20); b:SetPoint("TOPLEFT",x,y); b:SetText(text)
 b:SetNormalFontObject("GameFontNormal"); b:SetHighlightFontObject("GameFontHighlight")
 b:SetScript("OnClick",fn)
 return b
end
local window=nativeFrame("Frame","NoDramaGuildHall",UIParent,"PortraitFrameTemplate","BasicFrameTemplateWithInset")
N.window=window; window:SetSize(layout.windowWidth,layout.windowHeight)
window:SetFrameStrata("HIGH")
movable(window,"guildHall",{point="CENTER",relativePoint="CENTER",x=0,y=40},nil,{right=48,top=12})
if window.SetClampRectInsets then window:SetClampRectInsets(0,48,12,0) end
if window.SetTitle then window:SetTitle("ZERO DRAMA")
elseif window.TitleText then window.TitleText:SetText("ZERO DRAMA") end
if type(window.TitleContainer)=="table" and window.TitleContainer.TitleText then window.TitleContainer.TitleText:SetText("ZERO DRAMA") end
if window.CloseButton then window.CloseButton:SetScript("OnClick",function() window:Hide() end) end
local portrait=window.portrait or window.Portrait or (window.PortraitContainer and window.PortraitContainer.portrait)
if portrait then portrait:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga")
elseif window.SetPortraitToAsset then window:SetPortraitToAsset("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga") end
window:Hide(); _G.NoDramaGuildHall=window; tinsert(UISpecialFrames,"NoDramaGuildHall")
local hallBackdrop=window:CreateTexture(nil,"BACKGROUND",nil,-7)
hallBackdrop:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock");hallBackdrop:SetPoint("TOPLEFT",7,-24);hallBackdrop:SetSize(836,486);hallBackdrop:SetVertexColor(0.22,0.16,0.14,1)
local hallBanner=window:CreateTexture(nil,"BACKGROUND",nil,-6)
hallBanner:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\WarHall\\WarBanner.tga");hallBanner:SetSize(130,260);hallBanner:SetPoint("TOPRIGHT",-15,-42);hallBanner:SetAlpha(0.18)
local total=label(window,"GameFontNormalLarge",64,-32,490)
local sub=label(window,"GameFontHighlightSmall",64,-53,490)
local hallMotto=label(window,"GameFontNormalSmall",572,-45,258);hallMotto:SetJustifyH("RIGHT");hallMotto:SetText("LOK'TAR OGAR!  |  GUILD HALL")
local listBox=inset(window,layout.panelX,-103,layout.panelWidth,377)
local detailBox=inset(window,layout.detailX,-103,272,377)
local parchment=detailBox:CreateTexture(nil,"BACKGROUND",nil,1)
-- QuestBG packs its visible parchment into 296x331 pixels of a 512x512 texture.
parchment:SetTexture("Interface\\QuestFrame\\QuestBG");parchment:SetTexCoord(0,296/512,0,331/512);parchment:SetPoint("TOPLEFT",4,-4);parchment:SetPoint("BOTTOMRIGHT",-4,4);parchment:SetVertexColor(0.91,0.84,0.69,1)
local detailShade=detailBox:CreateTexture(nil,"BACKGROUND",nil,2);detailShade:SetTexture("Interface\\Buttons\\WHITE8X8");detailShade:SetAllPoints(parchment);detailShade:SetVertexColor(0.09,0.055,0.025,0.12)
local detailCrest=detailBox:CreateTexture(nil,"BACKGROUND",nil,3);detailCrest:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga");detailCrest:SetTexCoord(0.15,0.85,0.08,0.78);detailCrest:SetSize(200,200);detailCrest:SetPoint("BOTTOMRIGHT",-16,16);detailCrest:SetAlpha(0.10)
local column=CreateFrame("Frame",nil,window); column:SetPoint("TOPLEFT",layout.panelX+layout.contentInset,-78); column:SetSize(528,24)
local columnLabels={}; local columnButtons={}
for i=1,2 do
 local c=nativeFrame("Button",nil,column,"ColumnDisplayButtonTemplate",nil)
 c:SetPoint("TOPLEFT",i==1 and 0 or 246,0); c:SetSize(i==1 and 246 or 62,24)
 local t=c.Text
 if not t then t=label(c,"GameFontHighlightSmall",5,-6,i==1 and 234 or 52) end
 columnLabels[i]=t
 columnButtons[i]=c
end
-- The current client has the thin Communities scrollbar. Older clients get the
-- classic bar, with an explicit inside gutter for its wider arrow buttons.
local okScroll,scroll=pcall(CreateFrame,"ScrollFrame","NoDramaListScroll",window,"ScrollFrameTemplate")
local thinScroll=okScroll and scroll and scroll.ScrollBar and type(scroll.ScrollBar)~="function"
if not thinScroll then
 if okScroll and scroll then scroll:Hide()end
 scroll=CreateFrame("ScrollFrame","NoDramaListScrollLegacy",window,"UIPanelScrollFrameTemplate")
else layout.scrollbarWidth=12 end
local scrollbar=scroll.ScrollBar or _G[(thinScroll and "NoDramaListScroll"or"NoDramaListScrollLegacy").."ScrollBar"]
if type(scrollbar)=="function"then scrollbar=nil end
local contentWidth=layout.panelWidth-layout.contentInset*2-layout.scrollGap-layout.scrollbarWidth
layout.contentWidth=contentWidth
scroll:SetPoint("TOPLEFT",listBox,"TOPLEFT",layout.contentInset,-3)
scroll:SetPoint("BOTTOMRIGHT",listBox,"BOTTOMRIGHT",-layout.contentInset-layout.scrollGap-layout.scrollbarWidth,3)
scroll:SetSize(contentWidth,371)
if scrollbar then
 scrollbar:ClearAllPoints();scrollbar:SetPoint("TOPLEFT",scroll,"TOPRIGHT",layout.scrollGap,-(thinScroll and 0 or 16))
 scrollbar:SetPoint("BOTTOMLEFT",scroll,"BOTTOMRIGHT",layout.scrollGap,thinScroll and 0 or 16);scrollbar:SetWidth(layout.scrollbarWidth)
end
local body=CreateFrame("Frame",nil,scroll); body:SetSize(contentWidth,371); scroll:SetScrollChild(body)
N.listScroll=scroll;N.listBody=body;N.listInset=listBox
local function syncContentWidth(width)
 if not finite(width)or width<=0 or width==contentWidth then return end
 contentWidth=width;layout.contentWidth=width;body:SetWidth(width)
 if N.Render and window:IsShown()then N.Render()end
end
local previousSizeScript=scroll:GetScript("OnSizeChanged")
scroll:SetScript("OnSizeChanged",function(self,width,height)
 if previousSizeScript then previousSizeScript(self,width,height)end
 syncContentWidth(width)
end)
local detailScroll=CreateFrame("ScrollFrame",nil,window)
detailScroll:SetPoint("TOPLEFT",layout.detailX+12,-115); detailScroll:SetSize(layout.detailWidth,353)
local detailBody=CreateFrame("Frame",nil,detailScroll); detailBody:SetSize(layout.detailWidth,353); detailScroll:SetScrollChild(detailBody)
local detail=label(detailBody,"GameFontHighlightSmall",0,0,layout.detailWidth)
detail:SetWordWrap(true);N.SetFont(detail,11);detail:SetSpacing(4);detail:SetTextColor(0.20,0.13,0.07)
detailScroll:EnableMouseWheel(true)
detailScroll:SetScript("OnMouseWheel",function(self,delta)
 local value=self:GetVerticalScroll() or 0
 self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange() or 0,value-delta*15)))
end)
local selected={}; local rows={}; local used=0; local actions={}; N.page="Guild chat"
local chatViews={GUILD={bottom=true,offset=0},OFFICER={bottom=true,offset=0}}
local restoringChatScroll=false
N.rosterRows=rows
local function showDetail(s)
 detail:SetText((s or ""):gsub("|cffffd100","|cff552c12"):gsub("|cffe0ad74","|cff6f3b16"))
 local height=detail:GetStringHeight() or 65
 detailBody:SetHeight(math.max(detailScroll:GetHeight(),height)); detailScroll:UpdateScrollChildRect()
end
local function plain(s) return N.Safe(s) end
local function gold(s) return "|cffffd100"..s.."|r" end
local function icon(name,size)
 return "|TInterface\\Icons\\"..name..":"..(size or 13).."|t"
end
local function role(m)
 if m.index==0 then return "GM" end
 return N.db and N.db.roles[m.name] or ""
end
local function roleBadge(m)
 return "|T"..N.BadgeTexture(m)..":16|t "
end
local function livePosition(name)
 if N.Tracking then for _,record in ipairs(N.Tracking.GetPositions())do if record.name==name then return record end end end
end
local function liveLine(record)
 return plain(record.zone or"Unknown area")..string.format("  %.1f, %.1f  (%ds ago)",record.x*100,record.y*100,math.floor(record.age or 0))
end
local function continentSummary(census)
 if not C_Map or not C_Map.GetMapInfo then return nil end
 local counts={}
 for _,z in ipairs(census.zones) do
  local id=z.mapID; local visited={}
  for _=1,12 do
   if not id or visited[id] then break end; visited[id]=true
   local info=C_Map.GetMapInfo(id); if not info then break end
   if info.mapType==2 then counts[info.name]=(counts[info.name] or 0)+z.count; break end
   id=info.parentMapID
  end
 end
 local list={}; for name,count in pairs(counts) do list[#list+1]=plain(name).." "..count end
 table.sort(list)
 return #list>0 and table.concat(list," \194\183 ") or nil
end
local function action(index,text,fn)
 local b=actions[index]
 if not b then b=button(window,text,10+(index-1)*210,-491,200,fn); actions[index]=b end
 b:SetText(text); b:SetScript("OnClick",fn); b:Show(); return b
end
local function tooltip(owner,title,lines)
 GameTooltip:SetOwner(owner,"ANCHOR_RIGHT"); GameTooltip:SetText(title,1,0.82,0)
 for _,s in ipairs(lines or {}) do GameTooltip:AddLine(s,1,1,1,true) end
 GameTooltip:Show()
end
local function listRow(y,left,right,key,fn,tip,height)
 used=used+1; local r=rows[used]; height=height or 20
 if not r then
  r=CreateFrame("Button",nil,body)
  r.left=label(r,"GameFontHighlightSmall",3,-4,239)
  r.right=label(r,"GameFontHighlightSmall",249,-4,56)
  r.right:SetJustifyH("RIGHT"); r.right:SetWordWrap(false)
  r.highlight=r:CreateTexture(nil,"BACKGROUND"); r.highlight:SetAllPoints()
  r.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); r.highlight:SetAlpha(0.28)
  rows[used]=r
 end
 r:ClearAllPoints(); r:SetPoint("TOPLEFT",0,-y); r:SetSize(contentWidth,height)
 if r.chatBg then r.chatBg:Hide();r.left:SetParent(r)end
 if r.chatAvatar then r.chatAvatar:Hide()end
 if r.chatSender then r.chatSender:Hide();r.chatTime:Hide()end
 if r.memberInfo then r.memberInfo:Hide();r.memberArea:Hide()end
 if r.memberColumns then for _,text in ipairs(r.memberColumns)do text:Hide()end end
 if r.rowShade then r.rowShade:Hide()end
 if r.requestInfo then r.requestInfo:Hide()end
 r.left:ClearAllPoints();r.left:SetPoint("TOPLEFT",3,-4);r.left:SetFontObject("GameFontHighlightSmall");r.left:SetTextColor(1,1,1);r.left:SetSpacing(0)
 r.left:SetText(left or ""); r.right:SetText(right or "");r.left:Show();r.right:Show()
 local rightWidth=N.page=="Roster"and 86 or 56
 r.left:SetWidth(right and right~=""and contentWidth-rightWidth-12 or contentWidth-6);r.left:SetWordWrap(height>20)
 r.right:ClearAllPoints();r.right:SetPoint("TOPLEFT",contentWidth-rightWidth-2,-4);r.right:SetWidth(rightWidth)
 r.highlight:SetShown(key~=nil and selected[N.page]==key)
 r:SetScript("OnClick",function()
  if key~=nil then selected[N.page]=key; detailScroll:SetVerticalScroll(0) end
  if fn then fn() end
  N.Render()
 end)
 r:SetScript("OnEnter",function(self)
  self.highlight:Show()
  if tip then tip(self) end
 end)
 r:SetScript("OnLeave",function(self)
  self.highlight:SetShown(key~=nil and selected[N.page]==key); GameTooltip:Hide()
 end)
 r:Show(); return r
end
local textBlock
local block=label(body,"GameFontHighlightSmall",6,-6,294); block:SetWordWrap(true)
textBlock=function(s)
 block:SetWidth(contentWidth-12);block:SetText(s); block:Show()
 return math.max(229,(block:GetStringHeight() or 229)+12)
end
local dialog=nativeFrame("Frame",nil,window,"BasicFrameTemplateWithInset","BackdropTemplate")
dialog:SetSize(330,242); dialog:SetPoint("CENTER"); dialog:SetFrameLevel(window:GetFrameLevel()+30); dialog:Hide()
if dialog.CloseButton then dialog.CloseButton:SetScript("OnClick",function() dialog:Hide() end) end
local dialogTitle=label(dialog,"GameFontNormal",12,-9,290)
local dialogHelp=label(dialog,"GameFontHighlightSmall",16,-35,298); dialogHelp:SetWordWrap(true)
local fields={}; local confirm
for i=1,3 do
 local e=CreateFrame("EditBox",nil,dialog,"InputBoxTemplate")
 e:SetSize(286,26); e:SetPoint("TOPLEFT",22,-92-(i-1)*34); e:SetAutoFocus(false)
 e:SetMaxBytes(i==1 and 240 or 100); e:SetScript("OnEscapePressed",function() dialog:Hide() end); fields[i]=e
end
button(dialog,"Confirm",12,-211,150,function()
 if confirm and confirm(fields[1]:GetText(),fields[2]:GetText(),fields[3]:GetText())==false then
  N.Notify("Action unavailable. Check permissions and fields."); return
 end
 dialog:Hide(); N.Render()
end)
button(dialog,"Cancel",168,-211,150,function() dialog:Hide() end)
local function ask(title,help,values,fn)
 dialogTitle:SetText(title); dialogHelp:SetText(help); confirm=fn
 for i,e in ipairs(fields) do e:SetText(values[i] or ""); e:SetShown(values[i]~=nil) end
 dialog:Show(); if values[1]~=nil then fields[1]:SetFocus() end
end
do
 local half=math.floor((layout.detailWidth-6)/2)
 local target
 local function change(sign)
  return function()
   if not target then return end
   local name=plain(target.name:match("^[^-]+")or target.name)
   ask((sign>0 and"Add points: "or"Remove points: ")..name,"Enter the number of points and an optional reason. Everyone with the addon sees the new total.",{sign>0 and"10"or"5",""},function(amount,reason)
    local value=tonumber(amount);if not value or value<=0 or value%1~=0 then return false end
    return N.Points.Adjust(target.name,sign*value,reason)
   end)
  end
 end
 local add=button(window,"+ Add points",layout.detailX+12,-446,half,change(1))
 local remove=button(window,"- Remove points",layout.detailX+18+half,-446,half,change(-1))
 add:Hide();remove:Hide()
 function N.UpdatePointsControls(m)
  local show=(m~=nil and N.Points and N.Points.CanEdit()and not N.Points.IsExempt(m.name))and true or false
  target=show and m or nil;add:SetShown(show);remove:SetShown(show)
  detailScroll:SetHeight(show and 326 or 353)
 end
end
local drafts={GUILD="",OFFICER=""}; local composerChannel; local draftScope
local composer=inset(window,layout.chatX,-442,layout.chatWidth,64)
local chatEdit=CreateFrame("EditBox","NoDramaChatInput",window,"InputBoxTemplate"); N.chatInput=chatEdit
chatEdit:SetPoint("TOPLEFT",layout.chatX+13,-451); chatEdit:SetSize(layout.chatWidth-100,26); chatEdit:SetAutoFocus(false); chatEdit:SetMaxBytes(240); N.SetFont(chatEdit,12)
local placeholder=label(window,"GameFontDisableSmall",layout.chatX+17,-459,layout.chatWidth-118); placeholder:SetText("Message guild...")
local composerHint=label(window,"GameFontDisableSmall",layout.chatX+13,-484,layout.chatWidth-75)
local composerCount=label(window,"GameFontDisableSmall",layout.chatX+layout.chatWidth-57,-484,40);composerCount:SetJustifyH("RIGHT");composerCount:SetText("0/240")
local function sendChat()
 local channel=composerChannel
 if not channel or not N.db or not IsInGuild() then return false end
 if channel=="OFFICER" and not N.IsOfficer(N.Me()) then N.Notify("Officer chat access is required."); return false end
 local value=plain(chatEdit:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
 if value=="" then return false end
 SendChatMessage(N.Clip(value,240),channel)
 drafts[channel]=""; chatEdit:SetText(""); return true
end
N.SendChatFromWindow=sendChat
local sendButton=button(window,"Send",layout.chatX+layout.chatWidth-76,-451,64,sendChat);sendButton:SetHeight(26)
N.chatComposer=composer;N.chatSendButton=sendButton
chatEdit:SetScript("OnEnterPressed",sendChat)
chatEdit:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
chatEdit:SetScript("OnTextChanged",function(self)
 if composerChannel then drafts[composerChannel]=self:GetText() or "" end
 placeholder:SetShown((self:GetText() or "")=="" and not self:HasFocus())
 composerCount:SetText(#(self:GetText()or"").."/240")
 sendButton:SetEnabled((self:GetText()or""):find("%S")~=nil)
end)
chatEdit:SetScript("OnEditFocusGained",function()placeholder:Hide()end)
chatEdit:SetScript("OnEditFocusLost",function(self)placeholder:SetShown((self:GetText() or "")=="")end)
-- An independent conversation rail and native bubble treatment, inspired by the
-- user's open messenger. No Messenger assets, code or key bindings are imported.
local chatRail=inset(window,layout.panelX,-78,layout.chatRailWidth,428)
local chatRailHeading=label(chatRail,"GameFontNormalSmall",12,-12,166);chatRailHeading:SetText("CONVERSATIONS")
local chatHeader=inset(window,layout.chatX,-78,layout.chatWidth,48)
local chatCrest=chatHeader:CreateTexture(nil,"ARTWORK");chatCrest:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga");chatCrest:SetSize(36,36);chatCrest:SetPoint("TOPLEFT",8,-6)
local chatTitle=label(chatHeader,"GameFontNormal",54,-8,layout.chatWidth-65)
local chatSubtitle=label(chatHeader,"GameFontHighlightSmall",54,-27,layout.chatWidth-65)
local chatRooms={}
local function selectPage(page)
 N.page=page;restoringChatScroll=true;scroll:SetVerticalScroll(0);restoringChatScroll=false
 detailScroll:SetVerticalScroll(0);N.Render()
end
for i,room in ipairs({{page="Guild chat",title="Guild chat",hint="All guild members",badge="Champion"},{page="Officer chat",title="Officer council",hint="Guild officers only",badge="WarStrategist"}})do
 local b=CreateFrame("Button",nil,chatRail,"BackdropTemplate");b:SetSize(176,54);b:SetPoint("TOPLEFT",7,-29-(i-1)*58)
 b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,insets={left=3,right=3,top=3,bottom=3}})
 b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Badges\\"..room.badge..".tga");b.icon:SetSize(28,28);b.icon:SetPoint("TOPLEFT",8,-12)
 b.title=label(b,"GameFontNormalSmall",43,-12,125);b.title:SetText(room.title)
 b.hint=label(b,"GameFontHighlightSmall",43,-29,125);N.SetFont(b.hint,9);b.hint:SetText(room.hint)
 b:SetScript("OnClick",function()selectPage(room.page)end);chatRooms[room.page]=b
end
N.chatRooms=chatRooms;N.chatRail=chatRail;N.chatHeader=chatHeader
local chatRule=chatRail:CreateTexture(nil,"ARTWORK");chatRule:SetTexture("Interface\\Buttons\\WHITE8X8");chatRule:SetSize(166,1);chatRule:SetPoint("TOPLEFT",12,-158);chatRule:SetVertexColor(0.42,0.31,0.17,0.6)
local noticeHeading=label(chatRail,"GameFontNormalSmall",12,-173,166);noticeHeading:SetText("GUILD NOTICE")
local chatNotice=label(chatRail,"GameFontHighlightSmall",12,-193,166);N.SetFont(chatNotice,11);chatNotice:SetSpacing(3);chatNotice:SetHeight(177);chatNotice:SetWordWrap(true);chatNotice:SetMaxLines(12);chatNotice:SetTextColor(0.76,0.74,0.66)
local chatHistoryHint=label(chatRail,"GameFontDisableSmall",12,-375,166);chatHistoryHint:SetText("Protected chat text is not saved.")
local railRoster=button(chatRail,"Members & ranks",8,-397,174,function()selectPage("Roster")end)
local chatLatest=button(window,"Jump to latest",layout.chatX+layout.chatWidth-157,-411,138,function()
 if composerChannel then chatViews[composerChannel].bottom=true;chatViews[composerChannel].offset=scroll:GetVerticalScrollRange()or 0 end
 scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()or 0)
end);N.chatLatest=chatLatest;chatLatest:Hide()
-- Keep the template's scrollbar in sync when restoring a conversation at its
-- latest message. Replacing this handler otherwise leaves the thumb at zero
-- and makes the first mouse-wheel scroll jump or do nothing.
local nativeVerticalScroll=scroll:GetScript("OnVerticalScroll")
scroll:SetScript("OnVerticalScroll",function(self,value)
 if nativeVerticalScroll then nativeVerticalScroll(self,value)end
 if restoringChatScroll or not composerChannel or(N.page~="Guild chat"and N.page~="Officer chat")then return end
 local view=chatViews[composerChannel];view.offset=finite(value)and value or self:GetVerticalScroll()or 0
 view.bottom=(self:GetVerticalScrollRange()or 0)-view.offset<24
 chatLatest:SetShown(not view.bottom)
end)
local rosterTools=CreateFrame("Frame",nil,window);rosterTools:SetPoint("TOPLEFT",12,-77);rosterTools:SetSize(540,24)
local rosterSearch=CreateFrame("EditBox","NoDramaRosterSearch",rosterTools,"InputBoxTemplate");N.rosterSearch=rosterSearch
rosterSearch:SetPoint("TOPLEFT",9,0);rosterSearch:SetSize(390,22);rosterSearch:SetAutoFocus(false);rosterSearch:SetMaxBytes(80);N.SetFont(rosterSearch,10)
local searchHint=label(rosterTools,"GameFontDisableSmall",13,-7,378);searchHint:SetText("Search name, class, rank or area...")
local onlineOnly=CreateFrame("CheckButton","NoDramaRosterOnlineOnly",rosterTools,"UICheckButtonTemplate");onlineOnly:SetPoint("TOPLEFT",407,2);onlineOnly:SetSize(24,24);onlineOnly:SetChecked(false)
local onlineCaption=label(rosterTools,"GameFontHighlightSmall",433,-6,90);onlineCaption:SetText("Online only")
rosterSearch:SetScript("OnTextChanged",function(self)searchHint:SetShown((self:GetText()or"")==""and not self:HasFocus());if N.Render then N.Render()end end)
rosterSearch:SetScript("OnEditFocusGained",function()searchHint:Hide()end)
rosterSearch:SetScript("OnEditFocusLost",function(self)searchHint:SetShown((self:GetText()or"")=="")end)
rosterSearch:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
onlineOnly:SetScript("OnClick",function()if N.Render then N.Render()end end)
local locationToggle=CreateFrame("CheckButton","NoDramaShareLocation",window,"UICheckButtonTemplate");N.locationToggle=locationToggle
locationToggle:SetPoint("TOPLEFT",568,-75);locationToggle:SetSize(24,24)
local locationCaption=label(window,"GameFontHighlightSmall",595,-82,225);locationCaption:SetText("Share my live location")
locationToggle:SetScript("OnClick",function(self)if N.Tracking then N.Tracking.SetSharing(self:GetChecked());N.Render()end end)
locationToggle:SetScript("OnEnter",function(self)tooltip(self,"Guild location sharing",{"Share your outdoor coordinates with online guild addon users.","Updates while moving; old markers expire after 30 seconds.","Turn off to stop sharing. Different layers and phases are not verified."})end)
locationToggle:SetScript("OnLeave",function()GameTooltip:Hide()end)
local censusToggle=CreateFrame("CheckButton","NoDramaRegionCounts",window,"UICheckButtonTemplate");N.censusToggle=censusToggle
censusToggle:SetPoint("TOPLEFT",647,-487);censusToggle:SetSize(24,24)
local censusCaption=label(window,"GameFontHighlightSmall",674,-494,160);censusCaption:SetText("Region player counts")
censusToggle:SetScript("OnClick",function(self)if N.Army and N.Army.SetCensusEnabled then N.Army.SetCensusEnabled(self:GetChecked());N.Render()end end)
censusToggle:SetScript("OnEnter",function(self)tooltip(self,"Region player counts",{"Show one player-count marker per guild zone on the map.","Off by default. Requires map pins to be enabled.","This does not change live member locations or Army rally calls."})end)
censusToggle:SetScript("OnLeave",function()GameTooltip:Hide()end)
local rosterHeader=CreateFrame("Frame",nil,window);rosterHeader:SetPoint("TOPLEFT",layout.panelX+layout.contentInset,-105);rosterHeader:SetSize(808,24)
local classStrip=label(window,"GameFontHighlightSmall",layout.panelX+layout.contentInset+4,-365,layout.fullWidth-20);N.SetFont(classStrip,10);classStrip:SetWordWrap(false);classStrip:Hide()
-- N.Render is at Lua 5.1's 60-upvalue limit; it must reach this through N.
N.classStrip=classStrip
local rosterColumns={
 {key="name",label="Name",fraction=0.2}, {key="level",label="Lv",fraction=0.045},
 {key="class",label="Class",fraction=0.1}, {key="rank",label="Guild rank",fraction=0.16},
 {key="points",label="Points",fraction=0.075},
 {key="zone",label="Area / last seen",fraction=0.195}, {key="status",label="Status",fraction=0.095},
 {key="addon",label="Addon",fraction=0.13},
}
N.rosterColumns=rosterColumns;N.rosterHeaders={}
local rosterSort,rosterDescending="rank",false
function N.SortRoster(key)
 local exists=false;for _,col in ipairs(rosterColumns)do if col.key==key then exists=true end end
 if not exists then return end
 if rosterSort==key then rosterDescending=not rosterDescending else rosterSort=key;rosterDescending=false end
 if N.listScroll then N.listScroll:SetVerticalScroll(0)end
 if N.Render then N.Render()end
end
for i,col in ipairs(rosterColumns)do
 local header=nativeFrame("Button",nil,rosterHeader,"ColumnDisplayButtonTemplate",nil)
 local title=header.Text;if not title then title=label(header,"GameFontNormalSmall",4,-6,100)end
 header.ndTitle=title;header:SetHeight(24);header:SetScript("OnClick",function()N.SortRoster(col.key)end);N.rosterHeaders[i]=header
end
local function layoutRosterColumns(width)
 local x=0
 for i,col in ipairs(rosterColumns)do
  col.x=x;col.width=i==#rosterColumns and width-x or math.floor(width*col.fraction);x=x+col.width
  local header=N.rosterHeaders[i];header:ClearAllPoints();header:SetPoint("TOPLEFT",col.x,0);header:SetWidth(col.width)
  header.ndTitle:SetWidth(math.max(1,col.width-8));header.ndTitle:SetText(col.label..(rosterSort==col.key and(rosterDescending and" v"or" ^")or""))
 end
 rosterHeader:SetWidth(width)
end
local pollDrafts={};local pollCards={}
local creator=nativeFrame("Frame","NoDramaPollCreator",window,"BasicFrameTemplateWithInset","BackdropTemplate")
N.pollCreator=creator;creator:SetSize(330,410);creator:SetPoint("CENTER");creator:SetFrameLevel(window:GetFrameLevel()+35);creator:Hide()
tinsert(UISpecialFrames,"NoDramaPollCreator")
local creatorTitle=label(creator,"GameFontNormal",14,-8,280);creatorTitle:SetText("New ZERO DRAMA poll")
local questionLabel=label(creator,"GameFontNormalSmall",16,-36,290);questionLabel:SetText("Question")
local question=CreateFrame("EditBox","NoDramaPollQuestion",creator,"InputBoxTemplate");question:SetPoint("TOPLEFT",20,-53);question:SetSize(286,25);question:SetMaxBytes(120);question:SetAutoFocus(false)
local optionScroll=CreateFrame("ScrollFrame",nil,creator,"UIPanelScrollFrameTemplate");optionScroll:SetPoint("TOPLEFT",14,-90);optionScroll:SetSize(283,221)
local optionBody=CreateFrame("Frame",nil,optionScroll);optionBody:SetSize(280,221);optionScroll:SetScrollChild(optionBody)
local optionFields={};local optionCount=2
local function layoutCreator()
 for i=1,10 do optionFields[i]:SetShown(i<=optionCount);optionFields[i].caption:SetShown(i<=optionCount)end
 optionBody:SetHeight(math.max(221,optionCount*45));optionScroll:UpdateScrollChildRect()
end
for i=1,10 do
 local e=CreateFrame("EditBox",nil,optionBody,"InputBoxTemplate");e:SetPoint("TOPLEFT",9,-19-(i-1)*45);e:SetSize(260,24);e:SetAutoFocus(false);e:SetMaxBytes(60)
 e.caption=label(optionBody,"GameFontHighlightSmall",4,-2-(i-1)*45,260);e.caption:SetText("Option "..i);optionFields[i]=e
end
local multiple=CreateFrame("CheckButton","NoDramaPollAllowMultiple",creator,"UICheckButtonTemplate");multiple:SetPoint("TOPLEFT",11,-318);multiple:SetSize(26,26);multiple:SetChecked(true)
local multipleLabel=label(creator,"GameFontHighlightSmall",40,-326,270);multipleLabel:SetText("Allow multiple answers")
button(creator,"Add Option",14,-352,144,function()if optionCount<10 then optionCount=optionCount+1;layoutCreator();optionScroll:SetVerticalScroll(math.max(0,optionCount*45-221));optionFields[optionCount]:SetFocus()end end)
button(creator,"Remove Last",170,-352,144,function()if optionCount>2 then optionFields[optionCount]:SetText("");optionCount=optionCount-1;layoutCreator()end end)
button(creator,"Create Poll",14,-382,144,function()
 local options={};for i=1,optionCount do options[i]=optionFields[i]:GetText()end
 if not N.CreatePoll(question:GetText(),options,multiple:GetChecked())then N.Notify("Use a question and 2-10 different answers. Check officer access and message queue.");return end
 creator:Hide();N.Render()
end)
button(creator,"Cancel",170,-382,144,function()creator:Hide()end)
if creator.CloseButton then creator.CloseButton:SetScript("OnClick",function()creator:Hide()end)end
local function openPollCreator()
 if not N.IsOfficer(N.Me())then return end
 question:SetText("");optionCount=2;for _,e in ipairs(optionFields)do e:SetText("")end
 multiple:SetChecked(true);layoutCreator();optionScroll:SetVerticalScroll(0);creator:Show();question:SetFocus()
end
local function renderPollCards(officer)
 local ids={};for id in pairs(N.db.polls)do ids[#ids+1]=id end
 table.sort(ids,function(a,b)local pa,pb=N.db.polls[a],N.db.polls[b];if not not pa.closed~=not not pb.closed then return not pa.closed end;return a>b end)
 local y=0;local active=0
 for position,id in ipairs(ids)do
  local p=N.db.polls[id];if not p.closed then active=active+1 end
  local card=pollCards[position]
  if not card then
   card=nativeFrame("Frame",nil,body,"BackdropTemplate",nil)
   card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
   card:SetBackdropColor(0.075,0.075,0.055,0.98);card:SetBackdropBorderColor(0.43,0.37,0.23,1)
   card.title=label(card,"GameFontNormal",9,-9,288);card.meta=label(card,"GameFontDisableSmall",9,-28,288)
   card.options={};card.voters=label(card,"GameFontDisableSmall",9,-100,170)
   card.submit=button(card,"Vote",9,-120,136,function()end);card.close=button(card,"Close",222,-120,76,function()end)
   pollCards[position]=card
  end
  card:ClearAllPoints();card:SetPoint("TOPLEFT",0,-y);card:SetWidth(contentWidth);card:Show()
  card.title:SetWidth(contentWidth-18);card.meta:SetWidth(contentWidth-18);card.title:SetText(plain(p.question))
  local questionH=math.max(14,card.title:GetStringHeight()or 14)
  card.meta:ClearAllPoints();card.meta:SetPoint("TOPLEFT",9,-11-questionH)
  card.meta:SetText(p.closed and "Closed" or (p.allowMultiple and "Choose one or more answers" or "Choose one answer"))
  local selectedBallot=N.PollBallot(p,N.Me());local draft=pollDrafts[id]
  if not draft or p.closed then draft={};for _,choice in ipairs(selectedBallot)do draft[choice]=true end;pollDrafts[id]=draft end
  local counts,voters=N.PollCounts(p);local optionY=29+questionH
  for _,option in ipairs(card.options)do option:Hide()end
  for i,value in ipairs(p.options)do
   local option=card.options[i]
   if not option then
    option=CreateFrame("Button",nil,card);option:SetWidth(289)
    option.bar=option:CreateTexture(nil,"BACKGROUND");option.bar:SetTexture("Interface\\Buttons\\WHITE8X8");option.bar:SetVertexColor(0.38,0.30,0.12,0.25);option.bar:SetPoint("TOPLEFT",26,-1);option.bar:SetHeight(20)
   option.check=CreateFrame("CheckButton",nil,option,"UICheckButtonTemplate");option.check:SetSize(24,24);option.check:SetPoint("TOPLEFT",-1,2)
    option.label=label(option,"GameFontHighlightSmall",26,-4,232);option.label:SetWordWrap(true)
    option.count=label(option,"GameFontDisableSmall",261,-4,25);option.count:SetJustifyH("RIGHT")
    card.options[i]=option
   end
   local choice=i;local function choose()
    if p.closed then return end
    local nextValue=not draft[choice]
    if not p.allowMultiple then for key in pairs(draft)do draft[key]=nil end end
    draft[choice]=nextValue or nil;N.Render()
   end
   option:SetPoint("TOPLEFT",9,-optionY);option:SetWidth(contentWidth-18);option.label:SetWidth(contentWidth-75)
   option.count:ClearAllPoints();option.count:SetPoint("TOPLEFT",contentWidth-46,-4)
   option.label:SetText(plain(value));option.count:SetText(counts[i]or 0)
   local height=math.max(20,(option.label:GetStringHeight()or 12)+7);option:SetHeight(height)
   option.bar:SetHeight(height-3);option.bar:SetWidth(math.max(1,(contentWidth-77)*(counts[i]or 0)/math.max(1,voters)))
   option.check:SetChecked(draft[i]or false);option.check:SetEnabled(not p.closed);option.check:SetScript("OnClick",choose);option:SetScript("OnClick",choose);option:Show();optionY=optionY+height
  end
  card.voters:ClearAllPoints();card.voters:SetPoint("TOPLEFT",9,-optionY-3);card.voters:SetText(voters.." voters - received locally")
  local bottom=optionY+16;card.submit:ClearAllPoints();card.submit:SetPoint("TOPLEFT",9,-bottom)
  card.submit:SetText(#selectedBallot>0 and "Update Vote"or"Vote");card.submit:SetShown(not p.closed)
  card.submit:SetScript("OnClick",function()
   local choices={};for i=1,#p.options do if draft[i]then choices[#choices+1]=i end end
   if not N.Vote(id,choices)then N.Notify("Vote unavailable. The poll may be closed or the queue full.");return end
   pollDrafts[id]=nil;N.Render()
  end)
  card.close:ClearAllPoints();card.close:SetPoint("TOPLEFT",contentWidth-85,-bottom);card.close:SetShown(officer and not p.closed)
  card.close:SetScript("OnClick",function()ask("Close this poll?",plain(p.question).."\nVoting will stop only for this poll.",{},function()return N.ClosePoll(id)end)end)
  card:SetHeight(bottom+(p.closed and 0 or 20)+7);y=y+card:GetHeight()+6
 end
 if #ids==0 then y=textBlock("No guild polls received.\nOfficers can create several polls, each with up to ten choices.")end
 if officer then action(1,"Create Poll",openPollCreator)end
 return y,active,#ids
end
local requestIcon="Interface\\AddOns\\NO_DRAMA\\Media\\ArmyWarning.tga"
local function activeCalls()return N.Army.ActiveRequests and N.Army.ActiveRequests()or{}end
local function coords(r)return string.format("%.1f, %.1f",(tonumber(r.x)or 0)*100,(tonumber(r.y)or 0)*100)end
local requestIndex=1;local showingCall
local cancelRequest=nativeFrame("Frame","NoDramaArmyCancelDialog",UIParent,"BasicFrameTemplateWithInset","BackdropTemplate")
cancelRequest:SetSize(330,152);cancelRequest:SetPoint("CENTER");cancelRequest:SetFrameStrata("DIALOG");cancelRequest:Hide();N.armyCancelDialog=cancelRequest
tinsert(UISpecialFrames,"NoDramaArmyCancelDialog")
local cancelHeading=label(cancelRequest,"GameFontNormal",12,-10,294);cancelHeading:SetText("Cancel Army request?")
local cancelBody=label(cancelRequest,"GameFontHighlightSmall",16,-42,296);local cancelID
if cancelRequest.CloseButton then cancelRequest.CloseButton:SetScript("OnClick",function()cancelRequest:Hide()end)end
button(cancelRequest,"Cancel Request",12,-116,150,function()
 if not cancelID or not N.Army.CancelHelp or not N.Army.CancelHelp(cancelID)then N.Notify("This request is no longer active, or you cannot cancel it.");return end
 cancelRequest:Hide()
end)
button(cancelRequest,"Keep Active",168,-116,150,function()cancelRequest:Hide()end)
local function askCancel(r)
 if not r or not N.Army.CanCancel or not N.Army.CanCancel(r)then return end
 cancelID=r.id;cancelBody:SetText(plain(r.caller).."\n"..plain(r.zone).." ("..coords(r)..")\nCancels the marker and flashing alert for this call.");cancelRequest:Show()
end
local hud=button(UIParent,"",0,0,158,function(self)
 if self.ndDragged then self.ndDragged=false;return end
 if N.Army.RequestHelp then N.Army.RequestHelp()end
end)
N.requestArmyButton=hud;hud:SetFrameStrata("HIGH");hud:SetFrameLevel(250);hud:SetText("|T"..requestIcon..":15|t Request Army!")
movable(hud,"armyButton",{point="BOTTOMRIGHT",relativePoint="BOTTOMRIGHT",x=-36,y=180})
hud:SetScript("OnMouseDown",function(self)self.ndDragged=false end)
hud:SetScript("OnEnter",function(self)tooltip(self,"Request Army!",{"Ask the guild for help against the Alliance.","Shares a rally point at your current location.","Stays active until you, an officer, or the GM cancels.","Drag to move. Position is saved for this character.","/ndreset restores the default positions."})end)
hud:SetScript("OnLeave",function()GameTooltip:Hide()end)
do
 local W,H=440,146
 local preview;local seen={}
 local alert=nativeFrame("Frame","NoDramaArmyAlert",UIParent,"BackdropTemplate",nil);N.armyAlert=alert
 alert:SetSize(W,H);alert:SetFrameStrata("HIGH");alert:SetFrameLevel(200);alert:Hide()
 alert:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
 alert:SetBackdropColor(0.16,0.02,0.012,0.98);alert:SetBackdropBorderColor(0.95,0.5,0.14,1)
 local banner=alert:CreateTexture(nil,"BORDER");banner:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
 banner:SetVertexColor(0.62,0.1,0.04,0.95);banner:SetPoint("TOPLEFT",7,-7);banner:SetPoint("TOPRIGHT",-7,-7);banner:SetHeight(30)
 local rule=alert:CreateTexture(nil,"ARTWORK");rule:SetTexture("Interface\\Buttons\\WHITE8X8");rule:SetVertexColor(1,0.74,0.25,0.55)
 rule:SetPoint("TOPLEFT",banner,"BOTTOMLEFT",0,0);rule:SetPoint("TOPRIGHT",banner,"BOTTOMRIGHT",0,0);rule:SetHeight(1)
 local handle=CreateFrame("Frame",nil,alert);handle:SetPoint("TOPLEFT",7,-7);handle:SetSize(W-70,30);handle:SetFrameLevel(alert:GetFrameLevel()+1)
 N.armyAlertDragHandle=handle
 movable(alert,"armyAlert",{point="TOP",relativePoint="TOP",x=0,y=-92},handle)
 handle:SetScript("OnEnter",function(self)tooltip(self,"Request Army!",{"Drag this heading to move the alert.","Your position is saved for this character.","/ndreset restores the default positions."})end)
 handle:SetScript("OnLeave",function()GameTooltip:Hide()end)
 local crest=alert:CreateTexture(nil,"ARTWORK");crest:SetTexture(requestIcon);crest:SetSize(18,18);crest:SetPoint("TOPLEFT",14,-13)
 local title=alert:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("LEFT",crest,"RIGHT",6,0);title:SetText("REQUEST ARMY!");title:SetTextColor(1,0.82,0.35)
 local counter=alert:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");counter:SetPoint("TOPRIGHT",-62,-16)
 local glow=alert:CreateTexture(nil,"ARTWORK");glow:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center");glow:SetVertexColor(1,0.3,0.08,1);glow:SetPoint("CENTER",alert,"TOPLEFT",42,-68)
 local icon=alert:CreateTexture(nil,"OVERLAY");icon:SetTexture(requestIcon);icon:SetSize(46,46);icon:SetPoint("CENTER",glow,"CENTER")
 local who=label(alert,"GameFontHighlight",78,-46,W-92)
 local where=label(alert,"GameFontHighlightSmall",78,-66,W-92)
 local footer=label(alert,"GameFontDisableSmall",16,-124,W-32);footer:SetJustifyH("CENTER")
 local function short(r)return plain(r.caller:match("^[^-]+")or r.caller)end
 local function done()preview=nil;N.UpdateArmyAlert()end
 local coming=button(alert,"|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t I'm on my way",0,0,148,function()
  local r=showingCall;if not r then return end
  if preview then N.Notify("Preview: this would post in guild chat: "..N.Army.ComingMessage(r));return done()end
  N.Army.Respond(r.id,"coming")
 end)
 local busy=button(alert,"|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t I'm busy",0,0,104,function()
  local r=showingCall;if not r then return end
  if preview then N.Notify("Preview: you would stop getting alerts for this call.");return done()end
  N.Army.Respond(r.id,"busy")
 end)
 local map=button(alert,"Show Map",0,0,88,function()local r=showingCall;if r then N.Army.Open(r.mapID,r.x,r.y)end end)
 local stop=button(alert,"Cancel",0,0,66,function()if preview then return done()end;askCancel(showingCall)end)
 local function place(b,x,w)b:ClearAllPoints();b:SetPoint("TOPLEFT",x,-94);b:SetWidth(w);b:Show()end
 local function step(delta)return function()requestIndex=requestIndex+delta;N.UpdateArmyAlert()end end
 local prev=button(alert,"<",0,0,24,step(-1));prev:ClearAllPoints();prev:SetPoint("TOPRIGHT",-36,-12)
 local nextCall=button(alert,">",0,0,24,step(1));nextCall:ClearAllPoints();nextCall:SetPoint("TOPRIGHT",-12,-12)
 prev:SetFrameLevel(handle:GetFrameLevel()+2);nextCall:SetFrameLevel(handle:GetFrameLevel()+2)
 local pulse=0
 alert:SetScript("OnUpdate",function(_,dt)
  pulse=pulse+dt;local wave=(math.sin(pulse*3)+1)/2
  icon:SetAlpha(0.7+0.3*wave);glow:SetAlpha(0.35+0.65*wave);glow:SetSize(58+18*wave,58+18*wave)
  alert:SetBackdropBorderColor(1,0.30+wave*0.25,0.08,1)
 end)
 local function pending()
  local list={}
  for _,r in ipairs(activeCalls())do if r.caller==N.Me()or N.Army.NeedsAnswer(r)then list[#list+1]=r end end
  return list
 end
 local function alarm(calls)
  for _,r in ipairs(calls)do
   if not seen[r.id]then
    seen[r.id]=true
    if r.caller~=N.Me()and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound,SOUNDKIT.RAID_WARNING,"Master")end
   end
  end
 end
 function N.UpdateArmyAlert()
  N.RestoreUIPositions()
  hud:SetShown(N.db~=nil)
  local calls=preview and{preview}or pending();alarm(calls)
  alert:SetShown(#calls>0)
  if #calls==0 then showingCall=nil;return end
  if requestIndex>#calls then requestIndex=1 elseif requestIndex<1 then requestIndex=#calls end
  showingCall=calls[requestIndex];local r=showingCall
  local own=not preview and r.caller==N.Me()
  counter:SetText(#calls>1 and requestIndex.." of "..#calls or"");prev:SetShown(#calls>1);nextCall:SetShown(#calls>1)
  local member=preview and preview.member or N.members[r.caller]
  local level=member and tonumber(member.level)
  who:SetText(own and"Your call for help is active"or("|cff"..N.ClassColor(member)..short(r).."|r needs help!"..(level and"  |cffb0b0b0level "..level.."|r"or"")))
  local now=GetServerTime and GetServerTime()or time()
  local minutes=math.max(0,math.floor((now-(tonumber(r.created)or now))/60))
  where:SetText(plain(r.zone).."  |cffffd100"..coords(r).."|r  \194\183  "..(minutes<1 and"called just now"or"called "..minutes.." min ago"))
  local canCancel=not preview and N.Army.CanCancel and N.Army.CanCancel(r)
  if own then
   coming:Hide();busy:Hide();place(map,16,150);place(stop,172,150);stop:SetText("Cancel Request")
   footer:SetText("Stays active until you, an officer or the GM cancels it.")
  else
   place(coming,16,148);place(busy,168,104);place(map,276,88)
   stop:SetText(preview and"Close"or"Cancel");if preview or canCancel then place(stop,368,58)else stop:Hide()end
   footer:SetText(preview and"Preview only: nothing is sent to the guild."or"On my way posts an automatic guild chat message and marks "..short(r).." on your map for 30 min.")
  end
 end
 function N.ShowArmyPreview()
  local mapID,zone,x,y
  pcall(function()
   mapID=C_Map.GetBestMapForUnit("player");zone=C_Map.GetMapInfo(mapID).name
   local pos=C_Map.GetPlayerMapPosition(mapID,"player");if pos.GetXY then x,y=pos:GetXY()else x,y=pos.x,pos.y end
  end)
  local now=GetServerTime and GetServerTime()or time()
  preview={id="preview",caller="Thrall",zone=zone or"Durotar",mapID=mapID or 1411,x=finite(x)and x or 0.5,y=finite(y)and y or 0.5,created=now-120,member={classFile="SHAMAN",class="Shaman",level=60}}
  requestIndex=1;seen.preview=nil;N.UpdateArmyAlert()
 end
end
N.Army.OnRequestsChanged=function()N.UpdateArmyAlert();if window:IsShown()and N.Render then N.Render()end end
local alertDriver=CreateFrame("Frame");local alertTick=0
alertDriver:SetScript("OnUpdate",function(_,dt)alertTick=alertTick+dt;if alertTick>=0.5 then alertTick=0;N.UpdateArmyAlert()end end)
local orders=CreateFrame("Frame",nil,body,"BackdropTemplate");orders:SetWidth(contentWidth);orders:Hide()
orders:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=4,right=4,top=4,bottom=4}})
orders:SetBackdropColor(0.16,0.055,0.025,0.98);orders:SetBackdropBorderColor(0.62,0.45,0.24,1)
local ordersHeader=orders:CreateTexture(nil,"BACKGROUND");ordersHeader:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock");ordersHeader:SetVertexColor(0.42,0.13,0.095,0.85);ordersHeader:SetPoint("TOPLEFT",5,-5);ordersHeader:SetSize(297,98)
local banner=orders:CreateTexture(nil,"ARTWORK");banner:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\WarHall\\WarBanner.tga");banner:SetSize(48,96);banner:SetPoint("TOP",0,-5)
local axeLeft=orders:CreateTexture(nil,"ARTWORK");axeLeft:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\WarHall\\LeftAxe.tga");axeLeft:SetSize(48,96);axeLeft:SetPoint("TOPLEFT",71,-5)
local axeRight=orders:CreateTexture(nil,"ARTWORK");axeRight:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\WarHall\\RightAxe.tga");axeRight:SetSize(48,96);axeRight:SetPoint("TOPRIGHT",-71,-5)
local ordersLabel=label(orders,"GameFontNormalSmall",14,-111,279);ordersLabel:SetText("GUILD MESSAGE OF THE DAY")
local ordersText=label(orders,"GameFontHighlight",14,-130,279);N.SetFont(ordersText,10);ordersText:SetTextColor(0.90,0.85,0.72);ordersText:SetSpacing(3);ordersText:SetWordWrap(true)
local ordersMotto=label(orders,"GameFontNormalSmall",14,-220,279);ordersMotto:SetJustifyH("CENTER");ordersMotto:SetText("LOK'TAR OGAR!")
local pages={"Announcements","Army map","Guild chat","Officer chat","Roster","Dungeon finder","Requests","Guild bank","Guild polls","Discord"}
local tabIcons={"INV_Misc_Note_01","INV_Misc_Map_01","INV_Misc_GroupLooking","INV_Misc_Key_03","INV_Helmet_03","INV_Misc_GroupNeedMore","INV_Misc_Bag_10","INV_Misc_Coin_01","INV_Misc_Book_09","INV_BannerPVP_01"}
local tabs={}
for i,page in ipairs(pages) do
 local b=nativeFrame("CheckButton",nil,window,"RightSideTabTemplate",nil)
 b:SetSize(38,38); b:SetPoint("TOPLEFT",window,"TOPRIGHT",0,-43-(i-1)*46)
 local texture=b.Icon
 if not texture then
  texture=b:CreateTexture(nil,"ARTWORK"); texture:SetSize(30,30); texture:SetPoint("CENTER")
  local edge=b:CreateTexture(nil,"BACKGROUND"); edge:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
  edge:SetSize(64,64); edge:SetPoint("TOPLEFT",-3,11)
 end
 texture:SetTexture("Interface\\Icons\\"..tabIcons[i])
 texture:ClearAllPoints();texture:SetPoint("CENTER");texture:SetSize(34,34);texture:Show()
 b:SetScript("OnClick",function()selectPage(page)end)
 b:SetScript("OnEnter",function(self) tooltip(self,page) end)
 b:SetScript("OnLeave",function() GameTooltip:Hide() end)
 tabs[page]=b
end
local function layoutPage(isChat,isPoll,isRoster)
 rosterTools:SetShown(isRoster);rosterHeader:SetShown(isRoster);classStrip:SetShown(isRoster);column:SetShown(not isRoster and not isChat)
 local panelWidth=isRoster and layout.fullWidth or(isChat and layout.chatWidth or layout.panelWidth)
 local listHeight=isRoster and 228 or(isChat and layout.chatHeight or 377)
 local listY=isRoster and -130 or(isChat and -layout.chatY or -103)
 listBox:ClearAllPoints();listBox:SetPoint("TOPLEFT",isChat and layout.chatX or layout.panelX,listY);listBox:SetSize(panelWidth,listHeight)
 contentWidth=panelWidth-layout.contentInset*2-layout.scrollGap-layout.scrollbarWidth;layout.contentWidth=contentWidth
 scroll:SetSize(contentWidth,listHeight-6);body:SetWidth(contentWidth)
 if isRoster then layoutRosterColumns(contentWidth)end
 column:SetWidth(contentWidth)
 local secondWidth=isRoster and 92 or 62
 columnButtons[1]:SetWidth(contentWidth-secondWidth)
 columnButtons[2]:ClearAllPoints();columnButtons[2]:SetPoint("TOPLEFT",contentWidth-secondWidth,0);columnButtons[2]:SetWidth(secondWidth)
 columnLabels[1]:SetWidth(contentWidth-secondWidth-10);columnLabels[2]:SetWidth(secondWidth-10)
 composer:SetShown(isChat);chatEdit:SetShown(isChat);sendButton:SetShown(isChat);composerHint:SetShown(isChat);composerCount:SetShown(isChat)
 chatRail:SetShown(isChat);chatHeader:SetShown(isChat);hallMotto:SetShown(not isChat)
 if not isChat then chatLatest:Hide()end
 detailBox:SetShown(not isChat);detailScroll:SetShown(not isChat)
 detailCrest:SetShown(not isRoster)
 detailBox:ClearAllPoints();detailBox:SetPoint("TOPLEFT",isRoster and layout.panelX or layout.detailX,isRoster and -388 or -103);detailBox:SetSize(isRoster and layout.fullWidth or 272,isRoster and 92 or 377)
 detailScroll:ClearAllPoints();detailScroll:SetPoint("TOPLEFT",isRoster and layout.panelX+12 or layout.detailX+12,isRoster and -398 or -115);detailScroll:SetSize(isRoster and layout.fullWidth-24 or layout.detailWidth,isRoster and 72 or 353)
 detailBody:SetWidth(detailScroll:GetWidth());detail:SetWidth(detailScroll:GetWidth())
 local trackingAvailable=N.db and N.Tracking and type(N.Tracking.IsSharing)=="function"
 locationToggle:ClearAllPoints();locationToggle:SetPoint("TOPLEFT",568,isChat and -44 or -75)
 locationCaption:ClearAllPoints();locationCaption:SetPoint("TOPLEFT",595,isChat and -51 or -82)
 locationToggle:SetShown(not not trackingAvailable);locationCaption:SetShown(not not trackingAvailable)
 if trackingAvailable then locationToggle:SetChecked(N.Tracking.IsSharing())end
 local censusAvailable=N.page=="Army map"and N.db and N.Army and type(N.Army.IsCensusEnabled)=="function"
 censusToggle:SetShown(not not censusAvailable);censusCaption:SetShown(not not censusAvailable)
 if censusAvailable then censusToggle:SetChecked(N.Army.IsCensusEnabled())end
end
local function layoutOrders()
 orders:SetWidth(contentWidth);ordersHeader:SetWidth(contentWidth-10)
 ordersLabel:SetWidth(contentWidth-28);ordersText:SetWidth(contentWidth-28);ordersMotto:SetWidth(contentWidth-28)
 axeLeft:ClearAllPoints();axeLeft:SetPoint("TOPLEFT",math.floor((contentWidth-165)/2),-5)
 axeRight:ClearAllPoints();axeRight:SetPoint("TOPRIGHT",-math.floor((contentWidth-165)/2),-5)
end
local function measuredText(text,method,fallback)
 local ok,value=pcall(text[method],text)
 return ok and finite(value)and value>0 and value or fallback
end
local function chatBubble(y,entry,prior,channel,first)
 local member=N.members[N.Full(entry.sender)]
 local own=N.Full(entry.sender)==N.Me()
 local delta=prior and entry.stamp-prior.stamp
 local grouped=prior and prior.sender==entry.sender and delta>=0 and delta<=120
 y=y+(grouped and 3 or(first and 8 or 12))
 local display=N.ChatDisplay and N.ChatDisplay(entry)or entry.text
 local r=listRow(y,display,"",nil,nil,member and function(owner)tooltip(owner,plain(entry.sender),{N.DisplayRank(member),role(member)})end or nil,36)
 r:SetScript("OnClick",nil)
 r:SetScript("OnEnter",function(owner)
  if member then tooltip(owner,plain(entry.sender),{N.DisplayRank(member),role(member)})end
 end)
 r:SetScript("OnLeave",function()GameTooltip:Hide()end)
 if not r.chatBg then
  r.chatBg=CreateFrame("Frame",nil,r,"BackdropTemplate")
  r.chatBg:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,insets={left=3,right=3,top=3,bottom=3}})
  r.chatAvatar=r:CreateTexture(nil,"ARTWORK");r.chatAvatar:SetSize(28,28)
  r.chatSender=label(r,"GameFontNormalSmall",42,-1,400);N.SetFont(r.chatSender,10);r.chatSender:SetWordWrap(false)
  r.chatTime=label(r,"GameFontDisableSmall",0,0,40)
 end
 local maxBubble=math.max(52,math.min(math.floor(contentWidth*0.76),contentWidth-84))
 r.left:SetParent(r.chatBg);N.SetFont(r.left,12);r.left:SetSpacing(2);r.left:SetWordWrap(true);r.left:SetWidth(maxBubble-24)
 -- Measure the client-rendered text. Opaque chat handles must never be stripped,
 -- decoded or measured by their token byte length.
 r.left:SetText(display)
 local width=math.max(52,math.min(maxBubble,math.ceil(measuredText(r.left,"GetStringWidth",maxBubble-24))+24))
 r.left:SetWidth(width-24);r.left:ClearAllPoints();r.left:SetPoint("TOPLEFT",r.chatBg,"TOPLEFT",12,-8);r.left:SetTextColor(0.91,0.9,0.85)
 local bubbleHeight=math.max(30,measuredText(r.left,"GetStringHeight",18)+16)
 local top=grouped and 0 or 18
 local x=own and contentWidth-42-width or 42
 r.chatBg:ClearAllPoints();r.chatBg:SetPoint("TOPLEFT",x,-top);r.chatBg:SetSize(width,bubbleHeight)
 r.chatBg:SetBackdropColor(own and 0.14 or 0.065,own and 0.095 or 0.075,own and 0.045 or 0.095,0.96)
 r.chatBg:SetBackdropBorderColor(own and 0.48 or 0.28,own and 0.34 or 0.30,own and 0.16 or 0.35,0.85);r.chatBg:Show()
 r.chatAvatar:ClearAllPoints();r.chatAvatar:SetPoint("TOPLEFT",own and contentWidth-33 or 3,-top-1)
 r.chatAvatar:SetTexture(member and N.BadgeTexture(member)or"Interface\\Icons\\INV_Misc_GroupLooking");r.chatAvatar:SetShown(not grouped)
 local nameColor=member and N.ClassColor(member)or"CCCCCC"
 local sender=plain(entry.sender):match("^[^-]+")or plain(entry.sender)
 local metadata="|cff"..nameColor..sender.."|r  |cff8a877e"..date("%H:%M",entry.stamp).."|r"
 r.chatSender:ClearAllPoints();r.chatSender:SetPoint("TOPLEFT",own and contentWidth-42-maxBubble or 42,-1);r.chatSender:SetWidth(maxBubble)
 r.chatSender:SetJustifyH(own and"RIGHT"or"LEFT");r.chatSender:SetText(metadata);r.chatSender:SetShown(not grouped);r.chatTime:Hide();r.right:Hide()
 r.chatOwn=own;r.chatGrouped=not not grouped
 local height=top+bubbleHeight;r:SetHeight(height)
 return y+height
end
-- Kept in a block and reached through N: UI.lua is close to Lua 5.1's
-- 200-local limit and N.Render is at its 60-upvalue limit.
do
 local G=N.Groups
 local form=nativeFrame("Frame","NoDramaGroupForm",window,"BasicFrameTemplateWithInset","BackdropTemplate")
 form:SetSize(360,316);form:SetPoint("CENTER");form:SetFrameLevel(window:GetFrameLevel()+35);form:Hide()
 tinsert(UISpecialFrames,"NoDramaGroupForm")
 if form.CloseButton then form.CloseButton:SetScript("OnClick",function()form:Hide()end)end
 label(form,"GameFontNormal",12,-9,320):SetText("Post a guild group")
 local function field(caption,x,y,w,maxBytes)
  label(form,"GameFontNormalSmall",x,y,w):SetText(caption)
  local e=CreateFrame("EditBox",nil,form,"InputBoxTemplate")
  e:SetSize(w,24);e:SetPoint("TOPLEFT",x+4,y-14);e:SetAutoFocus(false);e:SetMaxBytes(maxBytes)
  e:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
  return e
 end
 label(form,"GameFontNormalSmall",18,-34,320):SetText("Dungeon")
 local pick=button(form,"",18,-50,324,function()form.menu:SetShown(not form.menu:IsShown())end)
 local info=label(form,"GameFontHighlightSmall",20,-76,320);info:SetWordWrap(true);info:SetHeight(42);info:SetTextColor(0.8,0.78,0.7)
 local minBox=field("Min level",18,-122,90,3)
 local maxBox=field("Max level",128,-122,90,3)
 local sizeBox=field("Group size",238,-122,90,2)
 label(form,"GameFontNormalSmall",18,-168,320):SetText("Your role")
 form.roleButtons={}
 function form.refreshRoles()
  local token=G.MyClass()
  for _,b in ipairs(form.roleButtons)do
   b:SetEnabled(G.CanPlay(b.role,token))
   if b.role==form.role then b:LockHighlight()else b:UnlockHighlight()end
  end
 end
 for i,r in ipairs(G.roles)do
  local b=button(form,"|cff"..r.color..r.name.."|r",18+(i-1)*110,-184,104,function()form.role=r.key;form.refreshRoles()end)
  b.role=r.key;form.roleButtons[i]=b
 end
 local noteBox=field("Note (optional)",18,-212,320,80)
 local menu=CreateFrame("Frame",nil,form,"BackdropTemplate");form.menu=menu
 local rowsPerColumn=math.ceil(#G.dungeons/2)
 menu:SetPoint("TOPLEFT",pick,"BOTTOMLEFT",0,-2);menu:SetSize(332,8+rowsPerColumn*18);menu:SetFrameLevel(form:GetFrameLevel()+10);menu:EnableMouse(true)
 menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
 menu:SetBackdropColor(0.05,0.05,0.06,0.97);menu:SetBackdropBorderColor(0.5,0.4,0.25,1);menu:Hide()
 local function choose(i)
  local d=G.dungeons[i];form.dungeon=i
  pick:SetText(d.name.."  ("..d.min..(d.min~=d.max and"-"..d.max or"")..")")
  minBox:SetText(tostring(d.min));maxBox:SetText(tostring(d.max));sizeBox:SetText(tostring(d.size or 5))
  local facts={d.zone}
  if d.bosses then facts[#facts+1]=d.bosses.." bosses"end
  if d.raid then facts[#facts+1]="|cffff9040Raid|r"end
  if d.new then facts[#facts+1]="|cff40c0ffNew in Forever|r"end
  info:SetText(table.concat(facts,"  \194\183  ")..(d.tip and"\n|cffaaaaaa"..d.tip.."|r"or""))
  menu:Hide()
 end
 for i,d in ipairs(G.dungeons)do
  local b=CreateFrame("Button",nil,menu)
  b:SetSize(162,18);b:SetPoint("TOPLEFT",4+math.floor((i-1)/rowsPerColumn)*162,-4-((i-1)%rowsPerColumn)*18)
  b:SetNormalFontObject("GameFontHighlightSmall")
  local text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");b.label=text
  text:SetPoint("LEFT",4,0);text:SetWidth(156);text:SetJustifyH("LEFT");text:SetWordWrap(false)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
  b:SetScript("OnClick",function()choose(i)end)
 end
 menu:SetScript("OnShow",function()
  -- Range colors depend on the player's current level, so refresh on open.
  for i,b in ipairs({menu:GetChildren()})do
   local d=G.dungeons[i]
   if d and b.label then b.label:SetText((d.new and"|cff40c0ff*|r "or"")..d.name.."  "..G.RangeText(d.min,d.max))end
  end
 end)
 button(form,"Post group",12,-282,164,function()
  local ok,err=G.Post(G.dungeons[form.dungeon].key,minBox:GetText(),maxBox:GetText(),sizeBox:GetText(),form.role,noteBox:GetText())
  if not ok then N.Notify(err);return end
  form:Hide();N.Notify("Group posted. Guild members in the level range who use ZERO DRAMA get a popup.");N.Render()
 end)
 button(form,"Cancel",184,-282,164,function()form:Hide()end)
 function N.OpenGroupForm()
  choose(G.DefaultDungeon());form.role=G.DefaultRole();form.refreshRoles();noteBox:SetText("");form:Show()
 end

 local function people(post,joined)
  local list={}
  for name,r in pairs(post.responses)do
   if(r.role~=nil)==joined then
    list[#list+1]=(joined and G.RoleText(r.role,true)..": "or"")..plain(G.Short(name)).."  "..tostring(r.level or"?").." "..G.ClassName(r.class)..(r.invited and"  (invited)"or"")
   end
  end
  table.sort(list)
  return #list>0 and table.concat(list,"\n")or"None yet"
 end
 local function playableRole(role)
  local token=G.MyClass()
  if role and G.CanPlay(role,token)then return role end
  return G.DefaultRole()
 end
 function N.RenderGroupsPage(y)
  columnLabels[1]:SetText("Open guild groups");columnLabels[2]:SetText("Group")
  local me=N.Me();local list=G.List();local chosen
  for _,post in ipairs(list)do if post.id==selected[N.page]then chosen=post end end
  if not chosen and list[1]then chosen=list[1];selected[N.page]=chosen.id end
  for _,post in ipairs(list)do
   local d=G.Dungeon(post.key);local yes=G.Counts(post)
   local top=gold(plain(d.name))..(d.new and"  |cff40c0ffNEW|r"or"")..(d.raid and"  |cffff9040RAID|r"or"").."   "..G.RangeText(post.min,post.max)..(post.leader==me and"   |cffffd100(yours)|r"or"")
   local bottom="|cff"..G.ClassHex(post.class)..plain(G.Short(post.leader)).."|r   "..G.RoleSummary(post).."   |cff888888"..G.Age(post).."|r"
   local tip={plain(d.zone or""),"Levels "..post.min.."-"..post.max.."  \194\183  "..(yes+1).."/"..post.size.." in group"}
   if post.note~=""then tip[#tip+1]="\""..plain(post.note).."\""end
   listRow(y,top.."\n"..bottom,(yes+1).."/"..post.size,post.id,nil,function(owner)tooltip(owner,plain(d.name),tip)end,36)
   y=y+38
  end
  if #list==0 then
   y=textBlock(gold("No open guild groups").."\n\nClick Post group to ask for a dungeon run. Guild members in the level range who use ZERO DRAMA get a popup to join as Tank, Healer or DPS.\n\nAll 28 dungeons are listed, including the nine new to WoW Forever, plus the Forever raids.")
   showDetail(gold("DUNGEON FINDER").."\n\nPost a dungeon, level range and your role. Members in range get a popup; you see who joins, in which role, and can invite them with one click.\n\nGroups close after 30 minutes or when the leader closes them. Only members online with ZERO DRAMA when you post receive the group.")
  else
   local d=G.Dungeon(chosen.key);local yes,no=G.Counts(chosen)
   local leader=N.members[chosen.leader]
   local lines={gold(plain(d.name))..(d.new and"  (new)"or"")..(d.raid and"  (raid)"or""),plain(d.zone or"")}
   if d.bosses then lines[#lines+1]=d.bosses.." bosses"end
   lines[#lines+1]="Levels "..chosen.min.."-"..chosen.max.."  \194\183  group of "..chosen.size
   lines[#lines+1]="Leader: "..plain(G.Short(chosen.leader)).." ("..G.RoleText(chosen.role,true)..(leader and leader.level and", level "..leader.level or"")..")"
   lines[#lines+1]="Posted "..G.Age(chosen)
   if chosen.note~=""then lines[#lines+1]="Note: \""..plain(chosen.note).."\""end
   if d.tip then lines[#lines+1]="Tip: "..d.tip end
   lines[#lines+1]="\n"..gold("ROLES").."\n"..G.RoleSummary(chosen,true)
   lines[#lines+1]="\n"..gold("JOINED ("..yes..")").."\n"..people(chosen,true)
   lines[#lines+1]="\n"..gold("DECLINED ("..no..")").."\n"..people(chosen,false)
   showDetail(table.concat(lines,"\n"))
  end
  action(1,"Post group",N.OpenGroupForm)
  if chosen and chosen.leader==me then
   action(2,"Invite joined",function()
    local count=G.InviteJoined(chosen.id)
    N.Notify(count>0 and"Invited "..count.." player(s)."or"Nobody new to invite.");N.Render()
   end)
   action(3,"Close group",function()G.Close(chosen.id);N.Render()end)
  elseif chosen and G.Eligible(chosen)then
   local mine=chosen.responses[me]
   G.pickedRole=playableRole(G.pickedRole or(mine and mine.role))
   local role=G.pickedRole
   local joinedAs=mine and mine.role==role
   action(2,(joinedAs and"Joined as "or"Join as ")..G.Role(role).name,function()G.Respond(chosen.id,role)end)
   action(3,"Switch role",function()
    local token=G.MyClass();local index=1
    for i,r in ipairs(G.roles)do if r.key==role then index=i end end
    for step=1,#G.roles do
     local nextRole=G.roles[(index+step-1)%#G.roles+1]
     if G.CanPlay(nextRole.key,token)then G.pickedRole=nextRole.key;break end
    end
    N.Render()
   end)
   action(4,mine and mine.role==nil and"Declined"or"Decline",function()G.Respond(chosen.id,nil)end)
  end
  return y
 end
end
do
 local R=N.Needs
 function N.ShowNeedsPage(id)
  if not window:IsShown()then N.Scope();N.RefreshRoster();window:Show()end
  if id then selected["Requests"]=id end
  selectPage("Requests")
 end
 function N.RenderNeedsPage(y)
  columnLabels[1]:SetText("Guild requests - profession mats and gold");columnLabels[2]:SetText("Left")
  local me=N.Me();local list=R.List();local chosen
  for _,req in ipairs(list)do if req.id==selected[N.page]then chosen=req end end
  if not chosen and list[1]then chosen=list[1];selected[N.page]=chosen.id end
  for _,req in ipairs(list)do
   local owner=N.members[req.owner];local done=R.Done(req)
   local top="|cff"..N.ClassColor(owner)..plain(R.Short(req.owner)).."|r   "..gold(req.kind=="gold"and"Gold"or plain(req.prof))
    ..(req.owner==me and"   |cffffd100(yours)|r"or"")..(done and"   |cff40d040covered|r"or"").."   |cff888888"..R.Age(req).."|r"
   listRow(y,top.."\n|cffbbbbbb"..plain(R.Summary(req,3)).."|r",done and"|cff40d0400|r"or R.LeftText(req),req.id,nil,nil,36)
   y=y+38
  end
  if #list==0 then
   y=textBlock(gold("No open requests").."\n\nLeveling a profession? Click New request, pick the mats you are missing, and guild members with ZERO DRAMA see them in a small guild needs window.\n\nShort on gold, for example for your first mount? Ask for gold and say what it is for.")
   showDetail(gold("GUILD REQUESTS").."\n\nPost the materials or gold you need. Guildies see them in the guild needs window, which they can move, collapse or turn off.\n\nAt a mailbox, click Guild Needs at the top of the mail window, pick a request, and the mail is filled in with the mats attached. Press Send, and the guild's list updates automatically.\n\nRequests close when their owner closes them, or after 3 days.")
  else
   local owner=N.members[chosen.owner]
   local lines={gold(chosen.kind=="gold"and"GOLD REQUEST"or string.upper(plain(chosen.prof)).." MATS"),
    "From |cff"..N.ClassColor(owner)..plain(R.Short(chosen.owner)).."|r"..(owner and owner.level and", level "..owner.level or"").."  \194\183  "..R.Age(chosen)}
   if chosen.reason~=""then lines[#lines+1]="\""..plain(chosen.reason).."\""end
   lines[#lines+1]=""
   if chosen.kind=="gold"then
    lines[#lines+1]="Needs "..gold(chosen.gold.."g").."  \194\183  "..(chosen.given or 0).."g sent so far"
   else
    for i,it in ipairs(chosen.items)do
     local left=R.Remaining(chosen,i);local have=R.Have(it.id)
     lines[#lines+1]="|T"..R.ItemIcon(it.id)..":14|t "..plain(R.ItemName(it.id)).."  "..(left>0 and left.." of "..it.count.." needed"or"|cff40d040covered|r")
      ..(have>0 and left>0 and"  |cff40d040(you have "..have..")|r"or"")
    end
   end
   if type(chosen.gifts)=="table"and #chosen.gifts>0 then
    lines[#lines+1]="\n"..gold("THANKS TO")
    for _,g in ipairs(chosen.gifts)do
     local what=g.index==0 and g.count.."g"or(chosen.items[g.index]and g.count.."x "..plain(R.ItemName(chosen.items[g.index].id))or g.count)
     lines[#lines+1]=plain(R.Short(g.from)).." - "..what
    end
   end
   showDetail(table.concat(lines,"\n"))
  end
  action(1,"New request",function()R.OpenForm("mats")end)
  if chosen and chosen.owner==me then action(2,"Close request",function()R.Close(chosen.id)end)
  elseif chosen and not R.Done(chosen)then action(2,"I sent some",function()R.OpenGive(chosen.id)end)end
  action(3,R.TrackerShown()and"Hide needs window"or"Show needs window",function()R.ToggleTracker()end)
  if chosen and chosen.owner~=me then action(4,"Fill in mail",function()R.FillMail(chosen)end)end
  return y
 end
end
function N.Render()
 N.RestoreUIPositions()
 if not window:IsShown() then return end
 restoringChatScroll=true
 used=0; block:Hide();chatLatest:Hide()
 orders:Hide()
 for _,r in ipairs(rows) do r:Hide() end
 for _,b in pairs(actions) do b:Hide() end
 N.UpdatePointsControls()
 for _,card in ipairs(pollCards)do card:Hide()end
 local officer=N.IsOfficer(N.Me()); local gm=N.IsGM()
 if not officer or N.page~="Guild polls" or not N.db then creator:Hide()end
 if N.page=="Officer chat" and not officer then N.page="Announcements" end
 local isChat=N.page=="Guild chat" or N.page=="Officer chat"
 local isPoll=N.page=="Guild polls"
 local isRoster=N.page=="Roster"
 layoutPage(isChat,isPoll,isRoster)
 if not isRoster then rosterSearch:ClearFocus()end
 if draftScope~=N.db then
  drafts={GUILD="",OFFICER=""};pollDrafts={};composerChannel=nil;chatEdit:SetText("");draftScope=N.db
  chatViews={GUILD={bottom=true,offset=0},OFFICER={bottom=true,offset=0}}
 end
 if isChat then
  local nextChannel=N.page=="Officer chat" and "OFFICER" or "GUILD"
  if composerChannel~=nextChannel then composerChannel=nextChannel; chatEdit:SetText(drafts[nextChannel]) end
  placeholder:SetText(nextChannel=="OFFICER" and "Message officers..." or "Message guild...")
  placeholder:SetShown((chatEdit:GetText() or "")=="" and not chatEdit:HasFocus())
  composerHint:SetText(nextChannel=="OFFICER" and "Enter to send  -  Officers only" or "Enter to send  -  Guild channel")
 else
  if composerChannel then drafts[composerChannel]=chatEdit:GetText() or "" end
  composerChannel=nil; chatEdit:ClearFocus(); placeholder:Hide()
 end
 for page,b in pairs(tabs) do
  b:SetShown(page~="Officer chat" or officer)
  if b.SetChecked then b:SetChecked(N.page==page) end
 end
 local count,online=0,0
 for _,m in pairs(N.members) do count=count+1; if m.online then online=online+1 end end
 local live=N.Tracking and #N.Tracking.GetPositions()or 0
 total:SetText(isChat and N.page or (isPoll and "ZERO DRAMA Voting" or(N.page=="Announcements"and"Guild Orders"or(N.page=="Roster"and"Guild Roster"or N.page))))
 sub:SetText(online.." / "..count.." online  \194\183  "..N.AddonSummary().." with addon  \194\183  "..live.." live on map  \194\183  "..plain(N.guild or "Not in a guild"))
 columnLabels[1]:SetText(N.page); columnLabels[2]:SetText("")
 showDetail(gold("ZERO DRAMA\nGUILD COMMAND").."\n\nSelect an entry to see its details.\n\n"..plain(N.Call("GetMOTD","GetGuildRosterMOTD")or"Welcome to the guild hall."))
 if not N.db then
  N.classStrip:SetText("")
  body:SetHeight(textBlock("Join a guild to open your command hall.")); scroll:UpdateScrollChildRect();restoringChatScroll=false; return
 end
 local y=0
 if N.page=="Army map" then
  local census=N.Army.Summary(); columnLabels[1]:SetText("Zone"); columnLabels[2]:SetText("Online")
  local calls=activeCalls();local chosenCall
  for _,r in ipairs(calls)do
   local call=r;local key="request:"..r.id
   local entry=listRow(y,"|T"..requestIcon..":16|t "..gold(plain(r.caller:gsub("%-.*",""))),"HELP",key,nil,function(owner)tooltip(owner,"REQUEST ARMY!",{plain(call.caller).." needs help",plain(call.zone).." ("..coords(call)..")","Active until cancelled by the requester, an officer, or the GM.","Rally point recorded at request time; layer unknown."})end,43)
   if not entry.requestInfo then entry.requestInfo=label(entry,"GameFontHighlightSmall",23,-24,279);N.SetFont(entry.requestInfo,8)end
   local answer=N.Army.Response and N.Army.Response(r)
   entry.requestInfo:SetWidth(contentWidth-26);entry.requestInfo:SetText(plain(r.zone).." ("..coords(r)..") - "..(answer=="coming"and"|cff60ff60You're on your way|r"or(answer=="busy"and"|cffb0b0b0You're busy|r"or"Until cancelled")));entry.requestInfo:Show()
   if selected[N.page]==key then chosenCall=r end;y=y+45
  end
  if #calls>0 then y=y+4 end
  local livePositions=N.Tracking and N.Tracking.GetPositions()or{};local chosenLive
  if #livePositions>0 then
   listRow(y,gold("LIVE GUILD POSITIONS"),tostring(#livePositions));y=y+24
   for _,record in ipairs(livePositions)do
    local position=record;local member=N.members[position.name];local key="live:"..position.name
    local display=(member and roleBadge(member)or"").."|cff"..N.ClassColor(member)..plain(position.name:match("^[^-]+")or position.name).."|r"
    local entry=listRow(y,display,math.floor(position.age or 0).."s",key,nil,function(owner)
     tooltip(owner,plain(position.name),{liveLine(position),"Latest coordinates shared by this member's addon.","Different layers and phases are not verified."})
    end,43)
    if not entry.requestInfo then entry.requestInfo=label(entry,"GameFontHighlightSmall",23,-24,279);N.SetFont(entry.requestInfo,9)end
    entry.requestInfo:SetWidth(contentWidth-26);entry.requestInfo:SetText(liveLine(position));entry.requestInfo:Show()
    if selected[N.page]==key then chosenLive=position end;y=y+45
   end
   y=y+6
  end
  listRow(y,gold("GUILD ZONE CENSUS"),"");y=y+24
  local chosen
  for _,z in ipairs(census.zones) do
   local zone=z
   listRow(y,plain(z.name),"|cff40e040"..z.count.."|r",z.name,nil,function(owner) N.Army.Tooltip(owner,zone) end)
   if selected[N.page]==z.name then chosen=z end
   y=y+20
  end
  if #census.zones==0 and #livePositions==0 and #calls==0 then y=textBlock("Waiting for online members in the guild roster.\n\nMembers with ZERO DRAMA 0.12 or newer can share their live outdoor position.") end
  if chosenCall then
   showDetail(gold("REQUEST ARMY! - "..plain(chosenCall.caller)).."\n"..plain(chosenCall.zone).." ("..coords(chosenCall)..")\nRally point active until an authorized cancellation.\nLayer is unknown.")
  elseif chosenLive then
   showDetail(gold("LIVE GUILD MEMBER").."\n\n"..plain(chosenLive.name).."\n"..liveLine(chosenLive).."\n\nThese are the member's latest shared coordinates.\n\nMoving members update about every 5 seconds. Old positions expire after 30 seconds.\n\nMembers can stop sharing with the checkbox above. Layer and phase are not verified.")
  elseif chosen then
   showDetail(gold(plain(chosen.name).." \194\183 "..chosen.count.." members").."\n"..plain(table.concat(chosen.members,", "))..(not chosen.mapID and "\nMap unavailable for this zone." or ""))
  else
   local breakdown=continentSummary(census) or census.unknown.." location unknown \194\183 "..census.offline.." offline."
   showDetail(gold("WHERE THE ARMY STANDS").."\n\n"..#livePositions.." fresh shared positions\n"..census.online.." online in "..#census.zones.." zones.\n"..breakdown.."\n\n"..gold("LIVE MAP MARKERS").."\nClass-colored markers follow members with this addon. Updates arrive about every 5 seconds while moving; stale markers disappear after 30 seconds.\n\nBoth Blizzard's map and OpenMap are supported.\n\n"..gold("REGION PLAYER COUNTS").."\nMap count markers start off. Turn them on with the checkbox below. Counts use the full roster and do not verify exact positions or a shared layer.")
  end
  action(1,chosenCall and"Show Map"or(chosenLive and"Locate member"or(chosen and chosen.mapID and "View Zone" or "World Map")),function()
   if chosenLive and not chosenCall and N.LiveMap then N.LiveMap.ShowMember(chosenLive.name)
   elseif chosenCall then N.Army.Open(chosenCall.mapID,chosenCall.x,chosenCall.y)
   else N.Army.Open(chosen and chosen.mapID or nil)end
  end)
  if chosenCall and N.Army.CanCancel and N.Army.CanCancel(chosenCall)then action(2,"Cancel Request",function()askCancel(chosenCall)end)
  else action(2,N.db.showGuildMap==false and "Show Pins" or "Hide Pins",function() N.db.showGuildMap=N.db.showGuildMap==false; N.Army.Draw(); N.Render() end)end
  if chosenCall and chosenCall.caller~=N.Me()then
   action(3,"I'm on my way",function()N.Army.Respond(chosenCall.id,"coming")end)
   action(4,"I'm busy",function()N.Army.Respond(chosenCall.id,"busy")end)
  else action(3,"Refresh",function() N.Call("GuildRoster","GuildRoster"); N.Notify("Roster refresh requested.") end)end
 elseif N.page=="Roster" then
  columnLabels[1]:SetText("Member"); columnLabels[2]:SetText("Rank")
  local query=(rosterSearch:GetText()or""):lower():gsub("^%s+",""):gsub("%s+$","")
  local members={};for _,m in pairs(N.members)do
   local searchable=table.concat({m.name,m.class or"",m.zone or"",m.rank or"",N.DisplayRank(m),role(m),(N.AddonStatus(m)),select(3,N.AddonStatus(m))==4 and"no addon"or""}," "):lower()
   if (not onlineOnly:GetChecked()or m.online)and(query==""or searchable:find(query,1,true))then members[#members+1]=m end
  end
  local classCounts,classOrder={},{}
  for _,m in ipairs(members)do
   local key=m.classFile or m.class or"?"
   if not classCounts[key]then classCounts[key]={name=plain(m.class or"Unknown"),count=0,color=N.ClassColor(m)};classOrder[#classOrder+1]=classCounts[key]end
   classCounts[key].count=classCounts[key].count+1
  end
  table.sort(classOrder,function(a,b)if a.count==b.count then return a.name<b.name end;return a.count>b.count end)
  local classParts={}
  for _,c in ipairs(classOrder)do classParts[#classParts+1]="|cff"..c.color..c.name.."|r "..c.count end
  N.classStrip:SetText(gold(#classOrder.." classes ("..#members.." members):").."  "..(#classParts>0 and table.concat(classParts,"  \194\183  ")or"None"))
  table.sort(members,function(a,b)
   local av,bv
   if rosterSort=="rank"then av,bv=a.index or 99,b.index or 99
   elseif rosterSort=="level"then av,bv=a.level or 0,b.level or 0
   elseif rosterSort=="status"then av,bv=N.MemberStatus(a),N.MemberStatus(b)
   elseif rosterSort=="addon"then av,bv=select(3,N.AddonStatus(a)),select(3,N.AddonStatus(b))
   elseif rosterSort=="points"then av,bv=-N.Points.SortValue(a),-N.Points.SortValue(b)
   else av,bv=tostring(a[rosterSort]or""):lower(),tostring(b[rosterSort]or""):lower()end
   if av==bv then return a.name<b.name end
   if rosterDescending then return av>bv end;return av<bv
  end)
  local kept=false;for _,m in ipairs(members)do if m.name==selected[N.page]then kept=true end end
  if not kept and members[1]then selected[N.page]=members[1].name end
  local selectedMember
  for _,m in ipairs(members) do
   local member=m; local w=N.db.warnings[m.name]; local hasWarning=w and w.reason~=""
   if m.name==selected[N.page]then selectedMember=m end
   local classColor=m.online and N.ClassColor(m)or"888888"
   local display=roleBadge(m).."|cff"..classColor..plain(m.name:match("^[^-]+") or m.name).."|r"
   if hasWarning then display=display.." |TInterface\\AddOns\\NO_DRAMA\\Media\\YellowCard.tga:11:7|t" end
   local r=listRow(y,display,plain(N.DisplayRank(m)),m.name,nil,function(owner)
    local lines={plain(N.DisplayRank(m))..(role(m)~="" and " \194\183 "..role(m) or ""),"Guild rank: "..plain(m.rank),"Level "..tostring(m.level or"?").." "..plain(m.class),"Status: "..N.MemberStatus(m),"Addon: "..(N.AddonStatus(m))..(select(3,N.AddonStatus(m))==4 and" (versions before 0.16 can't reply)"or""),m.online and "Area: "..plain(m.zone~=""and m.zone or"Unknown")or"Last seen: "..N.LastSeen(m)}
    lines[#lines+1]="Points: "..N.Points.Display(m)
    if m.note and m.note~=""then lines[#lines+1]="Public note: "..plain(m.note)end
    if N.CanViewOfficerNotes()and m.officerNote and m.officerNote~=""then lines[#lines+1]="Officer note: "..plain(m.officerNote)end
    if hasWarning then lines[#lines+1]="Yellow card: "..w.reason; lines[#lines+1]="Issued by "..w.by end
    local position=livePosition(member.name);if position then lines[#lines+1]="Live position: "..liveLine(position)end
    tooltip(owner,plain(member.name),lines)
   end,25)
   r.left:Hide();r.right:Hide()
   if not r.memberColumns then
    r.memberColumns={}
    for i=1,#rosterColumns do local cell=label(r,"GameFontHighlightSmall",0,-6,50);N.SetFont(cell,10);cell:SetWordWrap(false);r.memberColumns[i]=cell end
    r.rowShade=r:CreateTexture(nil,"BACKGROUND",nil,-3);r.rowShade:SetTexture("Interface\\Buttons\\WHITE8X8");r.rowShade:SetAllPoints()
   end
   r.rowShade:SetVertexColor(0.19,0.16,0.12,used%2==0 and 0.38 or 0.15);r.rowShade:Show()
   local state=N.MemberStatus(m);local where=m.online and plain(m.zone and m.zone~=""and m.zone or"Unknown area")or N.LastSeen(m)
   local tracking=N.Tracking and N.Tracking.GetStatus(m.name)or"No signal"
   local values={display,tostring(m.level or"?"),"|cff"..classColor..plain(m.class).."|r",plain(m.rank or N.DisplayRank(m)),N.Points.Display(m),where,(tracking=="Live"and"|cff80d8b0Live"or(m.online and"|cff80ac69"..state or"|cff777777Offline")).."|r"}
   local addonText,addonHex=N.AddonStatus(m);values[#values+1]="|cff"..addonHex..addonText.."|r"
   for i,col in ipairs(rosterColumns)do local cell=r.memberColumns[i];cell:ClearAllPoints();cell:SetPoint("TOPLEFT",col.x+4,-6);cell:SetWidth(math.max(1,col.width-8));cell:SetText(values[i]);cell:Show()end
   y=y+25
  end
  local m=selectedMember or members[1];if m then selected[N.page]=m.name end
  if m then
   local lines={roleBadge(m)..gold(plain(m.name)),"Level "..tostring(m.level or"?").." "..plain(m.class).." - "..plain(N.DisplayRank(m))..(role(m)~=""and" ("..role(m)..")"or""),"Status: "..N.MemberStatus(m).."   Addon: "..(N.AddonStatus(m))..(select(3,N.AddonStatus(m))==4 and" (no reply - versions before 0.16 can't reply)"or""),m.online and"Area: "..plain(m.zone and m.zone~=""and m.zone or"Unknown")or"Last seen: "..N.LastSeen(m),"Public note: "..plain(m.note and m.note~=""and m.note or"None")}
   if N.CanViewOfficerNotes()and m.officerNote and m.officerNote~=""then lines[#lines+1]="|cffe0ad74Officer note: "..plain(m.officerNote).."|r"end
   lines[#lines+1]=N.Points.DetailText(m)
   local warning=N.db.warnings[m.name];if warning and warning.reason~=""then lines[#lines+1]="|cffffd100Yellow card: "..plain(warning.reason).."|r"end
   local tracking,age;if N.Tracking then tracking,age=N.Tracking.GetStatus(m.name)end
   if tracking then lines[#lines+1]="Location sharing: "..tracking..(age and" ("..math.floor(age).."s ago)"or"")end
   local position=livePosition(m.name);if position then lines[#lines+1]="Live position: "..liveLine(position)end
   showDetail(table.concat(lines,"\n"));N.UpdatePointsControls(m)
   if tracking=="Live"and N.LiveMap then action(4,"Show on map",function()N.LiveMap.ShowMember(m.name)end)end
   local me=N.members[N.Me()]
   if officer and me and me.index<m.index then
    action(1,"Yellow Card",function()
     ask("Warning: "..plain(m.name),"Enter a reason. Blank clears the warning. Shared with online addon users.",{ "" },function(reason) return N.Warn(m.name,reason) end)
    end)
    if N.CanRemove(m.name) then action(2,"Red Card",function()
     ask("Remove "..plain(m.name).."?","This kicks the player from the guild. Type REMOVE to confirm.",{ "" },function(s)
      if s~="REMOVE" or not N.CanRemove(m.name) then return false end
      if C_GuildInfo and C_GuildInfo.RemoveFromGuild and m.guid then C_GuildInfo.RemoveFromGuild(m.guid)
      elseif C_GuildInfo and C_GuildInfo.Uninvite then C_GuildInfo.Uninvite(m.name)
      elseif GuildUninvite then GuildUninvite(m.name) else return false end
      N.Notify("Removal requested; the guild roster will confirm the result."); return true
     end)
    end) end
   end
   if gm and m.index~=0 then action(3,"Role Badge",function()
    ask("Role badge","Vice-GM, Officer HR, Officer Raid Tactics; blank clears. Cosmetic only.",{role(m)},function(s) return N.SetRole(m.name,s) end)
   end) end
  else y=textBlock("No members match your search.");showDetail("Search by member name, class, area, rank or role.\nUncheck Online to include offline members.")end
 elseif N.page=="Announcements" then
  columnLabels[1]:SetText("Guild orders")
  layoutOrders()
  orders:SetPoint("TOPLEFT",0,0);ordersText:SetText(plain(N.Call("GetMOTD","GetGuildRosterMOTD")or"No announcement posted."))
  local textHeight=math.max(32,ordersText:GetStringHeight()or 32);ordersMotto:ClearAllPoints();ordersMotto:SetPoint("TOPLEFT",14,-146-textHeight)
  y=170+textHeight;orders:SetHeight(y);orders:Show()
  showDetail(gold("THE GUILD CHARTER").."\n"..plain(N.Call("GetInfoText","GetGuildInfoText") or "No guild information available."))
  if N.CanEditMOTD() then action(1,"Edit MOTD",function()
   ask("Guild announcement","Updates the guild's official message of the day.",{N.Call("GetMOTD","GetGuildRosterMOTD") or ""},function(s)
    return N.UpdateMOTD(s)
   end)
  end) end
 elseif N.page=="Guild chat" or N.page=="Officer chat" then
  local channel=N.page=="Officer chat" and "OFFICER" or "GUILD"
  local log=N.chat and N.chat[channel] or {}
  chatTitle:SetText(channel=="OFFICER"and"Officer Council"or plain(N.guild or"ZERO DRAMA").." - Guild chat")
  chatSubtitle:SetText(channel=="OFFICER"and"Private guild officer channel"or online.." members online  -  Guild channel")
  chatNotice:SetText(plain(N.Call("GetMOTD","GetGuildRosterMOTD")or"Welcome to ZERO DRAMA."))
  for page,b in pairs(chatRooms)do
   b:SetShown(page~="Officer chat"or officer)
   local active=N.page==page;b:SetBackdropColor(active and 0.23 or 0.055,active and 0.14 or 0.055,active and 0.045 or 0.06,0.9)
   b:SetBackdropBorderColor(active and 0.65 or 0.19,active and 0.46 or 0.18,active and 0.18 or 0.16,0.85)
  end
  local view=chatViews[channel]
  -- Building a bubble per stored line made the first open stall; draw the
  -- newest lines and page older ones in on request.
  local limit=view.limit or 100
  local first=math.max(1,#log-limit+1)
  if first>1 then
   listRow(y,gold("Show older messages ("..(first-1)..")"),"",nil,function()view.limit=limit+100;view.bottom=false;view.offset=0 end)
   y=y+24
  end
  for i=first,#log do
   y=chatBubble(y,log[i],i>first and log[i-1]or nil,channel,i==first)
  end
  if #log==0 then y=textBlock("Your next conversation starts here.\n\nType a message below. Ordinary history is saved on this character.")end
  y=y+10
  body:SetHeight(math.max(scroll:GetHeight(),y)); scroll:UpdateScrollChildRect()
  local range=scroll:GetVerticalScrollRange()or 0
  scroll:SetVerticalScroll(view.bottom and range or math.min(view.offset,range));view.offset=scroll:GetVerticalScroll()or 0
  chatLatest:SetShown(not view.bottom and range-view.offset>=24)
 elseif N.page=="Dungeon finder" then
  y=N.RenderGroupsPage(y)
 elseif N.page=="Requests" then
  y=N.RenderNeedsPage(y)
 elseif N.page=="Guild bank" then
  columnLabels[1]:SetText("Guild bank records"); y=textBlock(N.Bank())
  showDetail("Availability depends on your realm and guild permissions.\nVisit the guild bank to load accessible records.")
 elseif N.page=="Guild polls" then
  columnLabels[1]:SetText("Guild polls - in-game only")
  local active,all;y,active,all=renderPollCards(officer);sub:SetText(active.." active - "..all.." polls - votes received locally")
  showDetail(gold("GUILD BALLOT BOX").."\n\nSelect one or more answers, then submit your vote. You may update or withdraw your ballot.\n\nSeveral polls can run at once. Officers create and close polls.\n\nTotals show votes received by this character; members who were offline may have incomplete results.\n\nThese are in-game guild polls, separate from Discord polls.")
 else
  columnLabels[1]:SetText("ZERO DRAMA Discord")
  y=textBlock(gold("discord.gg/3zQVrNWTm").."\n\nCommunity integration is not connected.\n\nDiscord polls and votes are not synchronized.")
  showDetail("Use Discord for Discord polls.\nA shared poll service needs a separate integration.")
  action(1,"Copy Invite",function() ask("Guild Discord","Select the address and copy it; open it in your browser.",{ "https://discord.gg/3zQVrNWTm" },function() return true end) end)
 end
 body:SetHeight(math.max(scroll:GetHeight(),y)); scroll:UpdateScrollChildRect()
 N.UpdateArmyAlert()
 restoringChatScroll=false
end
SLASH_NODRAMA1="/nd"; SLASH_NODRAMA2="/nodrama"; SLASH_NODRAMA3="/zd"; SLASH_NODRAMA4="/zerodrama"
SlashCmdList.NODRAMA=function(msg)
 if (msg or""):lower():match("^%s*testpopup%s*$")and N.Groups then N.Groups.Test();return end
 if (msg or""):lower():match("^%s*testarmy%s*$")and N.ShowArmyPreview then N.ShowArmyPreview();return end
 if (msg or""):lower():match("^%s*needs%s*$")and N.Needs then N.Needs.ToggleTracker();N.Notify("Guild needs window "..(N.Needs.TrackerShown()and"on."or"off."));return end
 if window:IsShown() then window:Hide()
 else N.Scope(); N.RefreshRoster(); N.Call("GuildRoster","GuildRoster"); window:Show(); N.Render() end
end
SLASH_NODRAMARESET1="/ndreset"
SlashCmdList.NODRAMARESET=N.ResetUIPositions

-- Standalone circular launcher; no minimap-button library is required.
if Minimap then
 local launcher=CreateFrame("Button","NoDramaMinimapButton",Minimap)
 launcher:SetSize(32,32);launcher:SetFrameStrata("MEDIUM");launcher:SetFrameLevel(Minimap:GetFrameLevel()+8)
 local icon=launcher:CreateTexture(nil,"ARTWORK");icon:SetSize(21,21);icon:SetPoint("CENTER",0,0)
 icon:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga")
 icon:SetTexCoord(0.15,0.85,0.08,0.78)
 if launcher.CreateMaskTexture and icon.AddMaskTexture then
  local mask=launcher:CreateMaskTexture(nil,"ARTWORK")
  if mask then mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");mask:SetAllPoints(icon);icon:AddMaskTexture(mask) end
 end
 local rim=launcher:CreateTexture(nil,"OVERLAY");rim:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");rim:SetSize(54,54);rim:SetPoint("TOPLEFT",0,0)
 launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
 local angle=180;local dragging=false;local dragged=false
 local function place()
  local radius=Minimap:GetWidth()/2+5;local radians=math.rad(angle)
  launcher:ClearAllPoints();launcher:SetPoint("CENTER",Minimap,"CENTER",math.cos(radians)*radius,math.sin(radians)*radius)
 end
 local function restore()
  local store=positionStore();if store and finite(store.minimapAngle)then angle=store.minimapAngle%360 end
  place()
 end
 launcher:RegisterForDrag("LeftButton")
 launcher:SetScript("OnDragStart",function(self)
  dragging=true;dragged=true
  self:SetScript("OnUpdate",function()
   local x,y=GetCursorPosition();local cx,cy=Minimap:GetCenter();local scale=Minimap:GetEffectiveScale()
   angle=math.deg(math.atan2(y/scale-cy,x/scale-cx));place()
  end)
 end)
 launcher:SetScript("OnDragStop",function(self)
  dragging=false;self:SetScript("OnUpdate",nil);local store=positionStore();if store then store.minimapAngle=angle%360 end
 end)
 launcher:SetScript("OnMouseDown",function()if not dragging then dragged=false end end)
 launcher:SetScript("OnClick",function()if not dragged then SlashCmdList.NODRAMA()end;dragged=false end)
 launcher:SetScript("OnEnter",function(self)tooltip(self,"ZERO DRAMA",{"Click to open or close Guild Hall.","Drag to move around the minimap."})end)
 launcher:SetScript("OnLeave",function()GameTooltip:Hide()end)
 launcher:SetScript("OnShow",restore)
 local events=CreateFrame("Frame");events:RegisterEvent("PLAYER_LOGIN");events:SetScript("OnEvent",restore)
 restore();N.minimapButton=launcher
end
