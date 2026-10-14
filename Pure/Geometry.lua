local _, ns = ...

local Geometry = {}
ns.Geometry = Geometry

local sqrt = math.sqrt

function Geometry.Distance(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return sqrt(dx * dx + dy * dy)
end

local function segmentDistance(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local lenSq = dx * dx + dy * dy
	if lenSq == 0 then
		return Geometry.Distance(px, py, ax, ay)
	end
	local t = ((px - ax) * dx + (py - ay) * dy) / lenSq
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return Geometry.Distance(px, py, ax + t * dx, ay + t * dy)
end

-- Points are a flat list { x1, y1, t1, x2, y2, t2, ... }.
function Geometry.Simplify(points, epsilon)
	local n = #points / 3
	if n <= 2 then
		return points
	end
	local keep = { [1] = true, [n] = true }
	local stack = { 1, n }
	while #stack > 0 do
		local last = table.remove(stack)
		local first = table.remove(stack)
		local ax, ay = points[first * 3 - 2], points[first * 3 - 1]
		local bx, by = points[last * 3 - 2], points[last * 3 - 1]
		local maxDist, index = 0, nil
		for i = first + 1, last - 1 do
			local d = segmentDistance(points[i * 3 - 2], points[i * 3 - 1], ax, ay, bx, by)
			if d > maxDist then
				maxDist, index = d, i
			end
		end
		if index and maxDist > epsilon then
			keep[index] = true
			stack[#stack + 1] = first
			stack[#stack + 1] = index
			stack[#stack + 1] = index
			stack[#stack + 1] = last
		end
	end
	local out = {}
	for i = 1, n do
		if keep[i] then
			out[#out + 1] = points[i * 3 - 2]
			out[#out + 1] = points[i * 3 - 1]
			out[#out + 1] = points[i * 3]
		end
	end
	return out
end

function Geometry.PathLength(points)
	local total = 0
	for i = 4, #points, 3 do
		total = total + Geometry.Distance(points[i - 3], points[i - 2], points[i], points[i + 1])
	end
	return total
end
