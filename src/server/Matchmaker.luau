--!strict
-- The ranked queue of one server (docs/PHASE6.md, M27, BQ). Pure Luau so Lune can test it with fake players and a
-- fake clock; PvpService feeds it and forms a room for each pair it makes.
--
-- Each player accepts an opponent whose points are within their window: WINDOW_BASE plus WINDOW_PER_SECOND for every
-- second waited, at most WINDOW_MAX. Two players are matched only when each is within the other's window. Players are
-- served longest-waiting first; each takes, among those who fit, someone they haven't met in the last RECENT_SECONDS
-- if there is one, and among those whoever has waited longest. Players are opaque keys (Player instances in the game,
-- strings in tests).

-- Config.PVP.QUEUE.
export type Settings = {
	WINDOW_BASE: number,
	WINDOW_PER_SECOND: number,
	WINDOW_MAX: number,
	RECENT_SECONDS: number,
}

export type Deps = { clock: () -> number, settings: Settings }

type Entry = { key: any, rating: number, since: number, order: number }

local Matchmaker = {}
Matchmaker.__index = Matchmaker

export type Matchmaker = typeof(setmetatable(
	{} :: {
		deps: Deps,
		queue: { [any]: Entry },
		met: { [any]: { [any]: number } }, -- by player: who they were matched with, and when
		nextOrder: number,
	},
	Matchmaker
))

function Matchmaker.new(deps: Deps): Matchmaker
	return setmetatable({ deps = deps, queue = {}, met = {}, nextOrder = 1 }, Matchmaker)
end

--- Puts the player in the queue with these rank points. False when they are in it already.
function Matchmaker.enqueue(self: Matchmaker, key: any, rating: number): boolean
	if self.queue[key] then
		return false
	end
	self.queue[key] = { key = key, rating = rating, since = self.deps.clock(), order = self.nextOrder }
	self.nextOrder += 1
	return true
end

--- Takes the player out of the queue. False when they weren't in it.
function Matchmaker.cancel(self: Matchmaker, key: any): boolean
	if not self.queue[key] then
		return false
	end
	self.queue[key] = nil
	return true
end

--- Forgets everything about the player (call when they leave the server).
function Matchmaker.remove(self: Matchmaker, key: any)
	self.queue[key] = nil
	self.met[key] = nil
	for _, others in self.met do
		others[key] = nil
	end
end

function Matchmaker.isQueued(self: Matchmaker, key: any): boolean
	return self.queue[key] ~= nil
end

--- Seconds the player has waited, or nil when they aren't queued.
function Matchmaker.waited(self: Matchmaker, key: any): number?
	local entry = self.queue[key]
	return if entry then self.deps.clock() - entry.since else nil
end

--- How many players are queued.
function Matchmaker.count(self: Matchmaker): number
	local count = 0
	for _ in self.queue do
		count += 1
	end
	return count
end

--- The points difference the player accepts right now.
function Matchmaker.window(self: Matchmaker, key: any): number
	local settings = self.deps.settings
	local waited = self:waited(key) or 0
	return math.min(settings.WINDOW_BASE + settings.WINDOW_PER_SECOND * waited, settings.WINDOW_MAX)
end

local function metRecently(self: Matchmaker, a: any, b: any, now: number): boolean
	local at = self.met[a] and self.met[a][b]
	return at ~= nil and now - at < self.deps.settings.RECENT_SECONDS
end

local function remember(self: Matchmaker, a: any, b: any, now: number)
	for _, pair in { { a, b }, { b, a } } do
		local others = self.met[pair[1]]
		if not others then
			others = {}
			self.met[pair[1]] = others
		end
		others[pair[2]] = now
	end
end

-- Forgets meetings older than RECENT_SECONDS, so the table doesn't grow.
local function forgetOld(self: Matchmaker, now: number)
	for key, others in self.met do
		for other, at in others do
			if now - at >= self.deps.settings.RECENT_SECONDS then
				others[other] = nil
			end
		end
		if next(others) == nil then
			self.met[key] = nil
		end
	end
end

--- Makes every pair it can now, takes them out of the queue and returns them (each { a, b }, a the longer waiting).
function Matchmaker.tick(self: Matchmaker): { { any } }
	local now = self.deps.clock()
	forgetOld(self, now)
	local waiting: { Entry } = {}
	for _, entry in self.queue do
		table.insert(waiting, entry)
	end
	table.sort(waiting, function(x: Entry, y: Entry): boolean
		return x.order < y.order
	end)

	local taken: { [any]: boolean } = {}
	local matched: { { any } } = {}
	for _, first in waiting do
		if taken[first.key] then
			continue
		end
		local windowFirst = self:window(first.key)
		local best: Entry? = nil
		local bestFresh = false
		for _, second in waiting do
			if second == first or taken[second.key] then
				continue
			end
			local gap = math.abs(first.rating - second.rating)
			if gap > windowFirst or gap > self:window(second.key) then
				continue
			end
			local fresh = not metRecently(self, first.key, second.key, now)
			-- `waiting` is longest-waiting first, so the first fit of each kind is the longest-waiting one.
			if best == nil or (fresh and not bestFresh) then
				best, bestFresh = second, fresh
			end
		end
		if best then
			taken[first.key] = true
			taken[best.key] = true
			self.queue[first.key] = nil
			self.queue[best.key] = nil
			remember(self, first.key, best.key, now)
			table.insert(matched, { first.key, best.key })
		end
	end
	return matched
end

--- How many entries the tables hold; 0 once everyone has left.
function Matchmaker.footprint(self: Matchmaker): number
	local count = 0
	for _ in self.queue do
		count += 1
	end
	for _, others in self.met do
		for _ in others do
			count += 1
		end
	end
	return count
end

return Matchmaker
