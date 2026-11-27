local _,N=...
-- Mailbox side of guild requests: a Guild Needs button on the mail window that
-- fills in a request's mail and attaches the mats from your bags. The player
-- still presses Blizzard's Send; a successful send is reported to the guild.
local R=N.Needs
local Cn=C_Container
local MAX_ROWS=8
local ROW_HEIGHT=46
local COIN="Interface\\Icons\\INV_Misc_Coin_01"

local function short(name)return R.Short(name)end
local function bags()return 0,(NUM_BAG_SLOTS or 4)end
local function numSlots(bag)
 local fn=Cn and Cn.GetContainerNumSlots or GetContainerNumSlots
 return fn and fn(bag)or 0
end
local function slotInfo(bag,slot)
 if Cn and Cn.GetContainerItemInfo then
  local info=Cn.GetContainerItemInfo(bag,slot)
  if info then return info.itemID,info.stackCount,info.isLocked end
  return
 end
 if not GetContainerItemInfo then return end
 local _,count,locked,_,_,_,link,_,_,id=GetContainerItemInfo(bag,slot)
 return id or(link and tonumber(link:match("item:(%d+)"))),count,locked
end
local function inBags(id)
 local total=0;local first,last=bags()
 for bag=first,last do for slot=1,numSlots(bag)do
  local itemID,count=slotInfo(bag,slot)
  if itemID==id then total=total+(count or 1)end
 end end
 return total
end
local function unlockedStack(id)
 local first,last=bags()
 for bag=first,last do for slot=1,numSlots(bag)do
  local itemID,count,locked=slotInfo(bag,slot)
  if itemID==id and not locked then return bag,slot,count or 1 end
 end end
end
local function maxAttachments()return ATTACHMENTS_MAX_SEND or 12 end
local function freeAttachment()
 for i=1,maxAttachments()do if not GetSendMailItem(i)then return i end end
end
local function mailOpen()return _G.MailFrame and _G.MailFrame:IsShown()end
-- Requests from others that still need something.
local function openRequests()
 local list,me={},N.Me()
 for _,req in ipairs(R.List())do if req.owner~=me and not R.Done(req)then list[#list+1]=req end end
 return list
end
-- What you can send from your bags for this request.
local function canGive(req)
 if req.kind=="gold"then return math.min(R.Remaining(req),math.floor((GetMoney and GetMoney()or 0)/10000))end
 local total=0
 for i,it in ipairs(req.items)do total=total+math.min(R.Remaining(req,i),inBags(it.id))end
 return total
end

-- Attaching runs one stack per step so each item lock settles first.
local plan
local function attachNext()
 if not plan then return end
 if not(_G.SendMailFrame and _G.SendMailFrame:IsVisible())then plan=nil;return end
 local step=plan.steps[1]
 if not step then
  local who=plan.who;plan=nil
  N.Notify("Mail to "..N.Safe(who).." is ready. Check it and press Send.")
  return
 end
 local slotIndex=freeAttachment()
 if not slotIndex then
  plan=nil
  N.Notify("This mail is full ("..maxAttachments().." attachments). Send it, then click Fill again for the rest.")
  return
 end
 local bag,slot,count=unlockedStack(step.id)
 if not bag or step.left<=0 then table.remove(plan.steps,1);C_Timer.After(0.1,attachNext);return end
 local take=math.min(step.left,count)
 if CursorHasItem and CursorHasItem()then ClearCursor()end
 local ok=pcall(function()
  if take<count then(Cn and Cn.SplitContainerItem or SplitContainerItem)(bag,slot,take)
  else(Cn and Cn.PickupContainerItem or PickupContainerItem)(bag,slot)end
  ClickSendMailItemButton(slotIndex)
 end)
 if not ok then
  plan=nil;ClearCursor()
  N.Notify("WoW did not let the addon attach items here. Drag the mats into the mail yourself.")
  return
 end
 step.left=step.left-take
 if step.left<=0 then table.remove(plan.steps,1)end
 C_Timer.After(0.35,attachNext)
end

function R.FillMail(req)
 if not mailOpen()then N.Notify("Open a mailbox first, then click this again.");return false end
 if req.owner==N.Me()then return false end
 if _G.MailFrameTab2 and not(_G.SendMailFrame and _G.SendMailFrame:IsVisible())then _G.MailFrameTab2:Click()end
 if not(_G.SendMailFrame and _G.SendMailFrame:IsVisible())then N.Notify("Open the Send Mail tab, then click this again.");return false end
 for i=1,maxAttachments()do if GetSendMailItem(i)then pcall(ClickSendMailItemButton,i,true)end end
 if _G.SendMailNameEditBox then _G.SendMailNameEditBox:SetText(short(req.owner))end
 if _G.SendMailSubjectEditBox then
  _G.SendMailSubjectEditBox:SetText(req.prof==R.BANK and R.Title(req).." from ZERO DRAMA"or(req.kind=="gold"and"Gold from ZERO DRAMA"or req.prof.." mats from ZERO DRAMA"))
 end
 if _G.SendMailBodyEditBox then
  _G.SendMailBodyEditBox:SetText("For your request"..(req.reason~=""and": "..req.reason or"")..". From "..N.Safe(short(N.Me())).." via ZERO DRAMA Guild Needs.")
 end
 local who=short(req.owner)
 if req.kind=="gold"then
  local amount=canGive(req)
  if amount<1 then N.Notify("You do not have any gold to send.");return false end
  if _G.SendMailSendMoneyButton and _G.SendMailSendMoneyButton.Click then _G.SendMailSendMoneyButton:Click()end
  if MoneyInputFrame_SetCopper and _G.SendMailMoney then MoneyInputFrame_SetCopper(_G.SendMailMoney,amount*10000)end
  N.Notify("Mail to "..N.Safe(who).." has "..amount.." gold filled in. Change the amount if you like, then press Send.")
  return true
 end
 local steps,short_={},{}
 for i,it in ipairs(req.items)do
  local left=R.Remaining(req,i);local have=inBags(it.id)
  if left>0 and have>0 then steps[#steps+1]={id=it.id,left=math.min(left,have)}end
  if left>have then short_[#short_+1]=(left-have).."x "..R.ItemName(it.id)end
 end
 if #steps==0 then N.Notify("You have none of the mats "..N.Safe(who).." needs in your bags.");return false end
 if #short_>0 then N.Notify("Not in your bags: "..table.concat(short_,", ")..".")end
 plan={who=who,steps=steps}
 C_Timer.After(0.1,attachNext)
 return true
end

-- Capture the mail at the moment Blizzard sends it; report after the server confirms.
local sending
local function snapshot(recipient)
 sending=nil
 if type(recipient)~="string"or recipient==""then return end
 local items={}
 for i=1,maxAttachments()do
  local link=GetSendMailItemLink and GetSendMailItemLink(i)
  local id=link and tonumber(link:match("item:(%d+)"))
  if id then
   local _,_,_,count=GetSendMailItem(i)
   items[id]=(items[id]or 0)+(tonumber(count)or 1)
  end
 end
 local cod=_G.SendMailCODButton and _G.SendMailCODButton.GetChecked and _G.SendMailCODButton:GetChecked()
 local money=(not cod and GetSendMailMoney and GetSendMailMoney())or 0
 sending={to=recipient:gsub("%-.*",""):lower(),items=items,gold=math.floor(money/10000)}
end
if type(SendMail)=="function"then hooksecurefunc("SendMail",snapshot)end
local function record(sent)
 local parts={};local owner
 for _,req in ipairs(R.List())do
  if short(req.owner):lower()==sent.to and req.owner~=N.Me()then
   if req.kind=="gold"and sent.gold>0 then
    local give=math.min(sent.gold,R.Remaining(req))
    if give>0 and R.Give(req.id,0,give)then sent.gold=sent.gold-give;parts[#parts+1]=give.."g";owner=req.owner end
   elseif req.kind=="mats"then
    for i,it in ipairs(req.items)do
     local give=math.min(sent.items[it.id]or 0,R.Remaining(req,i))
     if give>0 and R.Give(req.id,i,give)then sent.items[it.id]=sent.items[it.id]-give;parts[#parts+1]=give.."x "..R.ItemName(it.id);owner=req.owner end
    end
   end
  end
 end
 if owner then N.Notify("Recorded for "..N.Safe(short(owner)).."'s request: "..table.concat(parts,", ")..". Thank you!")end
end

local button,panel
local rows={}
local function row(i)
 if rows[i]then return rows[i]end
 local r=CreateFrame("Frame",nil,panel);r:SetSize(276,ROW_HEIGHT-2)
 r.shade=r:CreateTexture(nil,"BACKGROUND");r.shade:SetAllPoints();r.shade:SetColorTexture(1,1,1,i%2==0 and 0.05 or 0.02)
 r.icon=r:CreateTexture(nil,"ARTWORK");r.icon:SetSize(30,30);r.icon:SetPoint("LEFT",4,0)
 r.title=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");r.title:SetPoint("TOPLEFT",40,-5);r.title:SetWidth(160);r.title:SetJustifyH("LEFT");r.title:SetWordWrap(false)
 r.line=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.line:SetPoint("TOPLEFT",40,-21);r.line:SetWidth(160);r.line:SetJustifyH("LEFT");r.line:SetWordWrap(false)
 r.fill=CreateFrame("Button",nil,r,"UIPanelButtonTemplate");r.fill:SetSize(66,22);r.fill:SetPoint("RIGHT",-4,0);r.fill:SetText("Fill")
 r.fill:SetScript("OnClick",function()local req=r.req;if req then R.FillMail(req)end end)
 r:EnableMouse(true)
 r:SetScript("OnEnter",function(self)
  local req=self.req;if not req then return end
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(N.Safe(short(req.owner)).." - "..R.Title(req),1,0.82,0)
  if req.reason~=""then GameTooltip:AddLine("\""..req.reason.."\"",1,1,1,true)end
  if req.kind=="gold"then GameTooltip:AddLine(R.Remaining(req).."g still needed",1,1,1)
  else
   for idx,it in ipairs(req.items)do
    local left=R.Remaining(req,idx)
    if left>0 then
     local have=inBags(it.id)
     GameTooltip:AddDoubleLine(R.ItemName(it.id).." x"..left,have>0 and"you have "..have or"none in bags",1,1,1,have>0 and 0.3 or 0.6,have>0 and 1 or 0.6,have>0 and 0.3 or 0.6)
    end
   end
  end
  GameTooltip:Show()
 end)
 r:SetScript("OnLeave",function()GameTooltip:Hide()end)
 rows[i]=r
 return r
end
function R.UpdateMailPanel()
 if not button then return end
 local list=openRequests()
 button:SetText("Guild Needs ("..#list..")")
 button:SetShown(N.db~=nil)
 if not panel:IsShown()then return end
 for _,r in ipairs(rows)do r:Hide()end
 local y=-34
 for i=1,math.min(#list,MAX_ROWS)do
  local req=list[i];local r=row(i);r.req=req
  local owner=N.members[req.owner]
  r.title:SetText("|cff"..N.ClassColor(owner)..N.Safe(short(req.owner)).."|r  "..(req.kind=="gold"and"|cffffd100"..R.Title(req).."|r"or R.Title(req)))
  local give=canGive(req)
  if req.kind=="gold"then
   r.icon:SetTexture(COIN);r.line:SetText(R.Remaining(req).."g"..(req.reason~=""and" - "..req.reason or""))
  else
   r.icon:SetTexture(R.ItemIcon(req.items[1].id));r.line:SetText(R.Summary(req,2))
  end
  r.fill:SetEnabled(give>0)
  r.fill:SetText(give>0 and"Fill"or(req.kind=="gold"and"No gold"or"No mats"))
  r:ClearAllPoints();r:SetPoint("TOPLEFT",10,y);r:Show()
  y=y-ROW_HEIGHT
 end
 panel.empty:SetShown(#list==0)
 panel.more:SetShown(#list>MAX_ROWS)
 panel.more:SetText("+"..math.max(0,#list-MAX_ROWS).." more in the Requests tab (/zd)")
 panel.more:ClearAllPoints();panel.more:SetPoint("TOPLEFT",12,y-4)
 panel:SetHeight(math.max(110,-y+(#list>MAX_ROWS and 28 or 12)))
end
local function build()
 if button or not _G.MailFrame then return end
 button=CreateFrame("Button","NoDramaMailNeedsButton",_G.MailFrame,"UIPanelButtonTemplate")
 button:SetSize(140,22);button:SetPoint("BOTTOMRIGHT",_G.MailFrame,"TOPRIGHT",-28,2);button:SetFrameStrata("HIGH")
 panel=CreateFrame("Frame","NoDramaMailNeedsPanel",_G.MailFrame,"BackdropTemplate")
 panel:SetWidth(296);panel:SetPoint("TOPLEFT",_G.MailFrame,"TOPRIGHT",4,0);panel:EnableMouse(true);panel:Hide()
 panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=32,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 panel:SetBackdropBorderColor(0.62,0.45,0.24,1)
 local heading=panel:CreateFontString(nil,"OVERLAY","GameFontNormal");heading:SetPoint("TOPLEFT",12,-11);heading:SetText("|cffd4af68GUILD NEEDS|r")
 local hint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");hint:SetPoint("TOPRIGHT",-28,-13);hint:SetText("Fill, then press Send")
 local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton");close:SetSize(22,22);close:SetPoint("TOPRIGHT",-2,-3)
 close:SetScript("OnClick",function()panel:Hide();R.Settings().mailPanel=false end)
 panel.empty=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");panel.empty:SetPoint("TOPLEFT",12,-40);panel.empty:SetWidth(270);panel.empty:SetJustifyH("LEFT")
 panel.empty:SetText("No guild member needs anything right now.")
 panel.more=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");panel.more:SetWidth(270);panel.more:SetJustifyH("LEFT")
 button:SetScript("OnClick",function()
  local show=not panel:IsShown();panel:SetShown(show);R.Settings().mailPanel=show;R.UpdateMailPanel()
 end)
end

local events=CreateFrame("Frame")
for _,event in ipairs({"MAIL_SHOW","MAIL_CLOSED","MAIL_SEND_SUCCESS","MAIL_FAILED","BAG_UPDATE_DELAYED","PLAYER_MONEY"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event)
 if event=="MAIL_SHOW"then
  build()
  if panel then panel:SetShown(R.Settings().mailPanel~=false)end
  R.UpdateMailPanel()
 elseif event=="MAIL_CLOSED"then plan=nil;sending=nil
 elseif event=="MAIL_SEND_SUCCESS"then
  if sending then local sent=sending;sending=nil;record(sent)end
  R.UpdateMailPanel()
 elseif event=="MAIL_FAILED"then sending=nil
 elseif mailOpen()then R.UpdateMailPanel()end
end)
