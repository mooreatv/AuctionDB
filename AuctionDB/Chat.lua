-- "!ahdb <item>" (link, itemID or name) in guild, officer, party, raid or instance chat, from anyone else: answered
-- on the same channel with the item's last AH prices, its 30 day min - median and its vendor price (option "Answer
-- !ahdb in chat"). Part of a name that matches several items gets the list of their names ("which ...").
-- With several AHDB users there, one answers: they tell each other (addon messages on the party / raid / guild
-- channel, when joining a group, at login and after each scan) when they last scanned each AH. The one with the most
-- recent scan (not the one asking) answers right away; the others only after FALLBACK s if no answer came (it may
-- have left, or have no price for that item). Lists of partial matches come last (PARTIAL s): someone else may have
-- the exact item. The first answer in the channel answers the request.
local _, ADB = ...

local CHANNELS = {
  CHAT_MSG_GUILD = "GUILD",
  CHAT_MSG_OFFICER = "OFFICER",
  CHAT_MSG_PARTY = "PARTY",
  CHAT_MSG_PARTY_LEADER = "PARTY",
  CHAT_MSG_RAID = "RAID",
  CHAT_MSG_RAID_LEADER = "RAID",
  CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
  CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT"
}
local ANSWER = "AHDB " -- our answers start with it, which is also how we see other AHDB users' answers
local NONE = ANSWER .. "no " -- "no price" answers: not an answer for the others (they answer if they have prices)
local AGAIN = 60 -- seconds before answering about the same item on the same channel again
local GAP = 3 -- seconds between two of our answers
local FALLBACK = 3 -- seconds the others wait for the AHDB user with the most recent scan to answer
local PARTIAL = 6 -- seconds an AHDB user with only a list of partial matches waits for an exact answer
local REQUEST_LIFE = 15 -- seconds an unanswered request can still get an answer
local NOTHING = 9 -- seconds before the AHDB user with the most recent scan says it has no price, when no one answered
local MIN_SEARCH = 3 -- characters for a search by part of the name ("!ahdb cloth")
local MAX_MESSAGE = 255 -- chat message length

local answered = {} -- channel:itemID -> GetTime() of the last answer (ours or another AHDB user's)
local requests = {} -- channel -> {t, done} of the !ahdb requests there not answered yet, oldest first
local lastAnswer = -GAP
local echo = {} -- channel -> answer we sent, until it shows in that channel
local users = {group = {}, guild = {}} -- other AHDB users heard from: name -> {house -> last scan ts}

local function scope(channel) return (channel == "GUILD" or channel == "OFFICER") and "guild" or "group" end

-- Item named in the request: link, itemID, or name (of an item the client knows, or one of our price history).
-- done(itemID) for an exact match, else done(nil, matches): {id, name} of the items of our price history whose name
-- contains the text (MIN_SEARCH characters or more). A single partial match is still only a match: "Black Silk Pack"
-- may be missing from our history while "Pattern: Black Silk Pack" is there.
local function findItem(self, text, done)
  local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$")) or
               self:ItemIDFromLink(select(2, C_Item.GetItemInfo(text)))
  if id then return done(id) end
  local name = text:lower()
  local ids, missing, matches, seen = {}, {}, {}, {}
  for _, h in pairs(self.sv.houses) do
    for item in pairs(h.items) do ids[item] = true end
    for item in pairs(h.daily) do ids[item] = true end
  end
  -- true: exact match, nil: item not loaded yet
  local function look(item)
    local n = C_Item.GetItemInfo(item)
    if not n then return end
    local l = n:lower()
    if l == name then return true end
    if #name >= MIN_SEARCH and not seen[l] and l:find(name, 1, true) then
      seen[l] = true
      matches[#matches + 1] = {id = item, name = n}
    end
    return false
  end
  for item in pairs(ids) do
    local r = look(item)
    if r then return done(item) end
    if r == nil then missing[item] = true end
  end
  -- items the client hasn't loaded yet: load them, then look again
  self:LoadItems(missing, function()
    for item in pairs(missing) do if look(item) then return done(item) end end
    done(nil, matches)
  end, 3)
end

-- "AHDB which "cloth": [Silk Cloth], [Wool Cloth], Linen Cloth, ... (+3 more)": closest (shortest) names first, as
-- links while they fit (~60 characters each), then as names. Links are sent as the client makes them: one with its
-- empty trailing fields cut was not delivered.
local function which(query, matches)
  table.sort(matches, function(a, b)
    if #a.name ~= #b.name then return #a.name < #b.name end
    return a.name < b.name
  end)
  local msg, n, names = ('%swhich "%s":'):format(ANSWER, query), 0, false
  local room = MAX_MESSAGE - #" (+999 more)"
  for _, m in ipairs(matches) do
    local sep = n == 0 and " " or ", "
    local link = not names and select(2, C_Item.GetItemInfo(m.id))
    if link and #msg + #sep + #link <= room then
      msg = msg .. sep .. link
    elseif #msg + #sep + #m.name <= room then
      if not names then
        ADB:Debug("!ahdb: %s listed as a name: %s", m.name, link and ("link of %d characters, %d left"):format(#link,
                                                                                                         room - #msg) or
                    "no link")
      end
      names = true
      msg = msg .. sep .. m.name
    else
      break
    end
    n = n + 1
  end
  if n < #matches then msg = msg .. (" (+%d more)"):format(#matches - n) end
  return msg
end

-- Our faction's AH prices, else the neutral one's: house, {ts, min, median, qty}.
local function prices(self, id)
  for _, house in ipairs({self:PlayerHouse(), "Neutral"}) do
    local p = self:LastPrice(id, house)
    if p then return house, p end
  end
end

-- No "|" (chat escape) in what we send: "; " between the parts.
local function answer(self, id)
  local house, p = prices(self, id)
  if not house then return end
  local link = select(2, C_Item.GetItemInfo(id)) or ("item " .. id)
  local parts = {
    ("%s%s %s AH %s ago: min %s, median %s, %d listed"):format(ANSWER, link, house, self:Age(p[1]),
                                                               self:MoneyText(p[2]), self:MoneyText(p[3]), p[4])
  }
  local tmin, tmed, days = self:Typical(id, house)
  if days >= 3 then parts[#parts + 1] = ("30 days %s-%s"):format(self:MoneyText(tmin), self:MoneyText(tmed)) end
  local vp = self:SellablePrice(id)
  if vp then parts[#parts + 1] = "vendor " .. self:MoneyText(vp) end
  return table.concat(parts, "; ")
end

local function recent(key) return answered[key] and GetTime() - answered[key] < AGAIN end

local function lastScan(self, house)
  local h = self.sv.houses[house]
  local s = h and h.scans[#h.scans]
  return s and s[1] or 0
end

-- The AHDB user expected to answer about that AH on that channel: the most recent scan, the asker excluded.
local function freshest(self, house, channel, asker)
  local best, bestTs = self.myName, lastScan(self, house)
  for name, scans in pairs(users[scope(channel)]) do
    local ts = scans[house] or 0
    if name ~= asker and (ts > bestTs or (ts == bestTs and name < best)) then best, bestTs = name, ts end
  end
  return best
end

local function newRequest(channel)
  local list = requests[channel] or {}
  requests[channel] = list
  local req = {t = GetTime()}
  list[#list + 1] = req
  return req
end

local function oldestRequest(channel)
  local list = requests[channel]
  if not list then return end
  while list[1] and GetTime() - list[1].t > REQUEST_LIFE do table.remove(list, 1) end
  return list[1], list
end

-- An AHDB answer in the channel answers the oldest request still open there, whatever the item it names; a "no
-- price" one only stops the others from saying it too.
local function requestAnswered(channel, none)
  local req, list = oldestRequest(channel)
  if not req then return end
  if none then
    req.none = true
    return
  end
  table.remove(list, 1).done = true
end

-- Answers the request unless someone else does first: key (channel:what) against answering the same twice in a
-- row, house whose most recent scan answers first, what for the debug log, exact: an item (else a list of partial
-- matches, answered last), build(send) makes the message.
-- Sends the answer and checks it shows in the channel (a message the server refuses just doesn't).
local function say(self, channel, msg, what)
  echo[channel] = msg
  self:Debug("!ahdb: sending in %s: %s", channel, (msg:gsub("|c%x+|H(item:%d+)[^|]*|h(%b[])|h|r", "<link %1 %2>")))
  C_ChatInfo.SendChatMessage(msg, channel)
  C_Timer.After(5, function()
    if echo[channel] ~= msg then return end
    echo[channel] = nil
    self:Debug("!ahdb: our answer about %s didn't show in %s (not delivered): %s", what, channel, msg)
  end)
end

local function respond(self, req, channel, sender, key, house, what, exact, build)
  if recent(key) then
    self:Debug("!ahdb from %s in %s: %s answered less than %ds ago", sender, channel, what, AGAIN)
    return
  end
  local delay
  if not exact then
    delay = PARTIAL + math.random() * 2
    self:Debug("!ahdb from %s in %s: %s, answering in %.1fs if no exact answer comes", sender, channel, what, delay)
  else
    local best = freshest(self, house, channel, sender)
    if best == self.myName then
      delay = 0.2 + math.random() * 0.3
      self:Debug("!ahdb from %s in %s: %s, most recent %s AH scan: answering", sender, channel, what, house)
    else
      delay = FALLBACK + math.random() * 2
      self:Debug("!ahdb from %s in %s: %s, %s has a more recent %s AH scan: answering in %.1fs if it doesn't", sender,
                 channel, what, best, house, delay)
    end
  end
  C_Timer.After(delay, function()
    if req.done or recent(key) then
      self:Debug("!ahdb: %s already answered in %s, not answering", what, channel)
      return
    end
    if GetTime() - lastAnswer < GAP then
      self:Debug("!ahdb: answered something less than %ds ago, not answering", GAP)
      return
    end
    answered[key] = GetTime()
    lastAnswer = GetTime()
    build(function(msg) if msg then say(self, channel, msg, what) end end)
  end)
end

-- Nobody had a price (or an item by that name): the AHDB user with the most recent scan says so, if still no answer
-- after NOTHING s. msg says what wasn't found.
local function noPrice(self, req, channel, sender, what, msg)
  local house = self:PlayerHouse()
  if freshest(self, house, channel, sender) ~= self.myName then
    self:Debug("!ahdb from %s in %s: %s: nothing here", sender, channel, what)
    return
  end
  self:Debug("!ahdb from %s in %s: %s: nothing here either, saying so in %ds if nobody answers", sender, channel, what,
             NOTHING)
  C_Timer.After(NOTHING, function()
    if req.done or req.none then return end
    local scan = lastScan(self, house)
    say(self, channel,
        ("%s (last %s AH scan %s)"):format(msg, house, scan > 0 and (self:Age(scan) .. " ago") or "never"), what)
  end)
end

local function onChat(self, channel, text, sender)
  if text:sub(1, #ANSWER) == ANSWER then
    if sender == self.myName then echo[channel] = nil end
    if text:sub(1, #NONE) == NONE then
      requestAnswered(channel, true)
      return
    end
    requestAnswered(channel)
    -- a list of matches only answers that request: an item asked for next still gets its prices
    local query = text:match('^' .. ANSWER .. 'which "(.-)":')
    local id = not query and tonumber(text:match("|Hitem:(%d+)"))
    if query then answered[channel .. ":q:" .. query:lower()] = GetTime() end
    if id then answered[channel .. ":" .. id] = GetTime() end
    if id or query then self:Debug("!ahdb: %s answered about %s in %s", sender, id or query, channel) end
    return
  end
  local cmd, rest = text:match("^(%S+)%s+(.-)%s*$")
  if not cmd or cmd:lower() ~= "!ahdb" then return end
  local req = newRequest(channel) -- also ours, and with answers off: to match the answers to the requests
  if not self.db.chatAnswers or sender == self.myName then return end
  findItem(self, rest, function(id, matches)
    if id then
      local house = prices(self, id)
      if not house then
        local link = select(2, C_Item.GetItemInfo(id)) or ("item " .. id)
        noPrice(self, req, channel, sender, "item " .. id, ("%sno price for %s"):format(ANSWER, link))
        return
      end
      respond(self, req, channel, sender, channel .. ":" .. id, house, "item " .. id, true,
              function(send) self:LoadItems({[id] = true}, function() send(answer(self, id)) end, 2) end)
    elseif #matches > 0 then
      local query = rest:gsub("[|\"]", "")
      respond(self, req, channel, sender, channel .. ":q:" .. query:lower(), self:PlayerHouse(),
              ('"%s" (%d partial matches)'):format(query, #matches), false,
              function(send) send(which(query, matches)) end)
    else
      local name = rest:gsub("[|\"]", "")
      noPrice(self, req, channel, sender, ('"%s"'):format(name), ('%sno item named "%s"'):format(ANSWER, name))
    end
  end)
end

for event, channel in pairs(CHANNELS) do
  ADB:On(event, function(self, text, sender) onChat(self, channel, text, sender) end)
end

-- How AHDB answers look in our chat window: colors and coin icons (chat messages can't carry them: everyone else sees
-- the plain text that was sent).
local function coins(text)
  local copper = ADB:ParseMoney(text)
  return copper and ("|cffffffff" .. ADB:Money(copper) .. "|r") or text
end

local function pretty(msg)
  msg = msg:gsub("^" .. ANSWER, "|cff99e5ffAHDB|r ")
  msg = msg:gsub(" (%a+ AH) (%S+ ago):", " |cffffd100%1|r |cffa0a0a0%2|r:")
  msg = msg:gsub("(median) ([%dgsc]+)", function(l, v) return l .. " " .. coins(v) end)
  msg = msg:gsub("(min) ([%dgsc]+)", function(l, v) return l .. " " .. coins(v) end)
  msg = msg:gsub("(vendor) ([%dgsc]+)", function(l, v) return l .. " " .. coins(v) end)
  msg = msg:gsub("(30 days) ([%dgsc]+)%-([%dgsc]+)",
                 function(l, a, b) return l .. " " .. coins(a) .. " - " .. coins(b) end)
  msg = msg:gsub("(%d+) listed", "|cffffffff%1|r listed")
  return msg
end

ADB:Listen("LOGIN", function()
  for event in pairs(CHANNELS) do
    ChatFrameUtil.AddMessageEventFilter(event, function(_, _, msg, ...)
      if msg:sub(1, #ANSWER) == ANSWER then return false, pretty(msg), ... end
    end)
  end
end)

-- Scan times of the AHDB users of the group and guild. Payload: Comm.lua's presence ("<open AH>,<A>,<H>,<N>").

local lastTold = {} -- channel -> GetTime()

-- ask: they answer with theirs (when we join a group, at login)
local function tell(self, channel, ask)
  if not channel or (not ask and lastTold[channel] and GetTime() - lastTold[channel] < 2) then return end
  lastTold[channel] = GetTime()
  local p = self:Presence()
  self:SendGroup(channel, ask and "G" or "g", p, "scan times " .. p)
end

local function groupChannel() return IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil) end

local function heard(_, sender, channel, payload)
  local a, h, n = payload:match("^[^,]+,(%d+),(%d+),(%d+)$")
  if not a then return end
  users[scope(channel)][sender] = {Alliance = tonumber(a), Horde = tonumber(h), Neutral = tonumber(n)}
end

ADB:OnGroupMessage("G", function(self, sender, channel, payload)
  heard(self, sender, channel, payload)
  tell(self, channel)
end)
ADB:OnGroupMessage("g", heard)

local inGroup = false

ADB:Listen("LOGIN", function(self)
  inGroup = IsInGroup()
  C_Timer.After(5, function()
    tell(self, groupChannel(), true)
    if IsInGuild() then tell(self, "GUILD", true) end
  end)
end)

ADB:Listen("SCAN_DATA", function(self)
  tell(self, groupChannel())
  if IsInGuild() then tell(self, "GUILD") end
end)

-- Joining a group: ask its AHDB users; leaving it: forget them.
ADB:On("GROUP_ROSTER_UPDATE", function(self)
  local now = IsInGroup()
  if now and not inGroup then tell(self, groupChannel(), true) end
  if not now then wipe(users.group) end
  inGroup = now
end)
