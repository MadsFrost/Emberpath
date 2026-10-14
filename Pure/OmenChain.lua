local _, ns = ...

local Chain = {}
ns.OmenChain = Chain

Chain.SEASON_LENGTH = 28

-- v_L = seed, v_(k-1) = SHA256(v_k), commit = v_0. Day k of the season uses v_k.
-- Revealing v_k proves it against any earlier value without exposing later days.
function Chain.Value(seed, length, k)
	local v = seed
	for _ = 1, length - k do
		v = ns.SHA256(v)
	end
	return v
end

function Chain.Commit(seed, length)
	return Chain.Value(seed, length, 0)
end

function Chain.OmenIndex(vk, deckSize)
	local h = ns.SHA256(vk .. ":omen")
	return tonumber(h:sub(1, 8), 16) % deckSize + 1
end

function Chain.IsHash(v)
	return type(v) == "string" and #v == 64 and not v:find("[^0-9a-f]")
end

-- anchors: { [k] = verified v_k }, must contain [0] = commit.
function Chain.Verify(anchors, k, vk)
	if not Chain.IsHash(vk) or type(k) ~= "number" or k < 1 then
		return false
	end
	local best
	for j in pairs(anchors) do
		if j < k and (not best or j > best) then
			best = j
		end
	end
	if not best then
		return false
	end
	local v = vk
	for _ = 1, k - best do
		v = ns.SHA256(v)
	end
	return v == anchors[best]
end
