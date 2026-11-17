--!strict
-- The opponent's board as a 39-byte buffer for the unreliable PvpOpponentBoard remote (docs/PHASE6.md, M26, BW):
--   bytes 0-31  the 64 cells, two per byte (low nibble first): 0 empty, 1 to COLOR_COUNT a piece color, GARBAGE_COLOR
--   bytes 32-35 score (u32)
--   byte  36    garbage lines waiting (u8)
--   bytes 37-38 version (u16): grows with every change, so the client keeps only the newest it has seen
-- It never carries the opponent's tray or piece ids.

local Config = require("./Config")

local CELL_COUNT = Config.GRID_SIZE * Config.GRID_SIZE
local CELL_BYTES = CELL_COUNT // 2
local MAX_CELL = Config.PVP.GARBAGE_COLOR
local SIZE = CELL_BYTES + 4 + 1 + 2
local MAX_SCORE = 2 ^ 32 - 1
local VERSION_RANGE = 2 ^ 16

export type View = {
	cells: { number }, -- 64 color ids, as Board cells
	score: number,
	pending: number, -- garbage lines waiting
	version: number,
}

local PvpBoardCodec = {}

PvpBoardCodec.SIZE = SIZE

--- Packs a view. Cells outside 0 to GARBAGE_COLOR, the score, the count and the version are clamped or wrapped to fit.
function PvpBoardCodec.encode(view: View): buffer
	local data = buffer.create(SIZE)
	for i = 0, CELL_BYTES - 1 do
		local low = math.clamp(view.cells[i * 2 + 1] or 0, 0, MAX_CELL)
		local high = math.clamp(view.cells[i * 2 + 2] or 0, 0, MAX_CELL)
		buffer.writeu8(data, i, low + high * 16)
	end
	buffer.writeu32(data, CELL_BYTES, math.clamp(math.floor(view.score), 0, MAX_SCORE))
	buffer.writeu8(data, CELL_BYTES + 4, math.clamp(view.pending, 0, 255))
	buffer.writeu16(data, CELL_BYTES + 5, view.version % VERSION_RANGE)
	return data
end

--- Unpacks a buffer from the remote. Nil when it isn't a well-formed board (wrong type or size, a cell out of range).
function PvpBoardCodec.decode(data: unknown): View?
	if typeof(data) ~= "buffer" or buffer.len(data :: buffer) ~= SIZE then
		return nil
	end
	local bytes = data :: buffer
	local cells = table.create(CELL_COUNT, 0)
	for i = 0, CELL_BYTES - 1 do
		local byte = buffer.readu8(bytes, i)
		local low, high = byte % 16, byte // 16
		if low > MAX_CELL or high > MAX_CELL then
			return nil
		end
		cells[i * 2 + 1] = low
		cells[i * 2 + 2] = high
	end
	return {
		cells = cells,
		score = buffer.readu32(bytes, CELL_BYTES),
		pending = buffer.readu8(bytes, CELL_BYTES + 4),
		version = buffer.readu16(bytes, CELL_BYTES + 5),
	}
end

--- Whether version `incoming` is newer than `current`, allowing for the u16 wrapping around.
function PvpBoardCodec.isNewer(incoming: number, current: number): boolean
	local ahead = (incoming - current) % VERSION_RANGE
	return ahead ~= 0 and ahead < VERSION_RANGE / 2
end

return PvpBoardCodec
