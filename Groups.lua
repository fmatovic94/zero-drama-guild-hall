local _,N=...
-- Guild-only dungeon finder. Posts and answers travel on the addon's guild
-- channel, so only members running ZERO DRAMA receive the join popup.
local G={posts={}};N.Groups=G
local EXPIRY=30*60
local POPUP_SECONDS=120
-- Ranges for the Forever dungeons are Blizzard's announced bands (Oct 20, 2026);
-- the Group Finder lets players queue a little outside them.
G.dungeons={
 {key="RFC",name="Ragefire Chasm",min=13,max=18,zone="Orgrimmar",bosses=4},
 {key="HOT",name="Hall of Thanes",min=13,max=18,zone="Beneath Ironforge, Dun Morogh",bosses=4,new=true,tip="Alliance side: Horde must travel into Ironforge."},
 {key="ROL",name="Ruins of Lordaeron",min=15,max=20,zone="Above the Undercity, Tirisfal Glades",bosses=7,new=true,tip="Horde side: Alliance must travel to Tirisfal."},
 {key="WC",name="Wailing Caverns",min=17,max=24,zone="The Barrens",bosses=8},
 {key="DM",name="The Deadmines",min=17,max=26,zone="Westfall",bosses=8},
 {key="SFK",name="Shadowfang Keep",min=22,max=30,zone="Silverpine Forest",bosses=8},
 {key="BFD",name="Blackfathom Deeps",min=24,max=32,zone="Ashenvale",bosses=7},
 {key="STOCKS",name="The Stockade",min=24,max=32,zone="Stormwind City",bosses=5},
 {key="EXCAV",name="Excavation Site",min=24,max=29,zone="Wetlands",bosses=4,new=true,tip="Titan constructs above Whelgar's Excavation."},
 {key="DALA",name="City of Dalaran",min=28,max=33,zone="Alterac Mountains",bosses=9,new=true,tip="Needs the faction attunement quest chain; enter through the sewers."},
 {key="SMGY",name="SM Graveyard",min=28,max=38,zone="Scarlet Monastery, Tirisfal Glades"},
 {key="GNOMER",name="Gnomeregan",min=29,max=38,zone="Dun Morogh",bosses=5},
 {key="RFK",name="Razorfen Kraul",min=29,max=38,zone="The Barrens",bosses=6},
 {key="SMLIB",name="SM Library",min=29,max=39,zone="Scarlet Monastery, Tirisfal Glades"},
 {key="SMARM",name="SM Armory",min=32,max=42,zone="Scarlet Monastery, Tirisfal Glades"},
 {key="DROWN",name="The Drowned City",min=35,max=40,zone="Off Stranglethorn Vale, west of Grom'gol",bosses=6,new=true,tip="Underwater entrance: dive to find it."},
 {key="SMCATH",name="SM Cathedral",min=35,max=45,zone="Scarlet Monastery, Tirisfal Glades"},
 {key="RFD",name="Razorfen Downs",min=37,max=46,zone="The Barrens",bosses=6},
 {key="KROL",name="Krol'dok Stronghold",min=40,max=45,zone="The Riverglades",bosses=5,new=true,tip="Outdoor ogre fortress."},
 {key="ULDA",name="Uldaman",min=41,max=51,zone="Badlands",bosses=8},
 {key="ZF",name="Zul'Farrak",min=42,max=54,zone="Tanaris",bosses=8},
 {key="MARA",name="Maraudon",min=46,max=55,zone="Desolace",bosses=8},
 {key="ALCAZ",name="Alcaz Prison",min=48,max=53,zone="Alcaz Island, Dustwallow Marsh",bosses=5,new=true,tip="Defias and naga inside the island prison."},
 {key="ST",name="Sunken Temple",min=50,max=60,zone="Swamp of Sorrows",bosses=8},
 {key="BRD",name="Blackrock Depths",min=52,max=60,zone="Blackrock Mountain",bosses=21},
 {key="DIREM",name="Dire Maul",min=55,max=60,zone="Feralas",bosses=19},
 {key="LBRS",name="Lower Blackrock Spire",min=55,max=60,zone="Blackrock Mountain"},
 {key="UBRS",name="Upper Blackrock Spire",min=55,max=60,size=10,zone="Blackrock Mountain"},
 {key="BLACKMAW",name="Blackmaw Hold",min=55,max=60,zone="Azshara",bosses=7,new=true,tip="Several routes; tunnels lead on to the Barrow Deeps raid."},
 {key="STRAT",name="Stratholme",min=58,max=60,zone="Eastern Plaguelands",bosses=19},
 {key="SCHOLO",name="Scholomance",min=58,max=60,zone="Western Plaguelands",bosses=14},
 {key="SHAPER",name="Shaper's Terrace",min=58,max=60,zone="Northern hills, Un'Goro Crater",bosses=11,new=true,tip="Power the consoles with Un'Goro crystals."},
 {key="BARROW",name="Barrow Deeps",min=60,max=60,size=10,zone="Through Blackmaw Hold, Azshara",raid=true,new=true,tip="10-player raid. Raids open December 9, 2026."},
 {key="HYJAL",name="Hyjal Summit",min=60,max=60,size=20,zone="Mount Hyjal",raid=true,new=true,tip="20-player raid. Raids open December 9, 2026."},
 {key="ONY",name="Onyxia's Lair",min=60,max=60,size=40,zone="Dustwallow Marsh",raid=true,tip="40-player raid. Raids open December 9, 2026."},
 {key="OTHER",name="Other (see note)",min=1,max=60,zone="Described in the note"},
}
local byKey={};for _,d in ipairs(G.dungeons)do byKey[d.key]=d end
function G.Dungeon(key)return byKey[key]end

G.roles={
 {key="T",name="Tank",color="5fa8ff",classes={WARRIOR=true,PALADIN=true,DRUID=true}},
 {key="H",name="Healer",color="5fdf6f",classes={PRIEST=true,PALADIN=true,DRUID=true,SHAMAN=true}},
 {key="D",name="DPS",color="ff7070"},
}
local roleByKey={};for _,r in ipairs(G.roles)do roleByKey[r.key]=r end
function G.Role(key)return roleByKey[key]end
function G.CanPlay(roleKey,classToken)
 local r=roleByKey[roleKey]
 return r~=nil and(not r.classes or classToken==nil or r.classes[classToken]==true)
end
function G.RoleText(key,plainText)
 local r=roleByKey[key];if not r then return""end
 return plainText and r.name or"|cff"..r.color..r.name.."|r"
end

local function levelCap()
 local cap=GetMaxPlayerLevel and GetMaxPlayerLevel()
 return type(cap)=="number"and cap>0 and cap or 60
end
local function myLevel()return UnitLevel("player")or 0 end
local function myClass()local _,token=UnitClass("player");return token end
G.MyClass=myClass
local function short(name)return(name or""):match("^[^-]+")or name or""end
G.Short=short
function G.ClassName(token)
 return token and(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]or token:sub(1,1)..token:sub(2):lower())or""
end
function G.ClassHex(token)
 local c=token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
 if c then return c.colorStr and c.colorStr:match("(%x%x%x%x%x%x)$")or string.format("%02x%02x%02x",math.floor(c.r*255+0.5),math.floor(c.g*255+0.5),math.floor(c.b*255+0.5))end
 return"cccccc"
end
function G.Eligible(post)local level=myLevel();return level>=post.min and level<=post.max end
-- Red when the player is too low, green inside the range, grey when above it.
function G.RangeText(minLevel,maxLevel)
 local level=myLevel()
 local color=level<minLevel and"ff5040"or(level>maxLevel and"9d9d9d"or"40d040")
 return"|cff"..color..(minLevel==maxLevel and tostring(minLevel)or minLevel.."-"..maxLevel).."|r"
end
function G.DefaultDungeon()
 local level=myLevel();local best
 for i,d in ipairs(G.dungeons)do
  if not d.raid and d.key~="OTHER"and level>=d.min and level<=d.max then best=best or i;if d.new then return i end end
 end
 return best or #G.dungeons
end
function G.DefaultRole()
 local token=myClass()
 return token=="PRIEST"and"H"or(token=="WARRIOR"and"T"or"D")
end
function G.List()
 local now=time();local list={}
 for id,post in pairs(G.posts)do
  if now-post.stamp>EXPIRY then G.posts[id]=nil elseif not post.test then list[#list+1]=post end
 end
 table.sort(list,function(a,b)return a.stamp>b.stamp end)
 return list
end
function G.Counts(post)
 local yes,no=0,0
 for _,r in pairs(post.responses)do if r.role then yes=yes+1 else no=no+1 end end
 return yes,no
end
-- Counts include the leader. Wanted numbers only exist for 5-player groups.
function G.RoleCounts(post)
 local counts={T=0,H=0,D=0}
 if roleByKey[post.role]then counts[post.role]=counts[post.role]+1 end
 for _,r in pairs(post.responses)do if r.role then counts[r.role]=counts[r.role]+1 end end
 local wanted=post.size==5 and{T=1,H=1,D=3}or nil
 return counts,wanted
end
function G.RoleSummary(post,plainText)
 local counts,wanted=G.RoleCounts(post);local parts={}
 for _,r in ipairs(G.roles)do
  parts[#parts+1]=G.RoleText(r.key,plainText).." "..counts[r.key]..(wanted and"/"..wanted[r.key]or"")
 end
 return table.concat(parts,"  ")
end
function G.Age(post)
 local minutes=math.floor((time()-post.stamp)/60)
 return minutes<1 and"just now"or minutes.." min ago"
end

local queue={}
local popup=CreateFrame("Frame","NoDramaGroupPopup",UIParent,"BackdropTemplate")
popup:SetSize(380,206);popup:SetPoint("TOP",0,-120);popup:SetFrameStrata("DIALOG");popup:SetClampedToScreen(true);popup:Hide()
popup:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",tile=true,tileSize=32,edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
popup:EnableMouse(true);popup:SetMovable(true);popup:RegisterForDrag("LeftButton")
popup:SetScript("OnDragStart",popup.StartMoving);popup:SetScript("OnDragStop",popup.StopMovingOrSizing)
local crest=popup:CreateTexture(nil,"ARTWORK");crest:SetTexture("Interface\\AddOns\\NO_DRAMA\\Media\\Logo.tga");crest:SetTexCoord(0.15,0.85,0.08,0.78);crest:SetSize(44,44);crest:SetPoint("TOPLEFT",16,-16)
local function text(font,x,y,w,justify)
 local t=popup:CreateFontString(nil,"OVERLAY",font);t:SetPoint("TOPLEFT",x,y);t:SetWidth(w);t:SetJustifyH(justify or"LEFT");t:SetWordWrap(true)
 return t
end
local heading=text("GameFontDisableSmall",68,-16,290);heading:SetText("GUILD GROUP  \194\183  ZERO DRAMA")
local title=text("GameFontNormalLarge",68,-30,290)
local where=text("GameFontHighlightSmall",68,-50,290)
local facts=text("GameFontHighlightSmall",18,-72,344)
local noteText=text("GameFontHighlightSmall",18,-112,344)
local timer=CreateFrame("StatusBar",nil,popup);timer:SetPoint("TOPLEFT",18,-140);timer:SetSize(344,6)
timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");timer:SetStatusBarColor(0.85,0.65,0.2);timer:SetMinMaxValues(0,POPUP_SECONDS)
local timerBg=timer:CreateTexture(nil,"BACKGROUND");timerBg:SetAllPoints();timerBg:SetColorTexture(0,0,0,0.5)
local roleButtons={}
for i,r in ipairs(G.roles)do
 local b=CreateFrame("Button",nil,popup,"UIPanelButtonTemplate");b:SetSize(80,24);b:SetText("Join: "..r.name);b.role=r.key
 roleButtons[i]=b
end
local decline=CreateFrame("Button",nil,popup,"UIPanelButtonTemplate");decline:SetSize(80,24);decline:SetText("Decline")
local function layoutButtons()
 local shown={};local token=myClass()
 for _,b in ipairs(roleButtons)do
  local playable=G.CanPlay(b.role,token);b:SetShown(playable)
  if playable then shown[#shown+1]=b end
 end
 shown[#shown+1]=decline
 local width=math.min(110,math.floor((344-(#shown-1)*6)/#shown))
 local x=(380-(#shown*width+(#shown-1)*6))/2
 for _,b in ipairs(shown)do b:SetWidth(width);b:ClearAllPoints();b:SetPoint("BOTTOMLEFT",x,16);x=x+width+6 end
end
local function chime()
 local sound=SOUNDKIT and SOUNDKIT.READY_CHECK or 8960
 pcall(PlaySound,sound,"Master")
end
local function showNext()
 while queue[1]and not G.posts[queue[1]]do table.remove(queue,1)end
 local id=queue[1]
 if not id then popup.id=nil;popup:Hide();return end
 local post=G.posts[id];local d=byKey[post.key];local yes=G.Counts(post)
 popup.id=id;popup.shownAt=GetTime()
 title:SetText(N.Safe(d.name)..(d.new and"  |cff40c0ffNEW|r"or""))
 where:SetText((d.raid and"Raid  \194\183  "or"")..N.Safe(d.zone or"")..(d.bosses and"  \194\183  "..d.bosses.." bosses"or""))
 local leader="|cff"..G.ClassHex(post.class)..N.Safe(short(post.leader)).."|r"
 facts:SetText(leader.." wants a group  \194\183  Levels "..G.RangeText(post.min,post.max).."  \194\183  "..(yes+1).."/"..post.size.."\n"..G.RoleSummary(post))
 local extra={}
 if post.note~=""then extra[#extra+1]="|cffffd100\""..post.note.."\"|r"end
 if d.tip then extra[#extra+1]="|cffaaaaaa"..d.tip.."|r"end
 noteText:SetText(table.concat(extra,"\n"))
 layoutButtons()
 popup:Show()
end
function G.Prompt(post)
 for _,id in ipairs(queue)do if id==post.id then return end end
 queue[#queue+1]=post.id
 if not popup:IsShown()then showNext();chime()end
end
function G.Dismiss(id)
 for i=#queue,1,-1 do if queue[i]==id then table.remove(queue,i)end end
 if G.posts[id]and G.posts[id].test then G.posts[id]=nil end
 if popup.id==id then popup.id=nil;showNext()end
end
popup:SetScript("OnUpdate",function(self)
 if not self.id then return end
 local left=POPUP_SECONDS-(GetTime()-self.shownAt)
 timer:SetValue(math.max(0,left))
 -- An unanswered popup only closes; the group stays listed in Dungeon finder.
 if left<=0 then G.Dismiss(self.id)end
end)

-- role is a role key to join, or nil to decline.
function G.Respond(id,role)
 local post=G.posts[id];if not post or not N.db then return false end
 if role and not G.CanPlay(role,myClass())then return false end
 if post.test then
  N.Notify("Test popup: you clicked "..(role and"Join as "..G.RoleText(role)or"Decline")..". Nothing was sent to the guild.")
  G.Dismiss(id);return true
 end
 if not N.Send("DJ",id,role or"0",myLevel(),myClass()or"")then return false end
 local old=post.responses[N.Me()]
 post.responses[N.Me()]={role=role,level=myLevel(),class=myClass(),stamp=time(),invited=old and old.invited}
 G.Dismiss(id)
 if N.Render then N.Render()end
 return true
end
for _,b in ipairs(roleButtons)do b:SetScript("OnClick",function(self)if popup.id then G.Respond(popup.id,self.role)end end)end
decline:SetScript("OnClick",function()if popup.id then G.Respond(popup.id,nil)end end)

-- Local preview of the join popup; never sent to the guild.
function G.Test()
 local d=G.dungeons[G.DefaultDungeon()];local level=myLevel();local cap=levelCap()
 local id="test:"..time()
 G.posts[id]={id=id,test=true,leader="Thrall-Test",key=d.key,min=math.max(1,math.min(level,d.min)),max=math.min(cap,math.max(level,d.max)),size=d.size or 5,role="T",class="WARRIOR",
  note="Test popup - nothing is sent to the guild",stamp=time(),responses={["Jaina-Test"]={role="H",level=level,class="MAGE",stamp=time()}}}
 G.Prompt(G.posts[id])
end
function G.Close(id)
 local post=G.posts[id];if not post or post.leader~=N.Me()then return false end
 N.Send("DX",id);G.posts[id]=nil;G.Dismiss(id)
 return true
end
function G.Post(key,minLevel,maxLevel,size,role,note)
 local d=byKey[key];minLevel,maxLevel,size=tonumber(minLevel),tonumber(maxLevel),tonumber(size)
 if not N.db then return false,"Join a guild to post a group."end
 if not d or not minLevel or not maxLevel or minLevel<1 or maxLevel>levelCap()or minLevel>maxLevel then
  return false,"Choose a dungeon and a level range from 1 to "..levelCap().."."
 end
 if not size or size<2 or size>40 then return false,"Group size must be from 2 to 40."end
 if not G.CanPlay(role,myClass())then return false,"Choose a role your class can play."end
 local me=N.Me()
 for id,post in pairs(G.posts)do if post.leader==me then G.Close(id)end end
 local id=me..":"..time()
 note=N.Safe(note or""):gsub("^%s+",""):gsub("%s+$",""):sub(1,80)
 if not N.Send("D1",id,key,minLevel,maxLevel,size,role,myClass()or"",note)then return false,"The note is too long or the addon message queue is full."end
 G.posts[id]={id=id,leader=me,key=key,min=minLevel,max=maxLevel,size=size,role=role,class=myClass(),note=note,stamp=time(),responses={}}
 return true
end
function G.InviteJoined(id)
 local post=G.posts[id];if not post or post.leader~=N.Me()then return 0 end
 local invite=(C_PartyInfo and C_PartyInfo.InviteUnit)or InviteUnit
 if type(invite)~="function"then return 0 end
 local count=0
 for name,r in pairs(post.responses)do
  if r.role and not r.invited and name~=N.Me()and pcall(invite,name)then r.invited=true;count=count+1 end
 end
 return count
end

local function classToken(value)
 value=N.Safe(value)
 return value:match("^%u+$")and value or nil
end
function G.Receive(op,p,sender)
 if op=="D1"and #p==9 then
  local id,key=p[2],p[3];local minLevel,maxLevel,size=tonumber(p[4]),tonumber(p[5]),tonumber(p[6])
  if id:sub(1,#sender+1)~=sender..":"or not byKey[key]or not minLevel or not maxLevel or not size or minLevel>maxLevel then return end
  if G.posts[id]then return end
  for other,post in pairs(G.posts)do if post.leader==sender then G.posts[other]=nil;G.Dismiss(other)end end
  local post={id=id,leader=sender,key=key,min=minLevel,max=maxLevel,size=math.max(2,math.min(40,size)),role=roleByKey[p[7]]and p[7]or"D",class=classToken(p[8]),note=N.Safe(p[9]):sub(1,80),stamp=time(),responses={}}
  G.posts[id]=post
  if sender~=N.Me()and G.Eligible(post)then G.Prompt(post)end
 elseif op=="DJ"and #p==5 then
  local post=G.posts[p[2]];if not post then return end
  local role=roleByKey[p[3]]and p[3]or nil
  local old=post.responses[sender]
  post.responses[sender]={role=role,level=tonumber(p[4]),class=classToken(p[5]),stamp=time(),invited=old and old.invited}
  if post.leader==N.Me()and sender~=N.Me()then
   local yes=G.Counts(post)
   N.Notify(N.Safe(short(sender)).." "..(role and"joined as "..G.RoleText(role)or"declined").." your "..N.Safe(byKey[post.key].name).." group ("..(yes+1).."/"..post.size..").")
   if role then chime()end
  end
 elseif op=="DX"and #p==2 then
  local post=G.posts[p[2]]
  if post and post.leader==sender then G.posts[p[2]]=nil;G.Dismiss(p[2])end
 end
end
