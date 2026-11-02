--!strict
-- Every remote in the game, in one place. The server creates them; clients wait for them.
--
-- Client -> server
--   StartGame(mode)                              start or restart the player's run; mode "normal" or "tutorial"
--   RequestProfile()                             send the saved profile (best, games played, tutorial done)
--   ClientReady()                                the client finished loading and shows the menu (analytics)
--   SkipTutorial()                               the player skipped the tutorial (counts as done)
--   RequestLeaderboard()                         send the cached leaderboards
--   PlacePiece(runId, moveIndex, slot, x, y)     a move the client has already shown (predicted)
--   RequestState()                               the client disagrees with the server; send the full state
-- Server -> client
--   GameState(state, reason)                     full run state; reason is "start" or "resync"
--   MoveResult(runId, moveIndex, score, set, isOver, best)
--                                                a move was accepted; set = new piece ids when the tray refilled
--   Profile(profile)                             { best, gamesPlayed, tutorialDone, level, exp, title? }
--   RunRewards(runId, rewards)                   after a game over: EXP gained, level before and after,
--                                                titles unlocked during the run (see GameService)
--   Leaderboard(snapshot)                        top entries of every board and the player's own values
--                                                (see LeaderboardService.Snapshot)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local IS_SERVER = RunService:IsServer()

local folder: Instance
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function remoteEvent(name: string): RemoteEvent
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return {
	StartGame = remoteEvent("StartGame"),
	PlacePiece = remoteEvent("PlacePiece"),
	RequestState = remoteEvent("RequestState"),
	RequestProfile = remoteEvent("RequestProfile"),
	ClientReady = remoteEvent("ClientReady"),
	SkipTutorial = remoteEvent("SkipTutorial"),
	RequestLeaderboard = remoteEvent("RequestLeaderboard"),
	GameState = remoteEvent("GameState"),
	MoveResult = remoteEvent("MoveResult"),
	Profile = remoteEvent("Profile"),
	RunRewards = remoteEvent("RunRewards"),
	Leaderboard = remoteEvent("Leaderboard"),
}
