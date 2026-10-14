local _, ns = ...

local Chunker = {}
ns.Chunker = Chunker

local MAX_CHUNKS = 999

function Chunker.Split(payload, id, maxLen)
	maxLen = maxLen or 255
	local room = maxLen - (#id + 9)
	local n = math.max(1, math.ceil(#payload / room))
	if n > MAX_CHUNKS then
		return nil
	end
	local out = {}
	for i = 1, n do
		out[i] = id .. ":" .. i .. ":" .. n .. "~" .. payload:sub((i - 1) * room + 1, i * room)
	end
	return out
end

local Assembler = {}
Assembler.__index = Assembler

function Chunker.NewAssembler()
	return setmetatable({ pending = {} }, Assembler)
end

function Assembler:Add(sender, msg, now)
	local id, i, n, body = msg:match("^([^:~]+):(%d+):(%d+)~(.*)$")
	if not id then
		return nil
	end
	i, n = tonumber(i), tonumber(n)
	if n < 1 or i < 1 or i > n or n > MAX_CHUNKS then
		return nil
	end
	if n == 1 then
		return body
	end
	local key = sender .. "\0" .. id
	local entry = self.pending[key]
	if not entry or entry.n ~= n then
		entry = { n = n, got = 0, parts = {} }
		self.pending[key] = entry
	end
	entry.t = now
	if not entry.parts[i] then
		entry.parts[i] = body
		entry.got = entry.got + 1
	end
	if entry.got < n then
		return nil
	end
	self.pending[key] = nil
	return table.concat(entry.parts)
end

function Assembler:Expire(now, ttl)
	for key, entry in pairs(self.pending) do
		if now - entry.t > (ttl or 60) then
			self.pending[key] = nil
		end
	end
end
