--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[ChikaBlock] Server ready ({Config.GRID_SIZE}x{Config.GRID_SIZE} board)`)
