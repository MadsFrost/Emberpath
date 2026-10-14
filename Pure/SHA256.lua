local _, ns = ...

local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local MOD = 4294967296
local byte, char, format, rep = string.byte, string.char, string.format, string.rep

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- Bit ops may return signed results (LuaJIT) or unsigned (WoW); normalise everything to [0, 2^32).
local function u(x)
	return x % MOD
end

local function rotr(x, n)
	return u(bor(rshift(x, n), lshift(x, 32 - n)))
end

local function pad(msg)
	local len = #msg
	local bits = len * 8
	local lenBytes = {}
	for i = 7, 0, -1 do
		lenBytes[#lenBytes + 1] = char(math.floor(bits / 256 ^ i) % 256)
	end
	return msg .. "\128" .. rep("\0", (55 - len) % 64) .. table.concat(lenBytes)
end

local w = {}

local function digestBlock(msg, offset, H)
	for j = 1, 16 do
		local a, b, c, d = byte(msg, offset + (j - 1) * 4, offset + (j - 1) * 4 + 3)
		w[j] = ((a * 256 + b) * 256 + c) * 256 + d
	end
	for j = 17, 64 do
		local v15, v2 = w[j - 15], w[j - 2]
		local s0 = u(bxor(rotr(v15, 7), rotr(v15, 18), rshift(v15, 3)))
		local s1 = u(bxor(rotr(v2, 17), rotr(v2, 19), rshift(v2, 10)))
		w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % MOD
	end

	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for j = 1, 64 do
		local S1 = u(bxor(rotr(e, 6), rotr(e, 11), rotr(e, 25)))
		local ch = u(bxor(band(e, f), band(u(bnot(e)), g)))
		local t1 = (h + S1 + ch + K[j] + w[j]) % MOD
		local S0 = u(bxor(rotr(a, 2), rotr(a, 13), rotr(a, 22)))
		local maj = u(bxor(band(a, b), band(a, c), band(b, c)))
		local t2 = (S0 + maj) % MOD
		h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
	end

	H[1] = (H[1] + a) % MOD
	H[2] = (H[2] + b) % MOD
	H[3] = (H[3] + c) % MOD
	H[4] = (H[4] + d) % MOD
	H[5] = (H[5] + e) % MOD
	H[6] = (H[6] + f) % MOD
	H[7] = (H[7] + g) % MOD
	H[8] = (H[8] + h) % MOD
end

function ns.SHA256(msg)
	msg = pad(msg)
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	for offset = 1, #msg, 64 do
		digestBlock(msg, offset, H)
	end
	return format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end
