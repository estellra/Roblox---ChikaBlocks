--!strict
-- A pair of players counts for rank at most `limit` times in `windowSeconds` (docs/PHASE6.md, M27, BP): a third
-- match the same day is still played, but "unrated". Pure Luau so Lune can test it; the store is passed in. In the
-- game it is a MemoryStoreHashMap shared by every server, so the count holds when the two change servers; when the
-- store fails, a count kept in this server stands in (and the caller hears about it, for analytics).

-- What is kept for a pair: how many rated matches since `since`.
export type Record = { n: number, since: number }

-- The shared store. `get` reads a pair's record; `update` changes it with `transform` (which may be called again if
-- another server changed it meanwhile) and keeps it `ttl` seconds. Both return false when the store can't be reached.
export type Store = {
	get: (key: string) -> (boolean, Record?),
	update: (key: string, transform: (old: Record?) -> Record, ttl: number) -> boolean,
}

export type Deps = {
	store: Store,
	clock: () -> number, -- Unix seconds (os.time in the game), shared by servers
	limit: number,
	windowSeconds: number,
	onStoreError: ((what: string) -> ())?,
}

local PairLimits = {}
PairLimits.__index = PairLimits

export type PairLimits = typeof(setmetatable({} :: { deps: Deps, local_: { [string]: Record } }, PairLimits))

function PairLimits.new(deps: Deps): PairLimits
	return setmetatable({ deps = deps, local_ = {} }, PairLimits)
end

--- The key of a pair of UserIds, the same whichever order they come in: "<smaller>_<larger>".
function PairLimits.pairKey(a: number, b: number): string
	return string.format("%d_%d", math.min(a, b), math.max(a, b))
end

local function current(self: PairLimits, record: Record?): Record?
	if record and self.deps.clock() - record.since < self.deps.windowSeconds then
		return record
	end
	return nil -- none, or from an earlier window
end

local function failed(self: PairLimits, what: string)
	local onError = self.deps.onStoreError
	if onError then
		onError(what)
	end
end

--- Whether a match between these two UserIds counts for rank.
function PairLimits.isRated(self: PairLimits, a: number, b: number): boolean
	local key = PairLimits.pairKey(a, b)
	local ok, record = self.deps.store.get(key)
	if not ok then
		failed(self, "get")
		record = self.local_[key]
	end
	local live = current(self, record)
	return live == nil or live.n < self.deps.limit
end

--- Counts a rated match between these two UserIds.
function PairLimits.record(self: PairLimits, a: number, b: number)
	local key = PairLimits.pairKey(a, b)
	local now = self.deps.clock()
	local function transform(old: Record?): Record
		local live = current(self, old)
		return if live then { n = live.n + 1, since = live.since } else { n = 1, since = now }
	end
	self.local_[key] = transform(self.local_[key])
	if not self.deps.store.update(key, transform, self.deps.windowSeconds) then
		failed(self, "update")
	end
end

--- Drops pairs whose window is over from the stand-in count.
function PairLimits.sweep(self: PairLimits)
	for key, record in self.local_ do
		if not current(self, record) then
			self.local_[key] = nil
		end
	end
end

return PairLimits
