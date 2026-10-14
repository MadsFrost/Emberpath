local _, ns = ...

-- Append-only record log per author. Each author's records have increasing seq numbers.
-- "contig" is the highest seq such that every record 1..contig is present; sync compares it.
local Store = {}
Store.__index = Store

-- Seqs far beyond what we hold are rejected so a bad peer cannot make every loop over 1..high huge.
local MAX_JUMP = 5000

function ns.NewStore(records)
	return setmetatable({ records = records, claimed = {} }, Store)
end

function Store:Bucket(author, create)
	local b = self.records[author]
	if not b and create then
		b = { high = 0, contig = 0, list = {} }
		self.records[author] = b
	end
	return b
end

function Store:High(author)
	local b = self.records[author]
	return b and b.high or 0
end

function Store:Contig(author)
	local b = self.records[author]
	return b and b.contig or 0
end

function Store:Get(author, seq)
	local b = self.records[author]
	return b and b.list[seq]
end

function Store:Ingest(author, seq, rec)
	if type(author) ~= "string" or author == "" or type(seq) ~= "number" or seq < 1 or seq ~= math.floor(seq) then
		return false
	end
	if type(rec) ~= "table" or type(rec.t) ~= "string" then
		return false
	end
	local b = self:Bucket(author, true)
	if b.list[seq] or seq > b.contig + MAX_JUMP then
		return false
	end
	b.list[seq] = rec
	if seq > b.high then
		b.high = seq
	end
	while b.list[b.contig + 1] do
		b.contig = b.contig + 1
	end
	return true
end

-- Peers may know about our own records that this install lost; never reuse those seqs.
function Store:Claim(author, high)
	if type(high) == "number" and high > (self.claimed[author] or 0) and high <= self:Contig(author) + MAX_JUMP then
		self.claimed[author] = high
	end
end

function Store:Append(author, rec)
	local seq = math.max(self:High(author), self.claimed[author] or 0) + 1
	self:Ingest(author, seq, rec)
	return seq
end

function Store:Since(author, since)
	local out = {}
	local b = self.records[author]
	if not b then
		return out
	end
	for seq = (since or 0) + 1, b.high do
		local rec = b.list[seq]
		if rec then
			out[#out + 1] = { seq, rec }
		end
	end
	return out
end

function Store:Vector()
	local vec = {}
	for author, b in pairs(self.records) do
		vec[author] = b.contig
	end
	return vec
end

function Store:Each(fn)
	for author, b in pairs(self.records) do
		for seq = 1, b.high do
			local rec = b.list[seq]
			if rec then
				fn(author, seq, rec)
			end
		end
	end
end

function Store:Count()
	local n = 0
	for _, b in pairs(self.records) do
		for _ in pairs(b.list) do
			n = n + 1
		end
	end
	return n
end
