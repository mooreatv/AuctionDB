-- "!ahdb <item>" (link, itemID or name) in guild, officer, party, raid or instance chat, from anyone (us too): answered
-- on the same channel with the item's last AH prices, its 30 day min - median and its vendor price (option "Answer
-- !ahdb in chat"). With several AHDB users there, one answers: each waits a moment (less with fresher prices) and
-- stays quiet when another answer about the item came first.
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

local answered = {} -- channel:itemID -> GetTime() of the last answer (ours or another AHDB user's)
local lastAnswer = 0

local function itemFrom(text)
  local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$"))
  if id then return id end
  return ADB:ItemIDFromLink(select(2, C_Item.GetItemInfo(text))) -- by name, when the client knows the item
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
  if not cmd or cmd:lower() ~= "!ahdb" or not self.db.chatAnswers then return end
  local id = itemFrom(rest)
  if not id then
    self:Debug("!ahdb from %s in %s: unknown item %q", sender, channel, rest)
    return
  end
  local key = channel .. ":" .. id
  local _, p = prices(self, id)
  if not p then
    self:Debug("!ahdb from %s in %s: no price for item %d", sender, channel, id)
    return
  end
  if recent(key) then
    self:Debug("!ahdb from %s in %s: item %d answered less than %ds ago", sender, channel, id, AGAIN)
    return
  end
  -- fresher prices answer sooner: 0.3s to 2.3s, plus up to 0.7s at random
  local delay = 0.3 + math.min(2, (GetServerTime() - p[1]) / 3600 * 0.2) + math.random() * 0.7
  self:Debug("!ahdb from %s in %s: item %d, answering in %.1fs unless another AHDB does", sender, channel, id, delay)
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
end

for event, channel in pairs(CHANNELS) do
  ADB:On(event, function(self, text, sender) onChat(self, channel, text, sender) end)
end
