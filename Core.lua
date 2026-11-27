local _, N = ...
NoDrama = N
N.prefix, N.members, N.queue = "NODRAMA1", {}, {}
N.ranks = {
 {"High Marshal", "Warchief", "GM"},
 {"Field Marshal", "HighOverlord", "Vice-GM"},
 {"Marshal", "BloodGuard", "Officer HR"},
 {"Commander", "WarStrategist", "Officer Raid Tactics"},
 {"Captain", "Champion"}, {"Lieutenant", "Legionnaire"},
 {"Sergeant", "StoneGuard"}, {"Corporal", "Grunt"},
 {"Scout", "Scout"}, {"Recruit", "Initiate"},
}
function N.DisplayRank(m)
 local rank=N.ranks[math.min((m.index or 9)+1,#N.ranks)]
 return rank and rank[1] or m.rank
end
function N.BadgeKey(m)
 if m.index==0 then return "Warchief" end
 local roles={["Vice-GM"]="HighOverlord",["Officer HR"]="BloodGuard",["Officer Raid Tactics"]="WarStrategist"}
 local role=N.db and N.db.roles[m.name]
 if roles[role] then return roles[role] end
 local rank=N.ranks[math.min((m.index or 9)+1,#N.ranks)]
 return rank and rank[2] or "Initiate"
end
function N.BadgeTexture(m) return "Interface\\AddOns\\NO_DRAMA\\Media\\Badges\\"..N.BadgeKey(m)..".tga" end
function N.Call(name, legacy, ...)
 local fn = C_GuildInfo and C_GuildInfo[name] or _G[legacy or name]
 if fn then return fn(...) end
end
function N.CanEditMOTD()
 -- Blizzard's guild information UI uses the global CanEditMOTD permission API.
 if type(CanEditMOTD)~="function" then return false end
 local ok,allowed=pcall(CanEditMOTD)
 return ok and allowed==true
end
function N.UpdateMOTD(text)
 if not N.CanEditMOTD() or type(text)~="string" then return false end
 text=N.Safe(text)
 if text=="" or #text>255 then return false end
 local fn=C_GuildInfo and C_GuildInfo.SetMOTD or GuildSetMOTD
 if type(fn)~="function" then return false end
 return pcall(fn,text)
end
function N.Safe(s) return tostring(s or ""):gsub("|", ""):gsub("[%c]", " ") end
-- Byte limits must not split a multi-byte UTF-8 letter (Cyrillic is 2 bytes), or it draws as a box.
function N.Clip(s,limit)
 s=tostring(s or"");if #s<=limit then return s end
 s=s:sub(1,limit)
 local i=#s;while i>0 and s:byte(i)>=128 and s:byte(i)<192 do i=i-1 end
 local lead=i>0 and s:byte(i)
 if lead and lead>=192 then
  local need=lead>=240 and 4 or(lead>=224 and 3 or 2)
  if #s-i+1<need then s=s:sub(1,i-1)end
 end
 return s
end
-- Blizzard K strings are opaque, client-rendered handles, not durable text.
-- Keep complete handles only in this Lua session; SavedVariables receive a
-- neutral marker. General/protocol sanitization above intentionally stays strict.
local protectedChatText="[Protected message text is not saved]"
local protectedChatSender="[Protected sender]"
local chatDisplays=setmetatable({},{__mode="k"})
local checkedChatHistories=setmetatable({},{__mode="k"})
local chatDisplayScope
local function secretChatValue(value)
 if type(issecretvalue)~="function" then return false end
 local ok,secret=pcall(issecretvalue,value)
 return not ok or secret==true
end
local function receivedChatText(value)
 -- A true secret value must not enter tostring, comparisons or string parsing.
 if secretChatValue(value)then return protectedChatText,true,false end
 if type(value)~="string"then return nil end
 local parts={};local cursor,plainStart=1,1;local protected=false
 while true do
  local pipe=value:find("|",cursor,true);if not pipe then break end
  local code=value:sub(pipe+1,pipe+1)
  if code=="|"then
   -- An escaped literal pipe does not start a native K span.
   cursor=pipe+2
  elseif code=="K"then
   local first,last=value:find("|K[^|%c]+|k",pipe)
   if first==pipe then
    parts[#parts+1]=N.Safe(value:sub(plainStart,pipe-1))
    parts[#parts+1]=value:sub(pipe,last)
    protected=true;cursor=last+1;plainStart=cursor
   else cursor=pipe+1 end
  else cursor=pipe+1 end
 end
 parts[#parts+1]=N.Safe(value:sub(plainStart))
 return table.concat(parts),protected,protected
end
local function permittedChatLineText(lineID)
 -- The normal chat-line API may expose ordinary text outside messaging
 -- lockdown. It may also return another opaque handle: never decode one.
 if secretChatValue(lineID)or type(lineID)~="number"then return end
 if lineID~=lineID or lineID<=0 or lineID==math.huge or lineID~=math.floor(lineID)then return end
 if not C_ChatInfo or type(C_ChatInfo.InChatMessagingLockdown)~="function"or type(C_ChatInfo.GetChatLineText)~="function"then return end
 local ok,locked=pcall(C_ChatInfo.InChatMessagingLockdown)
 if not ok or secretChatValue(locked)or locked~=false then return end
 local read,value=pcall(C_ChatInfo.GetChatLineText,lineID)
 if not read or secretChatValue(value)or type(value)~="string"or value==""then return end
 local text,protected=receivedChatText(value)
 if not protected and text~=""then return text end
end
local function checkStoredChat(history)
 if type(history)~="table"or checkedChatHistories[history]then return end
 checkedChatHistories[history]=true
 for _,entry in ipairs(history)do
  if type(entry)=="table"then
   local _,protected=receivedChatText(entry.text)
   if protected then entry.text=protectedChatText end
   local _,protectedSender=receivedChatText(entry.sender)
   if protectedSender then entry.sender=protectedChatSender end
  end
 end
end
function N.ChatDisplay(entry)
 if type(entry)~="table"then return ""end
 local display=chatDisplays[entry];if display then return display end
 if secretChatValue(entry.text)then return protectedChatText end
 return type(entry.text)=="string"and entry.text or ""
end
function N.Full(name)
 if not name then return "" end
 if name:find("-", 1, true) then return name end
 return name .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub("%s", ""))
end
function N.CharacterKey() return N.Full(UnitName("player")) end
function N.Me()
 -- Forever can return a display surname in the roster but a short UnitName.
 -- Only an exact character GUID match may resolve that identity for permissions.
 local guid=UnitGUID and UnitGUID("player")
 if guid then
  for name,member in pairs(N.members)do if member.guid==guid then return name end end
 end
 return N.CharacterKey()
end
function N.CanViewOfficerNotes()
 local fn=C_GuildInfo and C_GuildInfo.CanViewOfficerNote or CanViewOfficerNote
 local ok,allowed=false,false
 if type(fn)=="function" then ok,allowed=pcall(fn) end
 allowed=ok and allowed==true
 -- Permission changes must also evict old in-memory officer notes.
 if not allowed then for _,member in pairs(N.members or {})do member.officerNote=nil end end
 return allowed
end
function N.MemberStatus(m)
 if not m or not m.online then return "Offline" end
 if m.status==1 then return "Away" elseif m.status==2 then return "Busy" end
 return "Online"
end
do
 local getMeta=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
 N.VERSION=getMeta and getMeta("NO_DRAMA","Version")or"?"
end
N.addonSeen,N.addonReplied={},{}
local function versionParts(v)
 local a,b,c=tostring(v or""):match("^(%d+)%.(%d+)%.(%d+)")
 return tonumber(a)or 0,tonumber(b)or 0,tonumber(c)or 0
end
function N.CompareVersion(x,y)
 local a1,b1,c1=versionParts(x);local a2,b2,c2=versionParts(y)
 if a1~=a2 then return a1<a2 and -1 or 1 end
 if b1~=b2 then return b1<b2 and -1 or 1 end
 if c1~=c2 then return c1<c2 and -1 or 1 end
 return 0
end
function N.MarkAddon(name,version)
 if not N.db then return end
 N.db.addon=N.db.addon or {}
 local known=N.addonSeen[name]
 if version then N.addonSeen[name]=version elseif not known then N.addonSeen[name]="old" end
 N.db.addon[name]={v=N.addonSeen[name]~="old"and N.addonSeen[name]or(N.db.addon[name]and N.db.addon[name].v)or"old",stamp=time()}
end
function N.SendHello(ask)
 if not N.db or not IsInGuild() then return false end
 N.MarkAddon(N.Me(),N.VERSION)
 if ask then N.helloSent=GetTime() end
 return N.Send("VH",N.VERSION,ask and "1" or "0")
end
-- Returns display text, hex color and a sort weight (lower = better).
function N.AddonStatus(m)
 if not m then return "Unknown","777777",5 end
 local v=N.addonSeen[m.name]
 if m.name==N.Me()then v=N.VERSION end
 if v=="old" then return "Outdated","ff9933",2 end
 if v then
  if N.CompareVersion(v,N.VERSION)<0 then return "v"..v.." (old)","ff9933",2 end
  return "v"..v,"40d040",1
 end
 local saved=N.db and N.db.addon and N.db.addon[m.name]
 if m.online then
  if not N.helloSent or GetTime()-N.helloSent<15 then return "Checking...","9d9d9d",3 end
  -- Versions before 0.16 can't answer the version check, so silence is not proof of no addon.
  if saved then return "Old version?","ff9933",2 end
  return "Not detected","ff5040",4
 end
 if saved then return saved.v=="old"and"Had addon"or"Had v"..saved.v,"9d9d9d",3 end
 return "Not seen","777777",5
end
function N.AddonSummary()
 local online,with,outdated=0,0,0
 for _,m in pairs(N.members)do if m.online then
  online=online+1
  local _,_,weight=N.AddonStatus(m)
  if weight<=2 then with=with+1 end
  if weight==2 then outdated=outdated+1 end
 end end
 return with,online,outdated
end
function N.LastSeen(m)
 if m and m.online then return "Online now" end
 local last=m and m.lastOnline
 if type(last)~="table" then return "Last seen unavailable" end
 for _,unit in ipairs({"years","months","days","hours"})do
  local n=last[unit]
  if type(n)=="number" and n>0 then
   n=math.floor(n);return n.." "..(n==1 and unit:sub(1,-2) or unit).." ago"
  end
 end
 return "Less than an hour ago"
end
function N.ClassColor(m)
 local file=m and (m.classFile or (type(m.class)=="string" and m.class:upper():gsub("%s","")))
 local color=RAID_CLASS_COLORS and file and RAID_CLASS_COLORS[file]
 if type(color)=="table" then
  if type(color.r)=="number" and type(color.g)=="number" and type(color.b)=="number" then
   local function byte(v)if v~=v then return 204 end;return math.floor(math.max(0,math.min(1,v))*255+0.5)end
   return string.format("%02X%02X%02X",byte(color.r),byte(color.g),byte(color.b))
  elseif type(color.colorStr)=="string" then
   local hex=color.colorStr:match("(%x%x%x%x%x%x)$");if hex then return hex:upper()end
  end
 end
 return "CCCCCC"
end
function N.RefreshRoster()
 local canReadOfficerNote=N.CanViewOfficerNotes()
 N.members = {}
 if not GetNumGuildMembers or not GetGuildRosterInfo then return end
 for i=1, GetNumGuildMembers() do
  local name, rank, index, level, class, zone, note, officerNote, online, status, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
  if name then
   local member={name=N.Full(name),rank=rank,index=index,level=level,class=class,zone=zone,online=online==true,status=status,classFile=classFile,guid=guid,note=N.Safe(note)}
   if canReadOfficerNote then member.officerNote=N.Safe(officerNote) end
   if not member.online and type(GetGuildRosterLastOnline)=="function" then
    local ok,years,months,days,hours=pcall(GetGuildRosterLastOnline,i)
    local values={years,months,days,hours};local any=false;local valid=ok
    for n=1,4 do local value=values[n];if value~=nil then
     if type(value)~="number" or value~=value or value<0 or value==math.huge then valid=false else any=true end
    end end
    if valid and any then member.lastOnline={years=years or 0,months=months or 0,days=days or 0,hours=hours or 0} end
   end
   N.members[member.name]=member
  end
 end
end
function N.IsOfficer(name)
 local m = N.members[N.Full(name)]
 if not m then return false end
 if m.index == 0 then return true end
 -- Permissions, never cosmetic rank names, establish authority. Fail closed.
 if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
  local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, m.index + 1)
  return ok and type(flags)=="table" and flags[3] and flags[4] or false
 end
 return false
end
function N.IsGM() local m=N.members[N.Me()]; return m and m.index==0 end
function N.CanRemove(target)
 local me, other = N.members[N.Me()], N.members[N.Full(target)]
 return N.IsOfficer(N.Me()) and me and other and me.index < other.index and CanGuildRemove and CanGuildRemove()
end
function N.Scope()
 local guild = GetGuildInfo("player")
 if not guild then
  N.db=nil; N.pollPending={}; N.pollScope=nil
  chatDisplays=setmetatable({},{__mode="k"});chatDisplayScope=nil
  return
 end
 local key = (GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()) .. ":" .. guild
 NoDramaDB = NoDramaDB or {guilds={}}
 NoDramaDB.guilds = NoDramaDB.guilds or {}
 NoDramaDB.guilds[key] = NoDramaDB.guilds[key] or {warnings={}, roles={}, chats={}, polls={}}
 N.db=NoDramaDB.guilds[key]
 if N.pollScope~=key then N.pollPending={}; N.pollScope=key end
 local me=N.CharacterKey()
 N.db.chats[me]=N.db.chats[me] or {GUILD={}, OFFICER={}}
 N.chat=N.db.chats[me]
 if chatDisplayScope~=N.chat then chatDisplays=setmetatable({},{__mode="k"});chatDisplayScope=N.chat end
 checkStoredChat(N.chat.GUILD);checkStoredChat(N.chat.OFFICER)
 N.guild=guild
end
function N.Pack(...)
 local out={...}
 for i,v in ipairs(out) do out[i]=tostring(v):gsub("%%","%%25"):gsub("\t","%%09"):gsub("\n","%%0A") end
 return table.concat(out,"\t")
end
function N.Unpack(msg)
 local t={}
 for v in (msg.."\t"):gmatch("(.-)\t") do t[#t+1]=v:gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end) end
 return t
end
function N.Send(...)
 local msg=N.Pack(...)
 if #msg>240 or #N.queue>=100 then return false end
 N.queue[#N.queue+1]=msg
 return true
end
function N.Notify(text) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd4af68ZERO DRAMA:|r "..text) end end
function N.Warn(target, reason)
 target=N.Full(target); reason=N.Clip(N.Safe(reason),100)
 if not N.db or not N.IsOfficer(N.Me()) or not N.members[target] then return false end
 local me,other=N.members[N.Me()],N.members[target]
 if me.index>=other.index then return false end
 local stamp=time()
 if not N.Send("W",target,reason,stamp) then return false end
 N.db.warnings[target]={reason=reason, by=N.Me(), stamp=stamp}
 return true
end
function N.SetRole(target, role)
 if not N.db or not N.IsGM() or not N.members[N.Full(target)] then return false end
 if role~="" and role~="Vice-GM" and role~="Officer HR" and role~="Officer Raid Tactics" then return false end
 N.db.roles[N.Full(target)]=role
 N.Send("R",N.Full(target),role)
 return true
end
local function pollText(value,limit)
 if type(value)~="string" then return nil end
 value=N.Safe(value):gsub("^%s+",""):gsub("%s+$","")
 if value=="" or #value>limit then return nil end
 return value
end
local function pollOptions(options)
 if type(options)~="table" or #options<2 or #options>10 then return nil end
 local out,seen={},{}
 for key in pairs(options) do if type(key)~="number" or key%1~=0 or key<1 or key>#options then return nil end end
 for i=1,#options do
  local text=pollText(options[i],60)
  if not text or seen[text:lower()] then return nil end
  seen[text:lower()]=true; out[i]=text
 end
 return out
end
local function ballot(p,choices)
 -- Numeric ballots are saved by versions before 0.5; normalize without discarding them.
 if type(choices)=="number" then choices={choices} end
 if type(choices)~="table" or type(p.options)~="table" then return nil end
 local out,seen={},{}
 for key in pairs(choices) do if type(key)~="number" or key%1~=0 or key<1 or key>#choices then return nil end end
 for i=1,#choices do
  local n=choices[i]
  if type(n)~="number" or n%1~=0 or n<1 or n>#p.options or seen[n] then return nil end
  seen[n]=true; out[#out+1]=n
 end
 if p.allowMultiple~=true and #out>1 then return nil end
 table.sort(out); return out
end
function N.PollBallot(p,name)
 return p and p.votes and ballot(p,p.votes[name]) or {}
end
function N.PollCounts(p)
 local counts={}; for i=1,#p.options do counts[i]=0 end
 local voters,selections=0,0
 for _,choices in pairs(p.votes or {}) do
  local valid=ballot(p,choices)
  if valid and #valid>0 then
   voters=voters+1
   for _,n in ipairs(valid) do counts[n]=counts[n]+1; selections=selections+1 end
  end
 end
 return counts,voters,selections
end
local function pollBatch(messages)
 if #N.queue+#messages>100 then return false end
 for _,msg in ipairs(messages) do if type(msg)~="string" or #msg>240 then return false end end
 for _,msg in ipairs(messages) do N.queue[#N.queue+1]=msg end
 return true
end
function N.CreatePoll(question,options,allowMultiple)
 if not N.db or not N.IsOfficer(N.Me()) then return false end
 -- Keep callers of the old two-string API working, as a single-choice poll.
 if type(options)=="string" and type(allowMultiple)=="string" then options,allowMultiple={options,allowMultiple},false end
 question=pollText(question,120); options=pollOptions(options)
 if not question or not options or (allowMultiple~=nil and type(allowMultiple)~="boolean") then return false end
 if allowMultiple==nil then allowMultiple=true end
 local id
 repeat
  N.pollSequence=(N.pollSequence or 0)+1
  id=N.Me()..":"..time()..":"..N.pollSequence
 until not N.db.polls[id] and not (N.pollPending and N.pollPending[id])
 if #id>120 then return false end
 local messages={N.Pack("P2",id,question,allowMultiple and "1" or "0",#options)}
 for i,text in ipairs(options) do messages[#messages+1]=N.Pack("O2",id,i,text) end
 if not pollBatch(messages) then return false end
 N.db.polls[id]={id=id,question=question,options=options,allowMultiple=allowMultiple,votes={},by=N.Me(),protocol=2}
 return id
end
function N.Vote(id,choices)
 local p=N.db and N.db.polls[id]
 if not p or p.closed or not N.members[N.Me()] then return false end
 local valid=ballot(p,choices)
 if not valid then return false end
 if p.protocol==2 then
  if not N.Send("V2",id,table.concat(valid,",")) then return false end
 else
  -- Do not send a lossy multi-select ballot to a legacy poll.
  if #valid~=1 or not N.Send("V",id,valid[1]) then return false end
 end
 p.votes[N.Me()]=#valid>0 and valid or nil
 return true
end
function N.ClosePoll(id)
 local p=N.db and N.db.polls[id]
 if not p or p.closed or not N.IsOfficer(N.Me()) then return false end
 if not N.Send(p.protocol==2 and "C2" or "C",id) then return false end
 p.closed=true; return true
end
local function ownedPollID(id,sender)
 if type(id)~="string" or #id>120 or id:sub(1,#sender+1)~=sender..":" then return false end
 return id:sub(#sender+2):match("^%d+:%d+$")~=nil
end
local function pendingPoll(id,owner)
 N.pollPending=N.pollPending or {}
 local total,owned=0,0; local now=time()
 for key,p in pairs(N.pollPending) do
  if now-p.stamp>120 then N.pollPending[key]=nil
  else total=total+1; if p.owner==owner then owned=owned+1 end end
 end
 local existing=N.pollPending[id]
 if existing then return existing.owner==owner and existing or nil end
 if total>=32 or owned>=8 then return nil end
 local p={owner=owner,stamp=now,options={}}; N.pollPending[id]=p; return p
end
local function publishPoll(id,p)
 if not p.question or not p.count then return end
 for i=1,p.count do if not p.options[i] then return end end
 for i in pairs(p.options) do if i>p.count then return end end
 local options=pollOptions(p.options)
 if not options or N.db.polls[id] then return end
 N.db.polls[id]={id=id,question=p.question,options=options,allowMultiple=p.allowMultiple,votes={},by=p.owner,protocol=2,closed=p.closed or nil}
 N.pollPending[id]=nil
end
local function receivePoll(op,p,sender)
 if op=="V2" and #p==3 then
  local poll=N.db.polls[p[2]]
  if not poll or poll.protocol~=2 or poll.closed or #p[3]>40 then return end
  local choices={}
  if p[3]~="" then
   if not p[3]:match("^%d[%d,]*%d$") and not p[3]:match("^%d$") then return end
   for token in (p[3]..","):gmatch("(.-),") do
    if token=="" or not token:match("^%d+$") then return end
    choices[#choices+1]=tonumber(token)
   end
  end
  local valid=ballot(poll,choices)
  if valid then poll.votes[sender]=#valid>0 and valid or nil end
 elseif op=="P2" and #p==5 and N.IsOfficer(sender) and ownedPollID(p[2],sender) then
  if N.db.polls[p[2]] then return end
  local question=pollText(p[3],120); local count=tonumber(p[5])
  if not question or (p[4]~="1" and p[4]~="0") or not count or count%1~=0 or count<2 or count>10 then return end
  local pending=pendingPoll(p[2],sender); if not pending then return end
  if pending.question and (pending.question~=question or pending.count~=count or pending.allowMultiple~=(p[4]=="1")) then return end
  pending.question=question; pending.count=count; pending.allowMultiple=p[4]=="1"; publishPoll(p[2],pending)
 elseif op=="O2" and #p==4 and N.IsOfficer(sender) and ownedPollID(p[2],sender) then
  if N.db.polls[p[2]] then return end
  local index=tonumber(p[3]); local option=pollText(p[4],60)
  if not index or index%1~=0 or index<1 or index>10 or not option then return end
  local pending=pendingPoll(p[2],sender); if not pending then return end
  if pending.count and index>pending.count then return end
  if pending.options[index] and pending.options[index]~=option then return end
  pending.options[index]=option; publishPoll(p[2],pending)
 elseif op=="C2" and #p==2 and N.IsOfficer(sender) then
  local poll=N.db.polls[p[2]]
  if poll then if poll.protocol==2 then poll.closed=true end; return end
  local owner=type(p[2])=="string" and p[2]:match("^(.-):%d+:%d+$")
  if owner and N.members[owner] and ownedPollID(p[2],owner) then
   local pending=pendingPoll(p[2],owner); if pending then pending.closed=true end
  end
 end
end
function N.Receive(prefix,msg,channel,sender)
 if prefix~=N.prefix or channel~="GUILD" or not N.db or type(msg)~="string" or #msg>240 then return end
 sender=N.Full(sender)
 if not N.members[sender] then return end
 local p=N.Unpack(msg); local op=p[1]
 if op=="VH" then
  if sender==N.Me() then return end
  local v=type(p[2])=="string" and p[2]:match("^%d+%.%d+%.%d+[%w%.%-]*$")
  N.MarkAddon(sender,v and v:sub(1,20) or nil)
  -- Throttled so a member stuck in a /reload loop can't make the whole guild spam replies.
  if p[3]=="1" and (not N.addonReplied[sender] or GetTime()-N.addonReplied[sender]>30) then
   N.addonReplied[sender]=GetTime();N.SendHello(false)
  end
  if N.Render then N.Render() end
  return
 end
 if sender~=N.Me() then N.MarkAddon(sender) end
 if op=="L1"or op=="L0"then
  if N.Tracking then N.Tracking.Receive(op,p,sender)end
  return -- Position heartbeats do not rebuild the chat window.
 end
 if op=="H1"or op=="HC"or op=="HS"then if N.Army and N.Army.ReceiveRequest then N.Army.ReceiveRequest(op,p,sender)end
 elseif op=="D1"or op=="DJ"or op=="DX"then if N.Groups then N.Groups.Receive(op,p,sender)end
 elseif op=="N1"or op=="N2"or op=="N3"or op=="NX"or op=="NG"or op=="NQ"then if N.Needs then N.Needs.Receive(op,p,sender)end
 elseif op=="S1"or op=="SS"or op=="SQ"then if N.Points then N.Points.Receive(op,p,sender)end
 elseif op=="B1"or op=="B2"or op=="B3"or op=="BQ"then if N.BankData then N.BankData.Receive(op,p,sender)end
 elseif op=="P2" or op=="O2" or op=="V2" or op=="C2" then receivePoll(op,p,sender)
 elseif op=="V" and #p==3 then
  local poll=N.db.polls[p[2]]; local choice=tonumber(p[3])
  if poll and poll.protocol~=2 and not poll.closed and (choice==1 or choice==2) then poll.votes[sender]={choice} end
 elseif op=="P" and N.IsOfficer(sender) and #p==5 and p[2]:sub(1,#sender+1)==sender..":" then
  if not N.db.polls[p[2]] then N.db.polls[p[2]]={id=p[2],question=N.Safe(p[3]),options={N.Safe(p[4]),N.Safe(p[5])},allowMultiple=false,votes={},by=sender,protocol=1} end
 elseif op=="C" and #p==2 and N.IsOfficer(sender) and N.db.polls[p[2]] and N.db.polls[p[2]].protocol~=2 then N.db.polls[p[2]].closed=true
 elseif op=="W" and N.IsOfficer(sender) and #p==4 then
  local target=N.Full(p[2]); local m=N.members[target]; local stamp=tonumber(p[4]); local old=N.db.warnings[target]
  if m and N.members[sender].index<m.index and stamp and stamp<=time()+60 and (not old or stamp>=old.stamp) then
   N.db.warnings[target]={reason=N.Clip(N.Safe(p[3]),100),by=sender,stamp=stamp}
  end
 elseif op=="R" and N.members[sender].index==0 and N.members[N.Full(p[2])] then
  local role=p[3]
  if role=="" or role=="Vice-GM" or role=="Officer HR" or role=="Officer Raid Tactics" then N.db.roles[N.Full(p[2])]=role end
 end
 if N.Render then N.Render() end
end
function N.ChatEvent(channel,message,sender,...)
 if secretChatValue(channel)or type(channel)~="string"or(channel~="GUILD"and channel~="OFFICER")then return false end
 if not N.db or not N.chat then return false end
 if channel=="OFFICER" and not N.IsOfficer(N.Me()) then return false end
 local text,protected,runtime=receivedChatText(message)
 local senderText,protectedSender=receivedChatText(sender)
 if not text or not senderText then return false end
 if runtime and select("#",...)>=9 then
  -- message/sender are event arguments 1/2; lineID is event argument 11.
  local lineText=permittedChatLineText(select(9,...))
  if lineText then text,protected,runtime=lineText,false,false end
 end
 local log=N.chat[channel];if type(log)~="table"then return false end
 local entry={text=protected and protectedChatText or text,sender=protectedSender and protectedChatSender or senderText,stamp=time()}
 log[#log+1]=entry
 if runtime then chatDisplays[entry]=text end
 while #log>500 do table.remove(log,1) end
 if N.Render then N.Render() end
 return true
end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_GUILD_UPDATE","GUILD_ROSTER_UPDATE","GUILD_MOTD","CHAT_MSG_GUILD","CHAT_MSG_OFFICER","CHAT_MSG_ADDON"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,...)
 if event=="ADDON_LOADED" then
  if (...)~="NO_DRAMA" then return end
  NoDramaDB=NoDramaDB or {guilds={}}
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(N.prefix) end
 elseif event=="PLAYER_LOGOUT"then
  if N.Tracking then N.Tracking.OnLogout()end
  N.queue={};return
 elseif event=="PLAYER_LOGIN" or event=="PLAYER_GUILD_UPDATE" then
  N.queue={}; N.Scope(); N.Call("GuildRoster","GuildRoster"); N.RefreshRoster()
  if event=="PLAYER_LOGIN" then N.addonSeen,N.helloSent,N.helloAt={},nil,GetTime()+8
  elseif not N.helloSent and not N.helloAt then N.helloAt=GetTime()+8 end
  if event=="PLAYER_LOGIN"and N.Tracking and N.Tracking.OnLogin then N.Tracking.OnLogin()end
 elseif event=="GUILD_ROSTER_UPDATE" then
  N.Scope(); N.RefreshRoster()
  if N.chat and N.members[N.Me()] and not N.IsOfficer(N.Me()) then N.chat.OFFICER={} end
 elseif event=="CHAT_MSG_GUILD" then N.ChatEvent("GUILD",...)
 elseif event=="CHAT_MSG_OFFICER" then N.ChatEvent("OFFICER",...)
 elseif event=="CHAT_MSG_ADDON" then N.Receive(...);return
 end
 if N.Tracking then N.Tracking.OnScopeChanged()end
 if N.Render then N.Render() end
end)
local elapsed,uiElapsed=0,0
events:SetScript("OnUpdate",function(_,dt)
 if N.Tracking then N.Tracking.OnUpdate(dt)end
 if N.LiveMap then N.LiveMap.OnUpdate(dt)end
 uiElapsed=uiElapsed+dt
 if uiElapsed>=2 then
  uiElapsed=0
  if N.window and N.window:IsShown()and(N.page=="Roster"or N.page=="Army map")and N.Render then N.Render()end
 end
 if N.helloAt and GetTime()>=N.helloAt and N.db and IsInGuild() then N.helloAt=nil;N.SendHello(true) end
 elapsed=elapsed+dt; if elapsed<0.35 then return end; elapsed=0
 if #N.queue>0 and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(N.prefix,table.remove(N.queue,1),"GUILD") end
end)
