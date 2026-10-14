local _, ns = ...

local DayClock = {}
ns.DayClock = DayClock

function DayClock.Key(serverTime, resetHourUTC)
	return math.floor((serverTime - (resetHourUTC or 0) * 3600) / 86400)
end

function DayClock.Start(key, resetHourUTC)
	return key * 86400 + (resetHourUTC or 0) * 3600
end
