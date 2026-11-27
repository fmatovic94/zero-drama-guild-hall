local _,N=...
-- Guild bank contents, gold and ledger. The client can only read them at a guild
-- vault, so whoever opens the bank shares a snapshot with the guild, and members
-- who log in later ask for the newest one.
local B={};N.BankData=B
local MAX_TABS=16
local LEDGER=40
local SHARE_THROTTLE=60
local QUERY_TIMEOUT=3
local unpack=unpack or table.unpack
local VERBS={deposit="deposited",withdraw="withdrew",move="moved",repair="repaired gear for",withdrawForTab="withdrew for a tab",buyTab="bought a tab for",depositSummary="deposited"}
local SPENT={withdraw=true,repair=true,withdrawForTab=true,buyTab=true}
local function clock()return GetServerTime and GetServerTime()or time()end
local function integer(v,low,high)
 v=tonumber(v);if not v or v~=v or v%1~=0 or v<low or v>high then return end
 return v
end
local function view()return N.db and type(N.db.bankView)=="table"and N.db.bankView or nil end
local function changed()
 if N.window and N.window:IsShown()and N.page=="Guild bank"and N.Render then N.Render()end
end
B.Changed=changed
function B.View()return view()end
function B.IsLive()return B.open==true end
function B.Unavailable()
 if C_GuildBank and C_GuildBank.IsGuildBankEnabled and not C_GuildBank.IsGuildBankEnabled()then return"The guild bank is not available on this realm."end
 if not GetNumGuildBankTabs or not GetGuildBankItemInfo or not GetGuildBankItemLink then return"The guild bank is not available in this client."end
end
function B.MoneyText(copper)
 copper=math.max(0,math.floor(tonumber(copper)or 0))
 if GetCoinTextureString then local ok,s=pcall(GetCoinTextureString,copper);if ok and type(s)=="string"then return s end end
 return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
end
function B.Age(stamp)
 local s=math.max(0,clock()-(stamp or clock()))
 if s<60 then return"just now"elseif s<3600 then return math.floor(s/60).." min ago"elseif s<86400 then return math.floor(s/3600).." h ago"end
 return math.floor(s/86400).." d ago"
end
function B.Count(id)
 local v=view();local n=0
 for _,tab in ipairs(v and v.tabs or{})do for _,it in ipairs(tab.items)do if it.id==id then n=n+it.count end end end
 return n
end
function B.LedgerLine(e,itemName)
 local verb=VERBS[e.kind]or e.kind
 local what=e.id==0 and B.MoneyText(e.count)or e.count.."x "..itemName(e.id)
 local sign=e.kind=="move"and"|cff6f5a3e~|r"or(SPENT[e.kind]and"|cffa02020-|r"or"|cff1f7a1f+|r")
 return sign.." "..(e.who:match("^[^-]+")or e.who).." "..verb.." "..what.."  |cff6f5a3e"..B.Age(e.at).."|r"
end

local loaded,queue,querying,queriedAt,logLoaded={},{},nil,0,false
local readAt,nextQueryAt
local function itemID(link)return type(link)=="string"and tonumber(link:match("item:(%d+)"))or nil end
local function readTab(tab)
 local items,index={},{}
 for slot=1,MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
  local link=GetGuildBankItemLink(tab,slot);local id=itemID(link)
  if id then
   local _,count,_,_,quality=GetGuildBankItemInfo(tab,slot);count=integer(count,1,1000000)or 1
   local it=index[id]
   if it then it.count=it.count+count
   else it={id=id,count=count,link=link,quality=tonumber(quality)};index[id]=it;items[#items+1]=it end
  end
 end
 return items
end
local function agoSeconds(y,m,d,h)return(((tonumber(y)or 0)*365+(tonumber(m)or 0)*30+(tonumber(d)or 0))*24+(tonumber(h)or 0))*3600 end
local function cleanName(who)return(N.Clip(N.Safe(who or"Unknown"),40):gsub("[,;:]",""))end
local function readLedger(now)
 local list={}
 local function add(at,who,kind,id,count,order)
  list[#list+1]={at=at,who=cleanName(who),kind=tostring(kind or""):match("^%a+$")or"other",id=id,count=count,order=order}
 end
 for tab=1,math.min(MAX_TABS,GetNumGuildBankTabs())do
  local _,_,viewable=GetGuildBankTabInfo(tab)
  if viewable and GetNumGuildBankTransactions then
   for i=1,GetNumGuildBankTransactions(tab)do
    local kind,who,link,count,_,_,y,m,d,h=GetGuildBankTransaction(tab,i)
    local id=itemID(link)
    if id then add(now-agoSeconds(y,m,d,h),who,kind,id,integer(count,1,1000000)or 1,i)end
   end
  end
 end
 if GetNumGuildBankMoneyTransactions then
  for i=1,GetNumGuildBankMoneyTransactions()do
   local kind,who,amount,y,m,d,h=GetGuildBankMoneyTransaction(i)
   add(now-agoSeconds(y,m,d,h),who,kind,0,integer(amount,0,1e12)or 0,i)
  end
 end
 table.sort(list,function(a,b)if a.at~=b.at then return a.at>b.at end;return a.order>b.order end)
 while #list>LEDGER do table.remove(list)end
 for _,e in ipairs(list)do e.order=nil end
 return list
end
function B.Read()
 if not B.open or not N.db or B.Unavailable()then return end
 local old=view()or{};local now=clock();local tabs={}
 for tab=1,math.min(MAX_TABS,GetNumGuildBankTabs())do
  local name,icon,viewable=GetGuildBankTabInfo(tab)
  if viewable then
   local items
   if loaded[tab]then items=readTab(tab)
   else for _,t in ipairs(old.tabs or{})do if t.index==tab then items=t.items end end end
   if items then
    local title=N.Clip(N.Safe(name),40)
    tabs[#tabs+1]={index=tab,name=title~=""and title or"Tab "..tab,icon=icon,items=items}
   end
  end
 end
 N.db.bankLog=nil
 N.db.bankView={stamp=now,by=N.Me(),money=integer(GetGuildBankMoney and GetGuildBankMoney(),0,1e12)or old.money or 0,tabs=tabs,ledger=logLoaded and readLedger(now)or old.ledger or{}}
 changed()
end
local function queryNext()
 querying=table.remove(queue,1);queriedAt=GetTime();nextQueryAt=nil
 if querying and QueryGuildBankTab then QueryGuildBankTab(querying)end
end
local function queueTabs()
 for tab=1,math.min(MAX_TABS,GetNumGuildBankTabs and GetNumGuildBankTabs()or 0)do
  local _,_,viewable=GetGuildBankTabInfo(tab)
  local waiting=querying==tab
  for _,t in ipairs(queue)do if t==tab then waiting=true end end
  if viewable and not loaded[tab]and not waiting then
   queue[#queue+1]=tab
   if QueryGuildBankLog then QueryGuildBankLog(tab)end
  end
 end
 if not querying then queryNext()end
end
local outbox,lastShared,shareAt={},-SHARE_THROTTLE,nil
local function opened()
 if B.open or B.Unavailable()then return end
 B.open,loaded,queue,querying,logLoaded=true,{},{},nil,false
 queueTabs()
 if QueryGuildBankLog then QueryGuildBankLog((MAX_GUILDBANK_TABS or 8)+1)end
 readAt=GetTime()+0.5;changed()
end
local function closed()
 if not B.open then return end
 B.Read();B.open,querying,queue=false,nil,{}
 if GetTime()-lastShared>=SHARE_THROTTLE then B.Share()else shareAt=lastShared+SHARE_THROTTLE end
 changed()
end

function B.Share()
 local v=view();if not v or not N.db then return false end
 local stamp,parts=v.stamp,{}
 local function part(op,...)parts[#parts+1]={op,...}end
 local function fits(op,...)return #N.Pack(op,stamp,999,...)<=240 end
 for _,tab in ipairs(v.tabs or{})do
  local icon=tostring(tab.icon or"")
  local chunk={}
  for _,it in ipairs(tab.items)do
   local entry=it.id..":"..it.count
   if #chunk>0 and not fits("B2",tab.index,tab.name,icon,table.concat(chunk,";")..";"..entry)then
    part("B2",tab.index,tab.name,icon,table.concat(chunk,";"));chunk={}
   end
   chunk[#chunk+1]=entry
  end
  part("B2",tab.index,tab.name,icon,table.concat(chunk,";"))
 end
 local chunk={}
 for _,e in ipairs(v.ledger or{})do
  local entry=table.concat({cleanName(e.who),e.kind,e.id,e.count,e.at},",")
  if #chunk>0 and not fits("B3",table.concat(chunk,";")..";"..entry)then part("B3",table.concat(chunk,";"));chunk={}end
  chunk[#chunk+1]=entry
 end
 if #chunk>0 then part("B3",table.concat(chunk,";"))end
 outbox={N.Pack("B1",stamp,v.money or 0,#parts,v.by or N.Me())}
 for i,p in ipairs(parts)do outbox[#outbox+1]=N.Pack(p[1],stamp,i,select(2,unpack(p)))end
 lastShared,shareAt=GetTime(),nil
 return true
end

local pending,heardStamp,heardAt,replyAt,lastReplyTo={},0,-100,nil,{}
local function assemble(key)
 local pend=pending[key];if not pend or not pend.total then return end
 for i=1,pend.total do if not pend.parts[i]then return end end
 pending[key]=nil
 local v=view();if v and v.stamp>=pend.stamp then return end
 local tabs,byIndex,ledger={},{},{}
 for i=1,pend.total do
  local p=pend.parts[i]
  if p.tab then
   local tab=byIndex[p.tab]
   if not tab then tab={index=p.tab,name=p.name,icon=p.icon,items={}};byIndex[p.tab]=tab;tabs[#tabs+1]=tab end
   for _,it in ipairs(p.items)do tab.items[#tab.items+1]=it end
  else for _,e in ipairs(p.entries)do ledger[#ledger+1]=e end end
 end
 table.sort(tabs,function(a,b)return a.index<b.index end)
 table.sort(ledger,function(a,b)return a.at>b.at end)
 while #ledger>LEDGER do table.remove(ledger)end
 N.db.bankView={stamp=pend.stamp,by=pend.by,money=pend.money,tabs=tabs,ledger=ledger}
 changed()
end
local function pendingFor(sender,stamp)
 local key=sender.."|"..stamp;local now,total=GetTime(),0
 for k,p in pairs(pending)do if now-p.at>120 then pending[k]=nil else total=total+1 end end
 if not pending[key]then
  if total>=10 then return end
  pending[key]={at=now,stamp=stamp,parts={}}
 end
 return pending[key],key
end
function B.Receive(op,p,sender)
 if not N.db or not N.members[sender]or sender==N.Me()then return end
 if op=="BQ"then
  local since=#p==2 and integer(p[2],0,1e11);local v=view()
  if not since or not v or v.stamp<=since then return end
  if lastReplyTo[sender]and GetTime()-lastReplyTo[sender]<SHARE_THROTTLE then return end
  lastReplyTo[sender]=GetTime()
  -- A random delay lets one holder answer while the others hear it and stay quiet.
  replyAt=replyAt or GetTime()+2+math.random(0,4)
  return
 end
 local stamp=integer(p[2],1,1e11);if not stamp or stamp>clock()+300 then return end
 if op=="B1"and #p==5 then
  local money,total=integer(p[3],0,1e12),integer(p[4],0,200);if not money or not total then return end
  if stamp>=heardStamp then heardStamp,heardAt=stamp,GetTime()end
  local v=view();if v and v.stamp>=stamp then return end
  local pend,key=pendingFor(sender,stamp);if not pend then return end
  local by=N.Full(p[5]);pend.money,pend.total,pend.by=money,total,N.members[by]and by or sender
  assemble(key)
 elseif op=="B2"and #p==7 then
  local index,tab=integer(p[3],1,200),integer(p[4],1,MAX_TABS);if not index or not tab then return end
  local items={}
  for id,count in p[7]:gmatch("(%d+):(%d+)")do
   id,count=integer(id,1,10000000),integer(count,1,1000000)
   if id and count and #items<200 then items[#items+1]={id=id,count=count}end
  end
  local icon=tonumber(p[6])or(#p[6]<=120 and p[6]:match("^[%w\\/_%-%.]+$"))or nil
  local pend,key=pendingFor(sender,stamp);if not pend then return end
  local name=N.Clip(N.Safe(p[5]),40)
  pend.parts[index]={tab=tab,name=name~=""and name or"Tab "..tab,icon=icon,items=items}
  assemble(key)
 elseif op=="B3"and #p==4 then
  local index=integer(p[3],1,200);if not index then return end
  local entries={}
  for who,kind,id,count,at in p[4]:gmatch("([^,;]+),(%a+),(%d+),(%d+),(%d+)")do
   id,count,at=integer(id,0,10000000),integer(count,0,1e12),integer(at,0,1e11)
   if id and count and at and at<=clock()+300 and #entries<LEDGER then entries[#entries+1]={who=N.Clip(N.Safe(who),40),kind=kind,id=id,count=count,at=at}end
  end
  local pend,key=pendingFor(sender,stamp);if not pend then return end
  pend.parts[index]={entries=entries}
  assemble(key)
 end
end

local queryAt
local driver=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_INTERACTION_MANAGER_FRAME_SHOW","PLAYER_INTERACTION_MANAGER_FRAME_HIDE","GUILDBANKFRAME_OPENED","GUILDBANKFRAME_CLOSED","GUILDBANKBAGSLOTS_CHANGED","GUILDBANKLOG_UPDATE","GUILDBANK_UPDATE_MONEY","GUILDBANK_UPDATE_TABS","GET_ITEM_INFO_RECEIVED"})do pcall(driver.RegisterEvent,driver,event)end
local renderAt
driver:SetScript("OnEvent",function(_,event,arg)
 if event=="PLAYER_ENTERING_WORLD"then
  queryAt=queryAt or GetTime()+20
 elseif event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW"or event=="PLAYER_INTERACTION_MANAGER_FRAME_HIDE"then
  local banker=Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
  if arg==banker then if event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW"then opened()else closed()end end
 elseif event=="GUILDBANKFRAME_OPENED"then opened()
 elseif event=="GUILDBANKFRAME_CLOSED"then closed()
 elseif event=="GET_ITEM_INFO_RECEIVED"then
  if N.page=="Guild bank"then renderAt=renderAt or GetTime()+0.3 end
 elseif B.open then
  if event=="GUILDBANKBAGSLOTS_CHANGED"then
   if querying then loaded[querying]=true;querying=nil;nextQueryAt=GetTime()+0.3 end
   local current=GetCurrentGuildBankTab and GetCurrentGuildBankTab()
   if current then loaded[current]=true end
  elseif event=="GUILDBANKLOG_UPDATE"then logLoaded=true
  elseif event=="GUILDBANK_UPDATE_TABS"then queueTabs()end
  readAt=GetTime()+0.4
 end
end)
local wait=0
driver:SetScript("OnUpdate",function(_,dt)
 wait=wait+dt;if wait<0.25 then return end;wait=0
 local now=GetTime()
 if B.open then
  if querying and now-queriedAt>QUERY_TIMEOUT then querying=nil;nextQueryAt=now end
  if not querying and nextQueryAt and now>=nextQueryAt then queryNext()end
  if readAt and now>=readAt then readAt=nil;B.Read()end
 end
 if renderAt and now>=renderAt then renderAt=nil;changed()end
 if not N.db then return end
 if queryAt and now>=queryAt then queryAt=nil;local v=view();N.Send("BQ",v and v.stamp or 0)end
 if shareAt and now>=shareAt and not B.open then B.Share()end
 if replyAt and now>=replyAt then
  local v=view()
  if v and not(now-heardAt<8 and heardStamp>=v.stamp)then B.Share()end
  replyAt=nil
 end
 while #outbox>0 and N.queue and #N.queue<80 do N.queue[#N.queue+1]=table.remove(outbox,1)end
end)
