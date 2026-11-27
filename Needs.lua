local _,N=...
-- Guild material and gold requests. They travel on the addon's guild channel.
-- Owners re-announce their open requests when a member logs in and asks, so
-- people who were offline at posting time still see them.
local R={};N.Needs=R
local EXPIRY=3*24*60*60
local MAX_ITEMS,MAX_OPEN,MAX_GOLD,MAX_COUNT=8,3,10000,1000
R.professions={"Alchemy","Blacksmithing","Enchanting","Engineering","Leatherworking","Tailoring","Cooking","First Aid","Other"}
R.BANK="Guild bank"
local isProfession={[R.BANK]=true};for _,p in ipairs(R.professions)do isProfession[p]=true end
local COIN="Interface\\Icons\\INV_Misc_Coin_01"

local function store()
 if not N.db then return nil end
 if type(N.db.needs)~="table"then N.db.needs={}end
 return N.db.needs
end
local function settings()
 NoDramaDB=NoDramaDB or{guilds={}}
 if type(NoDramaDB.needsTracker)~="table"then NoDramaDB.needsTracker={shown=true}end
 return NoDramaDB.needsTracker
end
local function short(name)return(name or""):match("^[^-]+")or name or""end
R.Short=short
function R.Title(req)
 if req.prof==R.BANK then return req.kind=="gold"and"Guild bank gold"or"Guild bank items"end
 return req.kind=="gold"and"Gold"or req.prof
end
R.Settings=settings
local function itemID(text)
 if type(text)~="string"then return nil end
 local id=text:match("item:(%d+)")or text:match("^%s*(%d+)%s*$")
 if not id and GetItemInfo then
  local _,link=GetItemInfo(text:gsub("^%s+",""):gsub("%s+$",""))
  id=link and link:match("item:(%d+)")
 end
 return tonumber(id)
end
-- Names sent by the poster, for items this client has not loaded yet.
local knownNames={}
function R.ItemName(id)
 local name=GetItemInfo and GetItemInfo(id)
 if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id)end
 return name or knownNames[id]or("Item #"..id)
end
function R.ItemIcon(id)
 local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
 if not icon and GetItemIcon then icon=GetItemIcon(id)end
 return icon or"Interface\\Icons\\INV_Misc_QuestionMark"
end
function R.Have(id)return GetItemCount and GetItemCount(id,true)or 0 end
function R.Remaining(req,i)
 if req.kind=="gold"then return math.max(0,req.gold-(req.given or 0))end
 local it=req.items[i];return it and math.max(0,it.count-(it.given or 0))or 0
end
function R.Done(req)
 if req.kind=="gold"then return R.Remaining(req)==0 end
 for i in ipairs(req.items)do if R.Remaining(req,i)>0 then return false end end
 return true
end
function R.LeftText(req)
 if req.kind=="gold"then return R.Remaining(req).."g"end
 local left=0;for i in ipairs(req.items)do left=left+R.Remaining(req,i)end
 return tostring(left)
end
function R.Summary(req,limit)
 if req.kind=="gold"then return R.Remaining(req).."g"..(req.reason~=""and" - "..req.reason or"")end
 local parts,more={},0
 for i,it in ipairs(req.items)do
  local left=R.Remaining(req,i)
  if left>0 then
   if not limit or #parts<limit then parts[#parts+1]=left.."x "..R.ItemName(it.id)else more=more+1 end
  end
 end
 if #parts==0 then return"All covered"end
 return table.concat(parts,", ")..(more>0 and", +"..more.." more"or"")
end
function R.Age(req)
 local minutes=math.floor((time()-req.stamp)/60)
 if minutes<1 then return"just now"elseif minutes<60 then return minutes.." min ago"end
 local hours=math.floor(minutes/60)
 return hours<24 and hours.." h ago"or math.floor(hours/24).." d ago"
end
function R.List()
 local s=store();if not s then return{}end
 local now=time();local list={};local rosterLoaded=next(N.members)~=nil;local me=N.Me()
 for id,req in pairs(s)do
  if type(req)~="table"or type(req.stamp)~="number"or now-req.stamp>EXPIRY
   or(rosterLoaded and req.owner~=me and not N.members[req.owner])then s[id]=nil
  else
   list[#list+1]=req
   for _,it in ipairs(req.items or{})do if it.name and not knownNames[it.id]then knownNames[it.id]=it.name end end
  end
 end
 table.sort(list,function(a,b)return a.stamp>b.stamp end)
 return list
end
function R.Changed()
 if R.UpdateTracker then R.UpdateTracker()end
 if R.UpdateMailPanel then R.UpdateMailPanel()end
 if N.window and N.window:IsShown()and N.Render then N.Render()end
end

local function announce(req)
 local messages={N.Pack("N1",req.id,req.kind,req.prof,req.gold,req.given or 0,req.reason,#req.items)}
 for i,it in ipairs(req.items)do messages[#messages+1]=N.Pack("N2",req.id,i,it.id,it.count,it.given or 0)end
 -- Separate message so 0.17.0 clients, which require exactly six N2 fields, keep working.
 for i,it in ipairs(req.items)do
  local name=GetItemInfo and GetItemInfo(it.id)or it.name
  if name then messages[#messages+1]=N.Pack("N3",req.id,i,N.Clip(N.Safe(name),60))end
 end
 if #N.queue+#messages>100 then return false end
 for _,m in ipairs(messages)do if #m>240 then return false end end
 for _,m in ipairs(messages)do N.queue[#N.queue+1]=m end
 return true
end
local function announceMine()
 local me=N.Me()
 for _,req in ipairs(R.List())do if req.owner==me then announce(req)end end
end
function R.Close(id)
 local s=store();local req=s and s[id]
 if not req or req.owner~=N.Me()then return false end
 N.Send("NX",id);s[id]=nil;R.Changed()
 return true
end
function R.Post(kind,prof,items,goldAmount,reason)
 local s=store();if not s then return false,"Join a guild to post a request."end
 reason=N.Clip(N.Safe(reason or""):gsub("^%s+",""):gsub("%s+$",""),80)
 local clean={}
 if kind=="mats"then
  if not isProfession[prof]then return false,"Choose the profession you are leveling."end
  for _,it in ipairs(items or{})do
   local id,count=tonumber(it.id),tonumber(it.count)
   if id and count and count>=1 then
    id=math.floor(id)
    clean[#clean+1]={id=id,count=math.min(MAX_COUNT,math.floor(count)),given=0,name=GetItemInfo and GetItemInfo(id)or nil}
   end
  end
  if #clean==0 then return false,"Add at least one material."end
  if #clean>MAX_ITEMS then return false,"Up to "..MAX_ITEMS.." materials per request."end
  goldAmount=0
 elseif kind=="gold"then
  goldAmount=tonumber(goldAmount)
  if not goldAmount or goldAmount<1 or goldAmount>MAX_GOLD then return false,"Enter an amount from 1 to "..MAX_GOLD.." gold."end
  if reason==""then return false,"Say what the gold is for, for example: first mount."end
  goldAmount=math.floor(goldAmount);prof=prof==R.BANK and R.BANK or""
 else return false,"Choose profession mats or gold."end
 local me=N.Me();local mine={}
 for _,req in ipairs(R.List())do if req.owner==me then mine[#mine+1]=req end end
 table.sort(mine,function(a,b)return a.stamp<b.stamp end)
 while #mine>=MAX_OPEN do R.Close(table.remove(mine,1).id)end
 R.sequence=(R.sequence or 0)+1
 local stamp=time()
 local req={id=me..":"..stamp..":"..R.sequence,owner=me,kind=kind,prof=prof,items=clean,gold=goldAmount,given=0,reason=reason,stamp=stamp}
 if not announce(req)then return false,"The addon message queue is full. Try again in a moment."end
 s[req.id]=req;R.Changed()
 return true
end
local function applyGift(req,index,count,giver)
 if index==0 and req.kind=="gold"then req.given=math.min(req.gold,(req.given or 0)+count)
 elseif req.kind=="mats"and req.items[index]then local it=req.items[index];it.given=math.min(it.count,(it.given or 0)+count)
 else return false end
 req.gifts=type(req.gifts)=="table"and req.gifts or{}
 table.insert(req.gifts,{from=giver,index=index,count=count,stamp=time()})
 while #req.gifts>20 do table.remove(req.gifts,1)end
 return true
end
-- index 0 means gold. This only tells the guild; the items or gold go by mail or trade.
function R.Give(id,index,count)
 local s=store();local req=s and s[id];count=tonumber(count);index=tonumber(index)
 if not req or not count or count<1 or not index then return false end
 count=math.min(MAX_GOLD,math.floor(count))
 if not N.Send("NG",id,index,count)then return false end
 applyGift(req,index,count,N.Me());R.Changed()
 return true
end
local pending={}
local function ownedID(id,sender)
 return type(id)=="string"and #id<=120 and id:sub(1,#sender+1)==sender..":"and id:sub(#sender+2):match("^%d+:%d+$")~=nil
end
local function number(v,lo,hi)
 v=tonumber(v)
 if not v or v~=math.floor(v)or v<lo or v>hi then return nil end
 return v
end
local function publish(id)
 local p=pending[id];if not p or not p.header then return end
 local h=p.header
 for i=1,h.count do if not p.items[i]then return end end
 local s=store();if not s then return end
 local old=s[id]
 local req={id=id,owner=p.owner,kind=h.kind,prof=h.prof,gold=h.gold,given=h.given,reason=h.reason,items={},stamp=h.stamp,gifts=old and old.gifts}
 for i=1,h.count do
  local it=p.items[i];local before=old and old.items and old.items[i]
  if before and before.id==it.id then it.given=math.max(it.given,before.given or 0);it.name=it.name or before.name end
  req.items[i]=it
 end
 if old then req.given=math.max(req.given,old.given or 0)end
 s[id]=req;pending[id]=nil
 -- Re-announced old requests arrive in a burst at login; only fresh ones notify.
 if not old and p.owner~=N.Me()and time()-h.stamp<600 then
  local what=h.prof==R.BANK and(h.kind=="gold"and h.gold.." gold"or"items").." from the guild bank"or(h.kind=="gold"and h.gold.." gold"or h.prof.." mats")
  N.Notify(N.Safe(short(p.owner)).." needs "..what..". See the guild needs window or /zd.")
 end
 R.Changed()
end
local function pendingFor(id,owner)
 local now,total=time(),0
 for key,p in pairs(pending)do if now-p.at>120 then pending[key]=nil else total=total+1 end end
 if pending[id]then return pending[id]end
 if total>=40 then return nil end
 pending[id]={owner=owner,at=now,items={}}
 return pending[id]
end
local lastQueryReply=-100
function R.Receive(op,p,sender)
 local s=store();if not s then return end
 if op=="N1"and #p==8 and ownedID(p[2],sender)then
  local kind,prof=p[3],N.Safe(p[4])
  local goldAmount,given,count=number(p[5],0,MAX_GOLD),number(p[6],0,MAX_GOLD),number(p[8],0,MAX_ITEMS)
  local stamp=number(p[2]:match(":(%d+):%d+$"),0,math.huge)
  if not goldAmount or not given or not count or not stamp then return end
  if kind=="mats"then if not isProfession[prof]or count<1 then return end
  elseif kind=="gold"then if goldAmount<1 or count~=0 then return end;prof=prof==R.BANK and R.BANK or""
  else return end
  local pend=pendingFor(p[2],sender);if not pend then return end
  pend.header={kind=kind,prof=prof,gold=goldAmount,given=math.min(given,goldAmount),reason=N.Clip(N.Safe(p[7]),80),count=count,stamp=stamp}
  publish(p[2])
 elseif op=="N2"and #p==6 and ownedID(p[2],sender)then
  local index,id,count,given=number(p[3],1,MAX_ITEMS),number(p[4],1,10000000),number(p[5],1,MAX_COUNT),number(p[6],0,MAX_COUNT)
  if not index or not id or not count or not given then return end
  local pend=pendingFor(p[2],sender);if not pend then return end
  pend.items[index]={id=id,count=count,given=math.min(given,count)}
  publish(p[2])
 elseif op=="N3"and #p==4 and ownedID(p[2],sender)then
  local index,name=number(p[3],1,MAX_ITEMS),N.Clip(N.Safe(p[4]),60)
  local req=s[p[2]];local it=req and req.items[index]
  if not it or name==""then return end
  it.name=name
  if not knownNames[it.id]then knownNames[it.id]=name;R.Changed()end
 elseif op=="NX"and #p==2 and ownedID(p[2],sender)then
  pending[p[2]]=nil
  if s[p[2]]then s[p[2]]=nil;R.Changed()end
 elseif op=="NG"and #p==4 then
  local req=s[p[2]];local index,count=number(p[3],0,MAX_ITEMS),number(p[4],1,MAX_GOLD)
  if not req or not index or not count or sender==N.Me()then return end
  if applyGift(req,index,count,sender)then
   if req.owner==N.Me()then
    local what=index==0 and count.." gold"or count.."x "..R.ItemName(req.items[index].id)
    N.Notify(N.Safe(short(sender)).." says they sent you "..what..". Check your mailbox.")
   end
   R.Changed()
  end
 elseif op=="NQ"and #p==1 and sender~=N.Me()then
  -- Throttled so several members logging in together cost one re-announce.
  if GetTime()-lastQueryReply>60 then lastQueryReply=GetTime();announceMine()end
 end
end

local function makeFrame(name,width,height,title)
 local ok,f=pcall(CreateFrame,"Frame",name,UIParent,"BasicFrameTemplateWithInset")
 if not ok or not f then
  f=CreateFrame("Frame",name,UIParent,"BackdropTemplate")
  f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",tile=true,tileSize=32,edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
 end
 f:SetSize(width,height);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true);f:Hide()
 f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag("LeftButton")
 f:SetScript("OnDragStart",f.StartMoving);f:SetScript("OnDragStop",f.StopMovingOrSizing)
 if f.CloseButton then f.CloseButton:SetScript("OnClick",function()f:Hide()end)end
 tinsert(UISpecialFrames,name)
 local t=f:CreateFontString(nil,"OVERLAY","GameFontNormal");t:SetPoint("TOPLEFT",12,-7);t:SetWidth(width-40);t:SetJustifyH("LEFT");t:SetText(title)
 f.title=t
 return f
end
local function text(parent,font,x,y,w)
 local t=parent:CreateFontString(nil,"OVERLAY",font);t:SetPoint("TOPLEFT",x,y);t:SetWidth(w);t:SetJustifyH("LEFT")
 return t
end
local function button(parent,label,x,y,w,fn)
 local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn)
 return b
end
local function input(parent,x,y,w,maxBytes,numeric)
 local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
 e:SetSize(w,22);e:SetPoint("TOPLEFT",x+5,y);e:SetAutoFocus(false);e:SetMaxBytes(maxBytes);e:SetNumeric(numeric==true)
 e:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
 return e
end
local function itemTooltip(owner,id,lines)
 GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
 if not pcall(GameTooltip.SetHyperlink,GameTooltip,"item:"..id)then GameTooltip:SetText(R.ItemName(id))end
 for _,line in ipairs(lines or{})do GameTooltip:AddLine(line,1,0.82,0)end
 GameTooltip:Show()
end

-- Post form.
local form=makeFrame("NoDramaNeedsForm",390,430,"Ask the guild for help")
form.items={}
local kindMats=button(form,"Profession mats",14,-32,178,function()form.setKind("mats")end)
local kindGold=button(form,"Gold",198,-32,178,function()form.setKind("gold")end)
local profLabel=text(form,"GameFontNormalSmall",18,-64,160);profLabel:SetText("Profession you are leveling")
local profPick=button(form,"",14,-80,178,function()form.menu:SetShown(not form.menu:IsShown())end)
local goldLabel=text(form,"GameFontNormalSmall",18,-64,160);goldLabel:SetText("Amount (gold)")
local goldBox=input(form,14,-80,120,5,true)
local addLabel=text(form,"GameFontNormalSmall",18,-110,226)
addLabel:SetText("Material: shift-click it, or type name/ID")
local itemBox=input(form,14,-126,222,120)
local countLabel=text(form,"GameFontNormalSmall",250,-110,40);countLabel:SetText("Qty")
local countBox=input(form,244,-126,48,4,true)
local addButton=button(form,"Add",304,-125,72,function()form.addTyped()end)
local recipeButton=button(form,"Add missing mats for selected recipe",14,-154,272,function()form.addRecipe()end)
local craftsBox=input(form,292,-155,36,3,true)
local craftsLabel=text(form,"GameFontHighlightSmall",336,-160,44);craftsLabel:SetText("crafts")
local listLabel=text(form,"GameFontNormalSmall",18,-186,350)
local rows={}
for i=1,MAX_ITEMS do
 local r=CreateFrame("Frame",nil,form);r:SetSize(362,22);r:SetPoint("TOPLEFT",14,-202-(i-1)*22)
 r.icon=r:CreateTexture(nil,"ARTWORK");r.icon:SetSize(18,18);r.icon:SetPoint("LEFT",2,0)
 r.name=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.name:SetPoint("LEFT",26,0);r.name:SetWidth(230);r.name:SetJustifyH("LEFT");r.name:SetWordWrap(false)
 r.count=input(r,256,0,48,4,true);r.count:ClearAllPoints();r.count:SetPoint("LEFT",262,0)
 r.count:SetScript("OnTextChanged",function(self)local it=form.items[i];if it then it.count=tonumber(self:GetText())or 0 end end)
 r.remove=CreateFrame("Button",nil,r,"UIPanelButtonTemplate");r.remove:SetSize(40,20);r.remove:SetPoint("LEFT",318,0);r.remove:SetText("X")
 r.remove:SetScript("OnClick",function()table.remove(form.items,i);form.refresh()end)
 r:EnableMouse(true)
 r:SetScript("OnEnter",function(self)local it=form.items[i];if it then itemTooltip(self,it.id,{"You have "..R.Have(it.id)})end end)
 r:SetScript("OnLeave",function()GameTooltip:Hide()end)
 rows[i]=r
end
local reasonLabel=form:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");reasonLabel:SetPoint("BOTTOMLEFT",18,74);reasonLabel:SetWidth(350);reasonLabel:SetJustifyH("LEFT")
local reasonBox=CreateFrame("EditBox",nil,form,"InputBoxTemplate")
reasonBox:SetSize(352,22);reasonBox:SetPoint("BOTTOMLEFT",19,48);reasonBox:SetAutoFocus(false);reasonBox:SetMaxBytes(80)
reasonBox:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
local post=CreateFrame("Button",nil,form,"UIPanelButtonTemplate");post:SetSize(178,24);post:SetPoint("BOTTOMLEFT",14,14);post:SetText("Post request")
local cancel=CreateFrame("Button",nil,form,"UIPanelButtonTemplate");cancel:SetSize(178,24);cancel:SetPoint("BOTTOMRIGHT",-14,14);cancel:SetText("Cancel")
cancel:SetScript("OnClick",function()form:Hide()end)
local menu=CreateFrame("Frame",nil,form,"BackdropTemplate");form.menu=menu
menu:SetPoint("TOPLEFT",profPick,"BOTTOMLEFT",0,-2);menu:SetSize(178,8+#R.professions*18);menu:SetFrameLevel(form:GetFrameLevel()+10);menu:EnableMouse(true)
menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
menu:SetBackdropColor(0.05,0.05,0.06,0.97);menu:SetBackdropBorderColor(0.5,0.4,0.25,1);menu:Hide()
for i,prof in ipairs(R.professions)do
 local b=CreateFrame("Button",nil,menu);b:SetSize(170,18);b:SetPoint("TOPLEFT",4,-4-(i-1)*18)
 local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("LEFT",4,0);t:SetText(prof)
 b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
 b:SetScript("OnClick",function()form.prof=prof;profPick:SetText(prof);menu:Hide()end)
end
function form.refresh()
 for i,r in ipairs(rows)do
  local it=form.items[i];r:SetShown(form.kind=="mats"and it~=nil)
  if it then
   r.icon:SetTexture(R.ItemIcon(it.id));r.name:SetText(R.ItemName(it.id))
   if tonumber(r.count:GetText())~=it.count then r.count:SetText(tostring(it.count))end
  end
 end
 listLabel:SetText(#form.items>0 and"Materials ("..#form.items.."/"..MAX_ITEMS..")   amount needed:"or"No materials added yet.")
end
function form.addItem(id,count)
 count=math.max(1,math.min(MAX_COUNT,math.floor(tonumber(count)or 1)))
 for _,it in ipairs(form.items)do if it.id==id then it.count=math.min(MAX_COUNT,it.count+count);form.refresh();return true end end
 if #form.items>=MAX_ITEMS then N.Notify("Up to "..MAX_ITEMS.." materials per request.");return false end
 form.items[#form.items+1]={id=id,count=count};form.refresh()
 return true
end
function form.addTyped()
 local id=itemID(itemBox:GetText())
 if not id then N.Notify("Item not found. Shift-click it from your bags, the auction house or a recipe instead.");return end
 if form.addItem(id,countBox:GetText())then itemBox:SetText("")end
end
itemBox:SetScript("OnEnterPressed",form.addTyped)
local function readRecipe(crafts)
 local out={}
 local function scan(index,num,info,link)
  for r=1,num(index)do
   local _,_,need=info(index,r)
   local l=link and link(index,r);local id=l and tonumber(l:match("item:(%d+)"))
   if id and type(need)=="number"then
    local missing=need*crafts-R.Have(id)
    if missing>0 then out[#out+1]={id=id,count=missing}end
   end
  end
 end
 if GetTradeSkillSelectionIndex and GetTradeSkillNumReagents and TradeSkillFrame and TradeSkillFrame:IsVisible()then
  local index=GetTradeSkillSelectionIndex()
  if index and index>0 then pcall(scan,index,GetTradeSkillNumReagents,GetTradeSkillReagentInfo,GetTradeSkillReagentItemLink)end
 end
 -- Classic Enchanting uses the separate craft window.
 if #out==0 and GetCraftSelectionIndex and GetCraftNumReagents and CraftFrame and CraftFrame:IsVisible()then
  local index=GetCraftSelectionIndex()
  if index and index>0 then pcall(scan,index,GetCraftNumReagents,GetCraftReagentInfo,GetCraftReagentItemLink)end
 end
 return out
end
function form.addRecipe()
 local crafts=math.max(1,math.min(100,tonumber(craftsBox:GetText())or 1))
 local mats=readRecipe(crafts)
 if #mats==0 then N.Notify("Open your profession window and select a recipe. Mats you already have are not added.");return end
 for _,it in ipairs(mats)do form.addItem(it.id,it.count)end
end
function form.setKind(kind)
 form.kind=kind
 local mats=kind=="mats"
 if mats then kindMats:LockHighlight();kindGold:UnlockHighlight()else kindGold:LockHighlight();kindMats:UnlockHighlight()end
 for _,w in ipairs({profLabel,profPick,addLabel,itemBox,countLabel,countBox,addButton,recipeButton,craftsBox,craftsLabel,listLabel})do w:SetShown(mats)end
 goldLabel:SetShown(not mats);goldBox:SetShown(not mats);menu:Hide()
 reasonLabel:SetText(mats and"Note (optional), for example: leveling 150 to 175"or"What is the gold for? For example: first mount")
 form:SetHeight(mats and 430 or 200)
 form.refresh()
end
post:SetScript("OnClick",function()
 local ok,err=R.Post(form.kind,form.prof,form.items,goldBox:GetText(),reasonBox:GetText())
 if not ok then N.Notify(err);return end
 form:Hide();N.Notify("Request posted. Guild members with ZERO DRAMA see it in their guild needs window.")
end)
function R.OpenForm(kind)
 form.items={};form.prof=form.prof or"Blacksmithing";profPick:SetText(form.prof)
 itemBox:SetText("");countBox:SetText("1");craftsBox:SetText("1");goldBox:SetText("");reasonBox:SetText("")
 form.setKind(kind or"mats");form:Show()
end
-- Shift-clicking an item while the material box has focus adds it.
local lastLink,lastLinkAt
local function insertLink(link)
 if not form:IsShown()or form.kind~="mats"or not itemBox:HasFocus()or type(link)~="string"then return end
 if link==lastLink and GetTime()-lastLinkAt<0.2 then return end
 lastLink,lastLinkAt=link,GetTime()
 local id=tonumber(link:match("item:(%d+)"))
 if id then form.addItem(id,countBox:GetText());itemBox:SetText("")end
end
if type(ChatEdit_InsertLink)=="function"then hooksecurefunc("ChatEdit_InsertLink",insertLink)end
if ChatFrameUtil and type(ChatFrameUtil.InsertLink)=="function"then hooksecurefunc(ChatFrameUtil,"InsertLink",insertLink)end

-- "I sent some" dialog.
local give=makeFrame("NoDramaNeedsGive",340,300,"")
local giveHelp=text(give,"GameFontHighlightSmall",16,-30,310);giveHelp:SetWordWrap(true)
giveHelp:SetText("For trades. Mail sent from the mailbox is recorded automatically. This only updates the guild's list.")
local giveRows={}
for i=1,MAX_ITEMS do
 local r=CreateFrame("Frame",nil,give);r:SetSize(310,22);r:SetPoint("TOPLEFT",14,-62-(i-1)*24)
 r.icon=r:CreateTexture(nil,"ARTWORK");r.icon:SetSize(18,18);r.icon:SetPoint("LEFT",2,0)
 r.name=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.name:SetPoint("LEFT",26,0);r.name:SetWidth(210);r.name:SetJustifyH("LEFT");r.name:SetWordWrap(false)
 r.count=input(r,0,0,52,5,true);r.count:ClearAllPoints();r.count:SetPoint("LEFT",250,0)
 r:EnableMouse(true)
 r:SetScript("OnEnter",function(self)if self.id then itemTooltip(self,self.id)end end)
 r:SetScript("OnLeave",function()GameTooltip:Hide()end)
 giveRows[i]=r
end
local giveConfirm=CreateFrame("Button",nil,give,"UIPanelButtonTemplate");giveConfirm:SetSize(150,24);giveConfirm:SetPoint("BOTTOMLEFT",14,14);giveConfirm:SetText("Mark as sent")
local giveMail=CreateFrame("Button",nil,give,"UIPanelButtonTemplate");giveMail:SetSize(150,24);giveMail:SetPoint("BOTTOMRIGHT",-14,14);giveMail:SetText("Fill in mail")
function R.OpenGive(id)
 local s=store();local req=s and s[id];if not req then return end
 give.id=id;give.title:SetText("Send to "..N.Safe(short(req.owner)))
 local n=0
 if req.kind=="gold"then
  n=1;local r=giveRows[1];r.id=nil;r.index=0
  r.icon:SetTexture(COIN);r.name:SetText("Gold  ("..R.Remaining(req).."g still needed)");r.count:SetText("")
 else
  for i,it in ipairs(req.items)do
   local left=R.Remaining(req,i)
   if left>0 then
    n=n+1;local r=giveRows[n];r.id=it.id;r.index=i
    r.icon:SetTexture(R.ItemIcon(it.id));r.name:SetText(R.ItemName(it.id).."  (needs "..left..", you have "..R.Have(it.id)..")")
    r.count:SetText("")
   end
  end
 end
 for i,r in ipairs(giveRows)do r:SetShown(i<=n)end
 give:SetHeight(110+n*24);give:Show()
end
giveConfirm:SetScript("OnClick",function()
 local sent=0
 for _,r in ipairs(giveRows)do
  local count=r:IsShown()and tonumber(r.count:GetText())
  if count and count>0 and R.Give(give.id,r.index,count)then sent=sent+1 end
 end
 if sent==0 then N.Notify("Enter how many you sent next to at least one line.");return end
 give:Hide();N.Notify("Thanks! The guild's list is updated.")
end)
giveMail:SetScript("OnClick",function()local s=store();local req=s and s[give.id];if req then R.FillMail(req)end end)

-- Small always-on window listing what guild members still need.
local MAX_ROWS=6
local tracker=CreateFrame("Frame","NoDramaNeedsTracker",UIParent,"BackdropTemplate")
tracker:SetSize(250,40);tracker:SetFrameStrata("MEDIUM");tracker:SetClampedToScreen(true);tracker:SetMovable(true);tracker:EnableMouse(true);tracker:RegisterForDrag("LeftButton");tracker:Hide()
tracker:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=2,right=2,top=2,bottom=2}})
tracker:SetBackdropColor(0.05,0.045,0.04,0.82);tracker:SetBackdropBorderColor(0.62,0.45,0.24,0.9)
tracker:SetScript("OnDragStart",tracker.StartMoving)
tracker:SetScript("OnDragStop",function(self)
 self:StopMovingOrSizing()
 local point,_,relative,x,y=self:GetPoint();settings().point={point,relative,x,y}
end)
local heading=tracker:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");heading:SetPoint("TOPLEFT",8,-7);heading:SetWidth(190);heading:SetJustifyH("LEFT")
local collapse=CreateFrame("Button",nil,tracker);collapse:SetSize(18,18);collapse:SetPoint("TOPRIGHT",-22,-3)
collapse:SetNormalFontObject("GameFontNormal");collapse:SetText("-")
collapse:SetScript("OnClick",function()local st=settings();st.collapsed=not st.collapsed;R.UpdateTracker()end)
local hideButton=CreateFrame("Button",nil,tracker,"UIPanelCloseButton");hideButton:SetSize(22,22);hideButton:SetPoint("TOPRIGHT",0,0)
hideButton:SetScript("OnClick",function()
 R.SetTrackerShown(false)
 N.Notify("Guild needs window hidden. Turn it back on in the Requests tab, or type /zd needs.")
end)
local footer=tracker:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");footer:SetJustifyH("LEFT");footer:SetWidth(234)
local trackerRows={}
local function trackerRow(i)
 local r=trackerRows[i];if r then return r end
 r=CreateFrame("Button",nil,tracker);r:SetSize(234,40);r:RegisterForClicks("LeftButtonUp","RightButtonUp")
 r.shade=r:CreateTexture(nil,"BACKGROUND");r.shade:SetAllPoints();r.shade:SetColorTexture(1,1,1,i%2==0 and 0.04 or 0.0)
 r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
 r.title=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.title:SetPoint("TOPLEFT",2,-2);r.title:SetWidth(230);r.title:SetJustifyH("LEFT");r.title:SetWordWrap(false)
 r.line=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.line:SetPoint("TOPLEFT",24,-20);r.line:SetWidth(208);r.line:SetJustifyH("LEFT");r.line:SetWordWrap(false)
 r.icons={}
 for k=1,MAX_ITEMS do
  local b=CreateFrame("Button",nil,r);b:SetSize(20,20);b:SetPoint("TOPLEFT",2+(k-1)*29,-16)
  b.tex=b:CreateTexture(nil,"ARTWORK");b.tex:SetAllPoints()
  b.count=b:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall");b.count:SetPoint("BOTTOMRIGHT",4,-2)
  b:SetScript("OnEnter",function(self)
   if self.id then itemTooltip(self,self.id,{"Still needed: "..self.left,"You have: "..R.Have(self.id),"Click to send, right-click to mark as sent"})end
  end)
  b:SetScript("OnLeave",function()GameTooltip:Hide()end)
  b:RegisterForClicks("LeftButtonUp","RightButtonUp")
  b:SetScript("OnClick",function(_,mouse)r:GetScript("OnClick")(r,mouse)end)
  r.icons[k]=b
 end
 r:SetScript("OnClick",function(self,mouse)
  local s=store();local req=s and self.id and s[self.id];if not req then return end
  if mouse=="RightButton"then if req.owner~=N.Me()then R.OpenGive(req.id)end;return end
  if _G.MailFrame and _G.MailFrame:IsVisible()and req.owner~=N.Me()then R.FillMail(req)
  elseif N.ShowNeedsPage then N.ShowNeedsPage(req.id)end
 end)
 r:SetScript("OnEnter",function(self)
  local s=store();local req=s and self.id and s[self.id];if not req then return end
  GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText(N.Safe(short(req.owner)).." - "..R.Title(req),1,0.82,0)
  if req.reason~=""then GameTooltip:AddLine("\""..req.reason.."\"",1,1,1,true)end
  GameTooltip:AddLine(R.Summary(req),0.9,0.9,0.9,true)
  GameTooltip:AddLine("Click: open details (at a mailbox: fill in the mail and attach the mats)",0.6,0.6,0.6)
  if req.owner~=N.Me()then GameTooltip:AddLine("Right-click: record something you traded",0.6,0.6,0.6)end
  GameTooltip:Show()
 end)
 r:SetScript("OnLeave",function()GameTooltip:Hide()end)
 trackerRows[i]=r
 return r
end
function R.TrackerShown()return settings().shown~=false end
function R.SetTrackerShown(shown)settings().shown=shown==true;R.UpdateTracker();if N.Render and N.window and N.window:IsShown()then N.Render()end end
function R.ToggleTracker()R.SetTrackerShown(not R.TrackerShown())end
local placed=false
function R.UpdateTracker()
 local st=settings()
 if not placed then
  placed=true;tracker:ClearAllPoints()
  local p=st.point
  if type(p)=="table"and type(p[1])=="string"and type(p[3])=="number"and type(p[4])=="number"then tracker:SetPoint(p[1],UIParent,p[2]or p[1],p[3],p[4])
  else tracker:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-70,-260)end
 end
 local open={}
 if N.db then for _,req in ipairs(R.List())do if not R.Done(req)then open[#open+1]=req end end end
 if st.shown==false or #open==0 then tracker:Hide();return end
 heading:SetText("|cffd4af68GUILD NEEDS|r  ("..#open..")")
 collapse:SetText(st.collapsed and"+"or"-")
 local y=-24;local me=N.Me()
 for i,r in ipairs(trackerRows)do r:Hide()end
 if not st.collapsed then
  for i=1,math.min(#open,MAX_ROWS)do
   local req=open[i];local r=trackerRow(i);r.id=req.id
   local owner=N.members[req.owner]
   r.title:SetText("|cff"..N.ClassColor(owner)..N.Safe(short(req.owner)).."|r  "..(req.kind=="gold"and"|cffffd100"..R.Title(req).."|r"or R.Title(req))..(req.owner==me and"  |cff888888(you)|r"or""))
   for _,b in ipairs(r.icons)do b:Hide();b.id=nil end
   if req.kind=="gold"then
    local b=r.icons[1];b.tex:SetTexture(COIN);b.count:SetText("");b:Show()
    r.line:SetText("|cffffd100"..R.Remaining(req).."g|r"..(req.reason~=""and"  "..req.reason or""));r.line:Show()
   else
    r.line:Hide();local k=0
    for idx,it in ipairs(req.items)do
     local left=R.Remaining(req,idx)
     if left>0 then
      k=k+1;local b=r.icons[k];b.id=it.id;b.left=left
      b.tex:SetTexture(R.ItemIcon(it.id));b.count:SetText(left)
      -- Green count: you carry some of this item.
      if R.Have(it.id)>0 then b.count:SetTextColor(0.3,1,0.3)else b.count:SetTextColor(1,1,1)end
      b:Show()
     end
    end
   end
   r:ClearAllPoints();r:SetPoint("TOPLEFT",8,y);r:SetHeight(40);r:Show()
   y=y-42
  end
 end
 local more=st.collapsed and 0 or #open-MAX_ROWS
 footer:ClearAllPoints();footer:SetPoint("TOPLEFT",8,y-2)
 footer:SetText(more>0 and"+"..more.." more - type /zd and open Requests"or"")
 footer:SetShown(more>0)
 tracker:SetHeight(-y+(more>0 and 20 or 6))
 tracker:Show()
end

local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_GUILD_UPDATE","GUILD_ROSTER_UPDATE","BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED"})do pcall(events.RegisterEvent,events,event)end
local dirty=false
events:SetScript("OnEvent",function(_,event)
 if event=="PLAYER_LOGIN"then
  C_Timer.After(12,function()
   if N.db and IsInGuild()then N.Send("NQ");announceMine()end
   R.UpdateTracker()
  end)
 end
 dirty=true
end)
local wait=0
events:SetScript("OnUpdate",function(_,dt)
 wait=wait+dt;if wait<1 then return end;wait=0
 if dirty then dirty=false;R.UpdateTracker()
  if form:IsShown()then form.refresh()end
  -- Item names load from the server after the page first draws.
  if N.page=="Requests"and N.window and N.window:IsShown()and N.Render then N.Render()end
 end
end)
