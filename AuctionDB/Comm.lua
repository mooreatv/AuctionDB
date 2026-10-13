-- Sharing prices with characters of your other WoW accounts (/ahdb trust <First Last>, on both sides): AHDB addon
-- messages whispered by full name (works ungrouped and across home realms; whispers can be late). Only trusted names
-- are listened to and answered: whisper senders are set by the server, so no signing is needed.
-- Message: "<type>;<id>;<part>/<parts>;<payload>", payloads longer than PART bytes are split in parts.
-- - I / i presence (I asks for one back): "<open AH house or ->,<last scan ts of Alliance>,<Horde>,<Neutral>"
-- - Q history query "<itemID>,<house>,<since ts>,<daily 0/1>": scans newer than since (and the daily entries),
--   answered with H "<recent>/<daily>" (wire format, History.lua), merged into our history
-- - L live AH search (Live.lua)
local _, ADB = ...

local PREFIX = "AHDB"
local SPACING = 0.25 -- seconds between our messages (addon messages are throttled)
local PART = 230 -- payload bytes per message (255 max)
local TIMEOUT = 60 -- seconds before giving up on an answer
local ASK_AGAIN = 600 -- seconds before asking again about the same item (tooltip)
local MAX_PENDING = 3 -- tooltip queries waiting for an answer
local HOUSES = {"Alliance", "Horde", "Neutral"}

ADB.peers = {} -- trusted characters heard from: full name -> {ah = open AH house, scans = {house -> last scan ts}}

local handlers = {}
local queue, sending = {}, false
local lastSent = {} -- name -> GetTime() of our last message to them
local partial = {} -- sender;type;id -> {parts, got, t}
local pending = {} -- query id -> {peer, id, house, full, t}
local asked = {} -- house:itemID[:f] -> GetTime()
local seq = math.random(1000)

function ADB:OnMessage(kind, fn) handlers[kind] = fn end

function ADB:NewMessageID()
  seq = seq + 1
  return self.B36(seq)
end

local function resultName(r)
  for k, v in pairs(Enum.SendAddonMessageResult) do if v == r then return k end end
  return tostring(r)
end

local function pump()
  local m = queue[1]
  if not m then
    sending = false
    return
  end
  local r = C_ChatInfo.SendAddonMessage(PREFIX, m[2], "WHISPER", m[1])
  if r == Enum.SendAddonMessageResult.AddonMessageThrottle then
    C_Timer.After(1, pump)
    return
  end
  table.remove(queue, 1)
  lastSent[m[1]] = GetTime()
  if r ~= Enum.SendAddonMessageResult.Success then ADB:Debug("message to %s not sent: %s", m[1], resultName(r)) end
  C_Timer.After(SPACING, pump)
end

function ADB:Send(to, kind, id, payload)
  local n = math.max(1, math.ceil(#payload / PART))
  for i = 1, n do
    queue[#queue + 1] = {to, ("%s;%s;%d/%d;%s"):format(kind, id, i, n, payload:sub((i - 1) * PART + 1, i * PART))}
  end
  self:Debug("to %s: %s %s (%d bytes, %d parts)", to, kind, id, #payload, n)
  if not sending then
    sending = true
    pump()
  end
end

ADB:On("CHAT_MSG_ADDON", function(self, prefix, text, _, sender)
  if prefix ~= PREFIX or not self.sv.trusted[sender] then return end
  local kind, id, i, n, payload = text:match("^(%a);([^;]*);(%d+)/(%d+);(.*)$")
  if not kind then return end
  i, n = tonumber(i), tonumber(n)
  local now = GetTime()
  if n > 1 then
    for k, p in pairs(partial) do if now - p.t > TIMEOUT then partial[k] = nil end end
    local key = sender .. ";" .. kind .. ";" .. id
    local p = partial[key]
    if not p then
      p = {parts = {}, got = 0, t = now}
      partial[key] = p
    end
    if not p.parts[i] then
      p.parts[i] = payload
      p.got = p.got + 1
    end
    if p.got < n then return end
    partial[key] = nil
    payload = table.concat(p.parts)
  end
  self.peers[sender] = self.peers[sender] or {scans = {}}
  local fn = handlers[kind]
  if fn then fn(self, sender, id, payload) end
end)

-- Presence

local function presence(self)
  local t = {self.house or "-"}
  for i, house in ipairs(HOUSES) do
    local h = self.sv.houses[house]
    local last = h and h.scans[#h.scans]
    t[i + 1] = last and last[1] or 0
  end
  return table.concat(t, ",")
end

-- ask: they answer with theirs (when we just logged in or trusted them)
function ADB:Announce(ask, to)
  local p = presence(self)
  for name in pairs(to and {[to] = true} or self.sv.trusted) do
    if name ~= self.myName then self:Send(name, ask and "I" or "i", "0", p) end
  end
end

local function heard(self, sender, payload)
  local ah, a, h, n = payload:match("^([^,]+),(%d+),(%d+),(%d+)$")
  if not ah then return end
  local peer = self.peers[sender]
  peer.ah = ah ~= "-" and ah or nil
  peer.scans = {Alliance = tonumber(a), Horde = tonumber(h), Neutral = tonumber(n)}
  self:Fire("PEERS_CHANGED")
end

ADB:OnMessage("I", function(self, sender, _, payload)
  heard(self, sender, payload)
  self:Announce(false, sender)
end)
ADB:OnMessage("i", heard)

-- An offline character: "No player named X is currently playing." for each message, hidden and the character
-- forgotten until it tells us it's back.
local function offline(self, name)
  self.peers[name] = nil
  for i = #queue, 1, -1 do if queue[i][1] == name then table.remove(queue, i) end end
  for qid, q in pairs(pending) do if q.peer == name then pending[qid] = nil end end
  self:Fire("PEERS_CHANGED")
end

ADB:Listen("LOGIN", function(self)
  self.myName = GetUnitName("player", true)
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    for name, t in pairs(lastSent) do
      if GetTime() - t < 10 and msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) then
        offline(ADB, name)
        return true
      end
    end
  end)
  C_Timer.After(3, function() self:Announce(true) end)
end)
ADB:Listen("SCAN_DATA", function(self) self:Announce(false) end)
ADB:Listen("AH_SHOW", function(self) self:Announce(false) end)
ADB:Listen("AH_CLOSED", function(self) self:Announce(false) end)

-- Price history queries

-- Online trusted character with the most recent scan of that house (newer than ts, if given).
function ADB:BestPeer(house, ts)
  local best, bestTs
  for name, p in pairs(self.peers) do
    local t = p.scans[house] or 0
    if t > (ts or 0) and (not bestTs or t > bestTs) then best, bestTs = name, t end
  end
  return best
end

-- Name of the character we're waiting on for that item's history, if any.
function ADB:Asking(id, house)
  local now = GetTime()
  for qid, q in pairs(pending) do
    if now - q.t > TIMEOUT then
      pending[qid] = nil
    elseif q.id == id and q.house == house then
      return q.peer
    end
  end
end

-- Asks the trusted character with the most recent scan of that house for the item's history newer than ours (full:
-- all of it, for the graph). Returns who was asked, nil when no one (or asked recently).
function ADB:AskHistory(id, house, full)
  if not self.db.askPeers or not next(self.peers) then return end
  local key = house .. ":" .. id .. (full and ":f" or "")
  local now = GetTime()
  if asked[key] and now - asked[key] < (full and TIMEOUT or ASK_AGAIN) then return end
  local last = self:LastPrice(id, house)
  local peer = self:BestPeer(house, not full and last and last[1] or nil)
  if not peer then return end
  if not full then
    local n = 0
    for _, q in pairs(pending) do if not q.full and now - q.t < TIMEOUT then n = n + 1 end end
    if n >= MAX_PENDING then return end
  end
  asked[key] = now
  local since = (full or not last) and self:RecentStart() - 1 or last[1]
  local qid = self:NewMessageID()
  pending[qid] = {peer = peer, id = id, house = house, full = full, t = now}
  self:Send(peer, "Q", qid, ("%d,%s,%d,%d"):format(id, house, since, (full or not last) and 1 or 0))
  return peer
end

ADB:OnMessage("Q", function(self, sender, qid, payload)
  local id, house, since, daily = payload:match("^(%d+),(%a+),(%d+),([01])$")
  if not id then return end
  id, since = tonumber(id), tonumber(since)
  local recent = {}
  for _, p in ipairs(self:RecentHistory(id, house)) do if p[1] > since then recent[#recent + 1] = p end end
  local days = daily == "1" and self:StoredDaily(id, house) or {}
  self:Send(sender, "H", qid, self:ToWire(recent) .. "/" .. self:ToWire(days))
end)

ADB:OnMessage("H", function(self, sender, qid, payload)
  local q = pending[qid]
  if not q or q.peer ~= sender then return end
  pending[qid] = nil
  local recent, daily = payload:match("^([^/]*)/(.*)$")
  if not recent then return end
  local n = self:MergeHistory(self:House(q.house), q.id, self:FromWire(recent), self:FromWire(daily))
  self:Debug("%s: %d new for item %d at the %s AH", sender, n, q.id, q.house)
  self:Fire("HISTORY_MERGED", q.id, q.house, sender, n)
end)

-- Commands

local function ago(self, ts) return ts and ts > 0 and (self:Age(ts) .. " ago") or "never" end

ADB:AddCommand("trust", function(self, rest)
  local name = rest ~= "" and rest or (UnitIsPlayer("target") and GetUnitName("target", true))
  if name then
    self.sv.trusted[name] = true
    self:Print("%s trusted: prices are shared with it once it trusts you too (/ahdb trust %s on its side)", name,
               self.myName)
    self:Announce(true, name)
    return
  end
  if not next(self.sv.trusted) then
    self:Print("no trusted characters: /ahdb trust <First Last> (or target it) here and the same for this one there")
    return
  end
  self:Print("trusted characters (prices shared both ways):")
  for n in pairs(self.sv.trusted) do
    local p = self.peers[n]
    if p then
      print(("  %s: online%s, last scans: Alliance %s, Horde %s, Neutral %s"):format(n, p.ah and
                                                                                       (", at the " .. p.ah .. " AH") or
                                                                                       "", ago(self, p.scans.Alliance),
                                                                                     ago(self, p.scans.Horde),
                                                                                     ago(self, p.scans.Neutral)))
    else
      print(("  %s: not heard from (offline, or doesn't trust you)"):format(n))
    end
  end
end, "trust [First Last] - share prices with that character of another account (both ways); no name: list")

ADB:AddCommand("untrust", function(self, rest)
  if not self.sv.trusted[rest] then
    self:Print("%s isn't trusted (/ahdb trust lists them)", rest)
    return
  end
  self.sv.trusted[rest] = nil
  self.peers[rest] = nil
  self:Print("%s no longer trusted", rest)
end, "untrust <First Last> - stop sharing prices with that character")
