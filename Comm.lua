local _, ns = ...

local Comm = {}
ns.Comm = Comm

local PREFIX = "Emberpath"
local PROTO = 1
local HELLO_INTERVAL = 300
local WANT_TIMEOUT = 30
local BURST, REGEN = 8, 1
local BATCH_WEIGHT = 8

Comm.peers = {}

local queues = { normal = {}, bulk = {} }
local tokens, lastRefill = BURST, 0
local assembler = ns.Chunker.NewAssembler()
local msgCounter = math.random(0, 0xffff) * 16
local pending = {}
local warnedVersion = false
local handlers = {}

local function available()
	return C_EncodingUtil ~= nil and C_EncodingUtil.SerializeCBOR ~= nil
end

local function encode(tbl)
	local cbor = C_EncodingUtil.SerializeCBOR(tbl)
	local packed = C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate)
	return C_EncodingUtil.EncodeBase64(packed)
end

local function decode(text)
	local ok, result = pcall(function()
		local packed = C_EncodingUtil.DecodeBase64(text)
		local cbor = C_EncodingUtil.DecompressString(packed, Enum.CompressionMethod.Deflate)
		return C_EncodingUtil.DeserializeCBOR(cbor)
	end)
	if ok and type(result) == "table" then
		return result
	end
end

local function groupChannel()
	if IsInRaid(LE_PARTY_CATEGORY_HOME) then
		return "RAID"
	elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "PARTY"
	end
end

local function broadcastChannels()
	local list = {}
	if IsInGuild() then
		list[#list + 1] = "GUILD"
	end
	local group = groupChannel()
	if group then
		list[#list + 1] = group
	end
	return list
end

function Comm:Send(tbl, chatType, target, bulk)
	if not available() then
		return
	end
	msgCounter = msgCounter + 1
	local chunks = ns.Chunker.Split(encode(tbl), string.format("%x", msgCounter), 255)
	if not chunks then
		return
	end
	local q = bulk and queues.bulk or queues.normal
	for _, chunk in ipairs(chunks) do
		q[#q + 1] = { chunk, chatType, target }
	end
end

function Comm:Broadcast(tbl, bulk)
	for _, channel in ipairs(broadcastChannels()) do
		self:Send(tbl, channel, nil, bulk)
	end
end

local function pump()
	local now = GetTime()
	tokens = math.min(BURST, tokens + (now - lastRefill) * REGEN)
	lastRefill = now
	local throttled = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
	while tokens >= 1 do
		local q = queues.normal
		if #q == 0 then
			if InCombatLockdown() or IsInInstance() then
				return
			end
			q = queues.bulk
		end
		local item = q[1]
		if not item then
			return
		end
		local result = C_ChatInfo.SendAddonMessage(PREFIX, item[1], item[2], item[3])
		if throttled and result == throttled then
			tokens = 0
			return
		end
		table.remove(q, 1)
		tokens = tokens - 1
	end
end

function Comm:Hello(query, chatType, target)
	local msg = { k = "H", me = ns.me, v = PROTO, vec = ns.store:Vector(), q = query or nil }
	if chatType then
		self:Send(msg, chatType, target)
	else
		self:Broadcast(msg)
	end
end

function Comm:Publish(author, seq, rec)
	self:Broadcast({ k = "R", a = author, r = { { seq, rec } } }, rec.t == "trail")
end

function Comm:Presence(msg)
	msg.k = "P"
	msg.me = ns.me
	self:Broadcast(msg)
end

function Comm:OnlinePeers()
	local out = {}
	local now = GetTime()
	for author, peer in pairs(self.peers) do
		if now - peer.seen < HELLO_INTERVAL * 1.3 then
			out[author] = peer
		end
	end
	return out
end

local function touchPeer(author, sender)
	local peer = Comm.peers[author]
	if not peer then
		peer = {}
		Comm.peers[author] = peer
	end
	peer.sender = sender
	peer.seen = GetTime()
end

handlers.H = function(msg, sender)
	if type(msg.me) ~= "string" or type(msg.vec) ~= "table" then
		return
	end
	if type(msg.v) == "number" and msg.v > PROTO and not warnedVersion then
		warnedVersion = true
		ns.Print("A friend runs a newer version of Emberpath. Please update.")
	end
	touchPeer(msg.me, sender)
	if msg.q then
		Comm:Hello(false, "WHISPER", sender)
	end
	local mine = ns.store:Vector()
	local want, any = {}, false
	local now = GetTime()
	for author, high in pairs(msg.vec) do
		if type(author) == "string" and type(high) == "number" then
			if author == ns.me then
				ns.store:Claim(author, high)
			end
			local have = mine[author] or 0
			if high > have and (not pending[author] or now - pending[author] > WANT_TIMEOUT) then
				want[author] = have
				pending[author] = now
				any = true
			end
		end
	end
	if any then
		Comm:Send({ k = "W", w = want }, "WHISPER", sender)
	end
	ns:Fire("EP_PEERS")
end

handlers.W = function(msg, sender)
	if type(msg.w) ~= "table" then
		return
	end
	for author, since in pairs(msg.w) do
		if type(author) == "string" and type(since) == "number" then
			local batch, weight = {}, 0
			for _, entry in ipairs(ns.store:Since(author, since)) do
				batch[#batch + 1] = entry
				weight = weight + (entry[2].t == "trail" and BATCH_WEIGHT or 1)
				if weight >= BATCH_WEIGHT then
					Comm:Send({ k = "R", a = author, r = batch }, "WHISPER", sender, true)
					batch, weight = {}, 0
				end
			end
			if #batch > 0 then
				Comm:Send({ k = "R", a = author, r = batch }, "WHISPER", sender, true)
			end
		end
	end
end

handlers.R = function(msg)
	if type(msg.a) ~= "string" or type(msg.r) ~= "table" then
		return
	end
	for _, entry in ipairs(msg.r) do
		if type(entry) == "table" then
			ns:Ingest(msg.a, entry[1], entry[2])
		end
	end
end

handlers.P = function(msg, sender)
	if type(msg.me) ~= "string" then
		return
	end
	touchPeer(msg.me, sender)
	ns:Fire("EP_PRESENCE", msg.me, msg)
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
	if prefix ~= PREFIX or not ns.ready or not available() or ns.IsMe(sender) then
		return
	end
	local payload = assembler:Add(sender, text, GetTime())
	if not payload then
		return
	end
	local msg = decode(payload)
	local handler = msg and handlers[msg.k]
	if handler then
		handler(msg, sender)
	end
end)

local wasGrouped = false
ns:On("GROUP_ROSTER_UPDATE", function()
	local channel = groupChannel()
	if channel and not wasGrouped and ns.ready then
		C_Timer.After(3, function()
			local current = groupChannel()
			if current then
				Comm:Hello(true, current)
			end
		end)
	end
	wasGrouped = channel ~= nil
end)

ns:On("EP_READY", function()
	if not available() then
		ns.Print("C_EncodingUtil is missing, so syncing with friends is off. Please report this.")
		return
	end
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	wasGrouped = groupChannel() ~= nil
	C_Timer.NewTicker(0.1, pump)
	C_Timer.NewTicker(30, function()
		assembler:Expire(GetTime(), 60)
	end)
	C_Timer.After(5, function()
		Comm:Hello(true)
	end)
	C_Timer.NewTicker(HELLO_INTERVAL, function()
		Comm:Hello(false)
	end)
end)
