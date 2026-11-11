--!strict
-- Every remote in the game, in one place. The server creates them; clients wait for them.
--
-- Client -> server
--   StartGame(mode)                              start or restart the player's run; mode "normal" or "tutorial"
--   RequestProfile()                             send the saved profile (best, games played, tutorial done)
--   ClientReady()                                the client finished loading and shows the menu (analytics)
--   SkipTutorial()                               the player skipped the tutorial (counts as done)
--   RequestRevive(runId)                         Revive pressed on the game over panel
--   RequestLeaderboard()                         send the cached leaderboards
--   RequestRotations()                           out of rotations: open the purchase prompt for a pack
--   RotatePiece(runId, moveIndex, slot)          turn the piece in a tray slot (predicted by the client)
--   RequestDonate(tier)                          a donation tier chosen on the Support screen (1 = smallest)
--   PlacePiece(runId, moveIndex, slot, x, y)     a move the client has already shown (predicted)
--   RequestState()                               the client disagrees with the server; send the full state
--   CoopInvite(targetUserId)                     invite a player in this server to a Co-op room
--   CoopInviteReply(inviteId, accept)            answer an invitation (only its target can)
--   CoopCancelInvite()                           take back the invitation the player has out
--   CoopLeave()                                  leave the Co-op room
-- Server -> client
--   GameState(state, reason)                     full run state; reason is "start", "resync" or "revive"
--   MoveResult(runId, moveIndex, score, set, isOver, best)
--                                                a move was accepted; set = new piece ids when the tray refilled
--   Profile(profile)                             { best, gamesPlayed, tutorialDone, level, exp, rotations, donated, title? }
--   RunRewards(runId, rewards)                   after a game over: EXP gained, level before and after,
--                                                titles unlocked during the run (see GameService)
--   ReviveOffer(runId, offer)                    after a game over: { tokens, price? }, the revives already paid for and
--                                                the Robux price of the next one
--   ReviveResult(runId, ok)                      the revive didn't happen (purchase cancelled or not possible)
--   Donated(amount, total)                       a donation was granted: its Robux, and the player's total
--   Leaderboard(snapshot)                        top entries of every board and the player's own values
--                                                (see LeaderboardService.Snapshot)
--   CoopInvited(inviteId, fromUserId, expiresAt) someone invited the player; expiresAt is in workspace:GetServerTimeNow()
--   CoopInviteResult(otherUserId, result)        how an invitation with that player stands. The inviter hears sent,
--                                                declined, expired, busy, cooldown or left; the invited player hears
--                                                expired or cancelled (the invitation is gone)
--   CoopRoom(room)                               { id, mode, you, present, userIds } where you is the player's seat (1 or 2),
--                                                present and userIds go by seat; nil when the player has no room
-- Who is free to be invited is published on each Player as attributes: CoopBusy ("room", "tutorial", "loading" or
-- nil when free) and Level.
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
	RequestRevive = remoteEvent("RequestRevive"),
	RequestLeaderboard = remoteEvent("RequestLeaderboard"),
	RequestRotations = remoteEvent("RequestRotations"),
	RotatePiece = remoteEvent("RotatePiece"),
	RequestDonate = remoteEvent("RequestDonate"),
	CoopInvite = remoteEvent("CoopInvite"),
	CoopInviteReply = remoteEvent("CoopInviteReply"),
	CoopCancelInvite = remoteEvent("CoopCancelInvite"),
	CoopLeave = remoteEvent("CoopLeave"),
	CoopInvited = remoteEvent("CoopInvited"),
	CoopInviteResult = remoteEvent("CoopInviteResult"),
	CoopRoom = remoteEvent("CoopRoom"),
	Donated = remoteEvent("Donated"),
	GameState = remoteEvent("GameState"),
	MoveResult = remoteEvent("MoveResult"),
	Profile = remoteEvent("Profile"),
	RunRewards = remoteEvent("RunRewards"),
	Leaderboard = remoteEvent("Leaderboard"),
	ReviveOffer = remoteEvent("ReviveOffer"),
	ReviveResult = remoteEvent("ReviveResult"),
}
