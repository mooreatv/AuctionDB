-- Sharing prices with characters of your other WoW accounts (/ahdb trust <First Last>, on both sides): AHDB addon
-- messages whispered by full name (works ungrouped and across home realms; whispers can be late). Only trusted names
-- are listened to and answered: whisper senders are set by the server, so no signing is needed.
-- Message: "<type>;<id>;<part>/<parts>;<payload>", payloads longer than PART bytes are split in parts.
-- - I / i presence (I asks for one back): "<open AH house or ->,<last scan ts of Alliance>,<Horde>,<Neutral>"
-- - Q history query "<itemID>,<house>:<since ts>:<daily 0/1>,...": per house the scans newer than since (and the
--   daily entries), answered with H "<house>:<recent>/<daily>;..." (wire format, History.lua), merged into our history.
--   Tooltips ask only while Alt is held; an item isn't asked about again until that character scans the house again.
-- - L live AH search (Live.lua)
local _, ADB = ...

local PREFIX = "AHDB"
local SPACING = 0.25 -- seconds between our messages (addon messages are throttled)
local PART = 230 -- payload bytes per message (255 max)
local TIMEOUT = 60 -- seconds before giving up on an answer
local HOUSES = {"Alliance", "Horde", "Neutral"}

ADB.peers = {} -- trusted characters heard from: full name -> {ah = open AH house, scans = {house -> last scan ts}}

local handlers = {}
local queue, sending = {}, false
local lastSent = {} -- name -> GetTime() of our last message to them
local checking = {} -- lower case name -> true while waiting for an answer to /ahdb trust
local partial = {} -- sender;type;id -> {parts, got, t}
local pending = {} -- query id -> {peer, id, houses, keys, t}
local asked = {} -- peer:house:itemID[:f] -> that character's scan of the house we asked about
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

-- what: for the debug log
function ADB:Send(to, kind, id, payload, what)
  local n = math.max(1, math.ceil(#payload / PART))
  for i = 1, n do
    queue[#queue + 1] = {to, ("%s;%s;%d/%d;%s"):format(kind, id, i, n, payload:sub((i - 1) * PART + 1, i * PART))}
  end
  self:Debug("to %s: %s%s", to, what or kind, n > 1 and (" (%d messages)"):format(n) or "")
  if not sending then
    sending = true
    pump()
  end
end

-- sv.trusted: lower case name -> name (as typed, then as the server spells it once heard from)
ADB:On("CHAT_MSG_ADDON", function(self, prefix, text, _, sender)
  local lname = sender:lower()
  if prefix ~= PREFIX or not self.sv.trusted[lname] then return end
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
  if not self.peers[sender] then
    -- they only send to characters they trust: both sides are set
    self.peers[sender] = {scans = {}}
    self.sv.trusted[lname] = sender
    self:Print("linked with %s: prices are shared", sender)
  end
  checking[lname] = nil
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
  for _, name in pairs(to and {to} or self.sv.trusted) do
    if name ~= self.myName then self:Send(name, ask and "I" or "i", "0", p, "presence " .. p) end
  end
end

local function heard(self, sender, _, payload)
  local ah, a, h, n = payload:match("^([^,]+),(%d+),(%d+),(%d+)$")
  if not ah then return end
  local peer = self.peers[sender]
  peer.ah = ah ~= "-" and ah or nil
  peer.scans = {Alliance = tonumber(a), Horde = tonumber(h), Neutral = tonumber(n)}
  self:Fire("PEERS_CHANGED")
end

ADB:OnMessage("I", function(self, sender, _, payload)
  heard(self, sender, nil, payload)
  self:Announce(false, sender)
end)
ADB:OnMessage("i", heard)

-- An offline character: "No player named X is currently playing." for each message, hidden and the character
-- forgotten until it tells us it's back.
local function offline(self, name)
  if checking[name:lower()] then
    checking[name:lower()] = nil
    self:Print("%s isn't online (or the name is misspelled)", name)
  end
  self.peers[name] = nil
  for i = #queue, 1, -1 do if queue[i][1] == name then table.remove(queue, i) end end
  for qid, q in pairs(pending) do if q.peer == name then pending[qid] = nil end end
  self:Fire("PEERS_CHANGED")
end

ADB:Listen("LOGIN", function(self)
  self.myName = GetUnitName("player", true)
  -- entries as name -> true: by lower case name
  local trusted = {}
  for k, v in pairs(self.sv.trusted) do trusted[k:lower()] = v == true and k or v end
  self.sv.trusted = trusted
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    msg = msg:lower()
    for name, t in pairs(lastSent) do
      if GetTime() - t < 10 and msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name):lower() then
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

-- Name of the character we're waiting on for that item's history at that house, if any.
function ADB:Asking(id, house)
  local now = GetTime()
  for qid, q in pairs(pending) do
    if now - q.t > TIMEOUT then
      pending[qid] = nil
      for _, k in ipairs(q.keys) do asked[k] = nil end -- no answer: can be asked again
    elseif q.id == id then
      for _, h in ipairs(q.houses) do if h == house then return q.peer end end
    end
  end
end

local function askKey(peer, house, id, full) return peer .. ":" .. house .. ":" .. id .. (full and ":f" or "") end

-- The trusted character to ask about the item and at which of these houses: where it scanned more recently than our
-- prices of the item (full: any of its scans, for the graph's whole history) and wasn't asked since. nil if none.
function ADB:AskTarget(id, houses, full)
  if not self.db.askPeers then return end
  local best, list
  for name, p in pairs(self.peers) do
    local l = {}
    for _, house in ipairs(houses) do
      local scan = p.scans[house] or 0
      local last = self:LastPrice(id, house)
      if scan > 0 and (full or scan > (last and last[1] or 0)) and asked[askKey(name, house, id, full)] ~= scan and
        not self:Asking(id, house) then l[#l + 1] = house end
    end
    if #l > 0 and (not list or #l > #list) then best, list = name, l end
  end
  return best, list
end

-- Asks AskTarget's character for the item's history newer than ours (full: also the daily history, for the graph).
-- Returns who was asked, nil when there's no one to ask.
function ADB:AskHistory(id, houses, full)
  local peer, list = self:AskTarget(id, houses, full)
  if not peer then return end
  local parts, keys = {}, {}
  for i, house in ipairs(list) do
    keys[i] = askKey(peer, house, id, full)
    asked[keys[i]] = self.peers[peer].scans[house]
    local last = self:LastPrice(id, house)
    local since = (full or not last) and self:RecentStart() - 1 or last[1]
    parts[i] = ("%s:%d:%d"):format(house, since, (full or not last) and 1 or 0)
  end
  local qid = self:NewMessageID()
  pending[qid] = {peer = peer, id = id, houses = list, keys = keys, t = GetTime()}
  self:Send(peer, "Q", qid, id .. "," .. table.concat(parts, ","),
            ("ask item %d at %s%s"):format(id, table.concat(list, ", "), full and " (all)" or ""))
  return peer
end

local function counts(list)
  local t = {}
  for _, c in ipairs(list) do t[#t + 1] = c[2] > 0 and (c[1] .. " " .. c[2]) or (c[1] .. " nothing newer") end
  return table.concat(t, ", ")
end

ADB:OnMessage("Q", function(self, sender, qid, payload)
  local id, rest = payload:match("^(%d+),(.*)$")
  if not id then return end
  id = tonumber(id)
  local parts, n = {}, {}
  for house, since, daily in rest:gmatch("(%a+):(%d+):([01])") do
    since = tonumber(since)
    local recent = {}
    for _, p in ipairs(self:RecentHistory(id, house)) do if p[1] > since then recent[#recent + 1] = p end end
    local days = daily == "1" and self:StoredDaily(id, house) or {}
    parts[#parts + 1] = house .. ":" .. self:ToWire(recent) .. "/" .. self:ToWire(days)
    n[#n + 1] = {house, #recent + #days}
  end
  self:Send(sender, "H", qid, table.concat(parts, ";"), ("item %d: %s"):format(id, counts(n)))
end)

ADB:OnMessage("H", function(self, sender, qid, payload)
  local q = pending[qid]
  if not q or q.peer ~= sender then return end
  pending[qid] = nil
  local n = {}
  for house, recent, daily in payload:gmatch("(%a+):([^/;]*)/([^;]*)") do
    local added = self:MergeHistory(self:House(house), q.id, self:FromWire(recent), self:FromWire(daily))
    n[#n + 1] = {house, added}
    self:Fire("HISTORY_MERGED", q.id, house, sender, added)
  end
  self:Debug("from %s: item %d: %s", sender, q.id, counts(n))
end)

-- Commands

local function ago(self, ts) return ts and ts > 0 and (self:Age(ts) .. " ago") or "never" end

ADB:AddCommand("trust", function(self, rest)
  local name = rest ~= "" and rest or (UnitIsPlayer("target") and GetUnitName("target", true))
  if name then
    local lname = name:lower()
    if lname == self.myName:lower() then
      self:Print("that's you: /ahdb trust <First Last> of a character of another account")
      return
    end
    self.sv.trusted[lname] = name
    self:Print("%s trusted: prices are shared once it trusts you too (/ahdb trust %s there)", name, self.myName)
    -- the answer (or "not online") tells whether the link works
    checking[lname] = true
    C_Timer.After(15, function()
      if not checking[lname] then return end
      checking[lname] = nil
      self:Print("no answer from %s: it needs /ahdb trust %s on its side too (same faction)", name, self.myName)
    end)
    self:Announce(true, name)
    return
  end
  if not next(self.sv.trusted) then
    self:Print("no trusted characters: /ahdb trust <First Last> (or target it) here and the same for this one there")
    return
  end
  self:Print("trusted characters (prices shared both ways):")
  for _, n in pairs(self.sv.trusted) do
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
  local name = self.sv.trusted[rest:lower()]
  if not name then
    self:Print("%s isn't trusted (/ahdb trust lists them)", rest)
    return
  end
  self.sv.trusted[rest:lower()] = nil
  self.peers[name] = nil
  rest = name
  self:Print("%s no longer trusted", rest)
end, "untrust <First Last> - stop sharing prices with that character")
