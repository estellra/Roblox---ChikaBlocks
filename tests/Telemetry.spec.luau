--!strict
local TestKit = require("./TestKit")
local Telemetry = require("../src/server/Telemetry")

local PLAYER = "player-1"

type Logged = { kind: string, step: number?, name: string, value: number?, fields: { string }? }

-- Telemetry with a sink that records what it was asked to log.
local function newTelemetry(): (Telemetry.Telemetry, { Logged })
	local logged: { Logged } = {}
	local telemetry = Telemetry.new({
		onboardingStep = function(_player: any, step: number, name: string)
			table.insert(logged, { kind = "onboarding", step = step, name = name })
		end,
		custom = function(_player: any, name: string, value: number, fields: { string })
			table.insert(logged, { kind = "custom", name = name, value = value, fields = fields })
		end,
	})
	return telemetry, logged
end

local function steps(logged: { Logged }): { number }
	local result = {}
	for _, entry in logged do
		if entry.kind == "onboarding" then
			table.insert(result, entry.step :: number)
		end
	end
	return result
end

local function summary(isOver: boolean): Telemetry.RunSummary
	return { mode = "tutorial", score = 172, moves = 23, maxCombo = 2, isOver = isOver }
end

return function(t: TestKit.TestKit)
	t.describe("Telemetry", function()
		t.it("walks a new player through the six onboarding steps in order", function()
			local telemetry, logged = newTelemetry()
			local data = { onboardingStep = 0 }
			telemetry:menuShown(PLAYER, data)
			telemetry:runStarted(PLAYER, data)
			telemetry:moveAccepted(PLAYER, data, 1) -- the tutorial's first move clears a line
			telemetry:runEnded(PLAYER, data, summary(true), "gameover")
			telemetry:runStarted(PLAYER, data)
			t.expect(steps(logged)).toEqual({ 1, 2, 3, 4, 5, 6 })
			t.expect(logged[1].name).toBe("MenuShown")
			t.expect(data.onboardingStep).toBe(6)
		end)

		t.it("logs each step once", function()
			local telemetry, logged = newTelemetry()
			local data = { onboardingStep = 0 }
			for _ = 1, 3 do
				telemetry:menuShown(PLAYER, data)
				telemetry:runStarted(PLAYER, data)
				telemetry:moveAccepted(PLAYER, data, 2)
			end
			t.expect(steps(logged)).toEqual({ 1, 2, 3, 4 })
		end)

		t.it("never skips a step: a game over before any line clear waits for the clear", function()
			local telemetry, logged = newTelemetry()
			local data = { onboardingStep = 0 }
			telemetry:menuShown(PLAYER, data)
			telemetry:runStarted(PLAYER, data)
			telemetry:moveAccepted(PLAYER, data, 0)
			telemetry:runEnded(PLAYER, data, summary(true), "gameover")
			telemetry:runStarted(PLAYER, data)
			t.expect(steps(logged)).toEqual({ 1, 2, 3 })

			telemetry:moveAccepted(PLAYER, data, 1)
			telemetry:runEnded(PLAYER, data, summary(true), "gameover")
			telemetry:runStarted(PLAYER, data)
			t.expect(steps(logged)).toEqual({ 1, 2, 3, 4, 5, 6 })
		end)

		t.it("logs nothing more for players who finished the funnel", function()
			local telemetry, logged = newTelemetry()
			local data = { onboardingStep = 6 }
			telemetry:menuShown(PLAYER, data)
			telemetry:runStarted(PLAYER, data)
			telemetry:moveAccepted(PLAYER, data, 1)
			t.expect(#logged).toBe(0)
		end)

		t.it("reports every ending run by mode and by how it ended", function()
			local telemetry, logged = newTelemetry()
			telemetry:runEnded(PLAYER, nil, summary(false), "left")
			t.expect(logged).toEqual({
				{ kind = "custom", name = "RunScore", value = 172, fields = { "tutorial", "left" } },
				{ kind = "custom", name = "RunMoves", value = 23, fields = { "tutorial", "left" } },
				{ kind = "custom", name = "RunMaxCombo", value = 2, fields = { "tutorial", "left" } },
			})
		end)

		t.it("does not count leaving or restarting as the onboarding game over", function()
			local telemetry, logged = newTelemetry()
			local data = { onboardingStep = 4 }
			telemetry:runEnded(PLAYER, data, summary(false), "left")
			telemetry:runEnded(PLAYER, data, summary(false), "restart")
			t.expect(steps(logged)).toEqual({})
			t.expect(data.onboardingStep).toBe(4)
		end)
	end)
end
