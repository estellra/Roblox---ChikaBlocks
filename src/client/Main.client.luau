--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[ChikaBlock] Client ready ({Config.PIECES_PER_SET} pieces per set)`)
