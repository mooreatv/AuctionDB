-- "!ahdb <item>" (link, itemID or name) in guild, officer, party, raid or instance chat, from anyone else: answered
-- on the same channel with the item's last AH prices, its 30 day min - median and its vendor price (option "Answer
-- !ahdb in chat").
-- With several AHDB users there, one answers: they tell each other (addon messages on the party / raid / guild
-- channel, when joining a group, at login and after each scan) when they last scanned each AH. The one with the most
-- recent scan (not the one asking) answers right away; the others only after FALLBACK s if no answer came (it may
-- have left, or have no price for that item).
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
local AGAIN = 60 -- seconds before answering about the same item on the same channel again
local GAP = 3 -- seconds between two of our answers
local FALLBACK = 3 -- seconds the others wait for the AHDB user with the most recent scan to answer

local answered = {} -- channel:itemID -> GetTime() of the last answer (ours or another AHDB user's)
local lastAnswer = 0
local users = {group = {}, guild = {}} -- other AHDB users heard from: name -> {house -> last scan ts}

local function scope(channel) return (channel == "GUILD" or channel == "OFFICER") and "guild" or "group" end

-- Item named in the request: link, itemID, or name (of an item the client knows, or one of our price history).
local function findItem(self, text, done)
  local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$")) or
               self:ItemIDFromLink(select(2, C_Item.GetItemInfo(text)))
  if id then return done(id) end
  local name = text:lower()
  local ids, missing = {}, {}
  for _, h in pairs(self.sv.houses) do
    for item in pairs(h.items) do ids[item] = true end
    for item in pairs(h.daily) do ids[item] = true end
  end
  for item in pairs(ids) do
    local n = C_Item.GetItemInfo(item)
    if not n then
      missing[item] = true
    elseif n:lower() == name then
      return done(item)
    end
  end
  -- items the client hasn't loaded yet: load them, then look again
  self:LoadItems(missing, function()
    for item in pairs(missing) do
      local n = C_Item.GetItemInfo(item)
      if n and n:lower() == name then return done(item) end
    end
    done()
  end, 3)
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

local function onChat(self, channel, text, sender)
  if text:sub(1, #ANSWER) == ANSWER then
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if id then
      answered[channel .. ":" .. id] = GetTime()
      self:Debug("!ahdb: %s answered about item %d in %s", sender, id, channel)
    end
    return
  end
  local cmd, rest = text:match("^(%S+)%s+(.-)%s*$")
  if not cmd or cmd:lower() ~= "!ahdb" or not self.db.chatAnswers or sender == self.myName then return end
  findItem(self, rest, function(id)
    if not id then
      self:Debug("!ahdb from %s in %s: unknown item %q", sender, channel, rest)
      return
    end
    local key = channel .. ":" .. id
    local house = prices(self, id)
    if not house then
      self:Debug("!ahdb from %s in %s: no price for item %d", sender, channel, id)
      return
    end
    if recent(key) then
      self:Debug("!ahdb from %s in %s: item %d answered less than %ds ago", sender, channel, id, AGAIN)
      return
    end
    local best = freshest(self, house, channel, sender)
    local delay
    if best == self.myName then
      delay = 0.2 + math.random() * 0.3
      self:Debug("!ahdb from %s in %s: item %d, most recent %s AH scan: answering", sender, channel, id, house)
    else
      delay = FALLBACK + math.random() * 2
      self:Debug("!ahdb from %s in %s: item %d, %s has a more recent %s AH scan: answering in %.1fs if it doesn't",
                 sender, channel, id, best, house, delay)
    end
    C_Timer.After(delay, function()
      if recent(key) then
        self:Debug("!ahdb: item %d already answered in %s, not answering", id, channel)
        return
      end
      if GetTime() - lastAnswer < GAP then
        self:Debug("!ahdb: answered something less than %ds ago, not answering", GAP)
        return
      end
      answered[key] = GetTime()
      lastAnswer = GetTime()
      self:LoadItems({[id] = true}, function()
        local msg = answer(self, id)
        if msg then C_ChatInfo.SendChatMessage(msg, channel) end
      end, 2)
    end)
  end)
end

for event, channel in pairs(CHANNELS) do
  ADB:On(event, function(self, text, sender) onChat(self, channel, text, sender) end)
end

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
