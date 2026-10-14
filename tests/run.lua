-- Run from the repo root: luajit tests/run.lua
bit = bit or require("bit")

local ns = {}
for _, file in ipairs({
	"Pure/SHA256.lua",
	"Pure/OmenChain.lua",
	"Pure/DayClock.lua",
	"Pure/Geometry.lua",
	"Pure/Store.lua",
	"Pure/Chunker.lua",
	"Omens/Deck.lua",
}) do
	assert(loadfile(file))("Emberpath", ns)
end

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

test("sha256 known vectors", function()
	eq(ns.SHA256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty")
	eq(ns.SHA256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc")
	eq(ns.SHA256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
		"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "two blocks")
	eq(ns.SHA256(string.rep("a", 1000)),
		"41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", "1000 a")
end)

local Chain = ns.OmenChain
local seed = ns.SHA256("test seed")
local L = 10
local commit = Chain.Commit(seed, L)

test("chain verifies each day against the commit", function()
	for k = 1, L do
		assert(Chain.Verify({ [0] = commit }, k, Chain.Value(seed, L, k)), "day " .. k)
	end
end)

test("chain verifies against a later anchor", function()
	local anchors = { [0] = commit, [3] = Chain.Value(seed, L, 3) }
	assert(Chain.Verify(anchors, 7, Chain.Value(seed, L, 7)))
end)

test("chain rejects tampered and misplaced values", function()
	local anchors = { [0] = commit }
	assert(not Chain.Verify(anchors, 4, Chain.Value(seed, L, 5)), "wrong day")
	assert(not Chain.Verify(anchors, 4, ns.SHA256("forged")), "forged")
	assert(not Chain.Verify(anchors, 4, "not a hash"), "garbage")
	assert(not Chain.Verify(anchors, 0, commit), "day zero")
	assert(not Chain.Verify({}, 2, Chain.Value(seed, L, 2)), "no anchors")
end)

test("omen index stays inside the deck", function()
	local size = #ns.Deck
	for k = 1, L do
		local idx = Chain.OmenIndex(Chain.Value(seed, L, k), size)
		assert(idx >= 1 and idx <= size and idx == math.floor(idx), "index " .. idx)
	end
end)

test("deck entries are complete and ids unique", function()
	local seen = {}
	for i, omen in ipairs(ns.Deck) do
		assert(type(omen.id) == "string" and not seen[omen.id], "id at " .. i)
		seen[omen.id] = true
		assert(omen.kind == "restriction" or omen.kind == "ritual" or omen.kind == "goal", "kind of " .. omen.id)
		assert(type(omen.text) == "string" and type(omen.icon) == "string", "fields of " .. omen.id)
	end
end)

test("day keys roll over at the reset hour", function()
	local DayClock = ns.DayClock
	local midnight = 20000 * 86400
	eq(DayClock.Key(midnight + 3 * 3600, 4), 19999, "before reset")
	eq(DayClock.Key(midnight + 4 * 3600, 4), 20000, "at reset")
	eq(DayClock.Start(20000, 4), midnight + 4 * 3600, "start")
end)

test("simplify keeps corners and drops collinear points", function()
	local G = ns.Geometry
	local pts = { 0, 0, 0, 10, 0, 1, 20, 0, 2, 30, 0, 3, 30, 10, 4, 30, 20, 5 }
	local out = G.Simplify(pts, 1)
	eq(#out, 9, "points kept")
	eq(out[4], 30, "corner x")
	eq(out[5], 0, "corner y")
	eq(out[6], 3, "corner time")
	eq(G.PathLength(pts), 50, "length")
end)

test("store tracks contiguous range and gaps", function()
	local s = ns.NewStore({})
	assert(s:Ingest("A", 1, { t = "x" }))
	assert(s:Ingest("A", 3, { t = "x" }))
	assert(not s:Ingest("A", 3, { t = "x" }), "duplicate")
	assert(not s:Ingest("A", 2, { nope = true }), "invalid")
	eq(s:Contig("A"), 1, "contig with gap")
	eq(s:High("A"), 3, "high")
	assert(s:Ingest("A", 2, { t = "x" }))
	eq(s:Contig("A"), 3, "contig after fill")
	eq(#s:Since("A", 1), 2, "since")
	eq(s:Vector().A, 3, "vector")
end)

test("store append respects claimed seqs", function()
	local s = ns.NewStore({})
	eq(s:Append("me", { t = "x" }), 1, "first")
	s:Claim("me", 7)
	eq(s:Append("me", { t = "x" }), 8, "after claim")
end)

test("store rejects absurd seq jumps", function()
	local s = ns.NewStore({})
	assert(not s:Ingest("A", 1e9, { t = "x" }), "huge seq")
	s:Claim("me", 1e9)
	eq(s:Append("me", { t = "x" }), 1, "bogus claim ignored")
end)

test("chunker round-trips and handles interleaving", function()
	local C = ns.Chunker
	local payload = string.rep("abcdefghij", 70)
	local a = C.Split(payload, "1f", 255)
	local b = C.Split("short", "20", 255)
	assert(#a == 3, "chunk count " .. #a)
	for _, chunk in ipairs(a) do
		assert(#chunk <= 255, "chunk too long")
	end
	local asm = C.NewAssembler()
	assert(asm:Add("X", a[2], 0) == nil)
	eq(asm:Add("X", b[1], 0), "short", "single chunk")
	assert(asm:Add("X", a[1], 0) == nil)
	eq(asm:Add("X", a[3], 0), payload, "reassembled")
	assert(asm:Add("X", "garbage", 0) == nil)
end)

test("all addon files parse", function()
	local toc = assert(io.open("Emberpath.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") then
			local path = line:gsub("\\", "/")
			local ok, err = loadfile(path)
			assert(ok, err)
		end
	end
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
