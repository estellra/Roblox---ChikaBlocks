--!strict
-- Number formatting for the UI.
local Format = {}

-- 1280 -> "1,280"
function Format.withCommas(number: number): string
	local digits = tostring(math.floor(number))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

return Format
