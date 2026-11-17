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
--   CoopInvite(targetUserId, mode)               invite a player in this server to a room: mode 1 (or nil) Co-op, 2 a Duel
--                                                (a friendly PVP match)
--   CoopInviteReply(inviteId, accept)            answer an invitation (only its target can)
--   CoopCancelInvite()                           take back the invitation the player has out
--   CoopLeave()                                  leave the Co-op room (and with it the run)
--   CoopPlace(runId, moveId, slot, x, y)         a Co-op move the client has already shown (predicted); moveId is the
--                                                client's own counter, only for recognising the move again
--   CoopRotate(runId, moveId, slot)              turn a Co-op piece (predicted by the client); moveId comes from the same
--                                                counter as CoopPlace's. Revive and buying rotations reuse RequestRevive and
--                                                RequestRotations, which the server answers for whichever run the player is in
--   CoopRequestState()                           the client thinks it is out of step; send the full Co-op state
--   CoopTakeOver(runId)                          the partner has been idle too long: take their pieces and play on
--   CoopRematch()                                Play again after a Co-op game over; needs both players
--   CoopHover(slot, x, y)                        (unreliable) the board cell a Co-op piece is aimed at, for the partner to
--                                                see; sent when the cell changes, at most 10 a second. No arguments: the
--                                                piece is no longer aimed
--   PvpPlace(matchId, moveIndex, slot, x, y)     a PVP move the client has already shown (predicted); moveIndex is how many
--                                                moves the player had made before it
--   PvpRotate(matchId, moveIndex, slot)          turn a piece with the match's free rotation (predicted)
--   PvpRequestState()                            the client thinks it is out of step; send the full match state
--   PvpForfeit(matchId)                          give up the match (a loss)
--   PvpRematch(matchId)                          Play again after a friendly or practice match; needs both players
-- Server -> client
--   GameState(state, reason)                     full run state; reason is "start", "resync" or "revive"
--   MoveResult(runId, moveIndex, score, set, isOver, best)
--                                                a move was accepted; set = new piece ids when the tray refilled
--   Profile(profile)                             { best, gamesPlayed, tutorialDone, level, exp, rotations, donated, title? }
--   RunRewards(runId, rewards)                   after a game over: EXP gained, level before and after,
--                                                titles unlocked during the run (see GameService)
--   ReviveOffer(runId, offer)                    after a game over: { tokens, price? }, the revives already paid for and
--                                                the Robux price of the next one. A Co-op run offers it to both players
--   ReviveResult(runId, ok)                      the revive didn't happen (purchase cancelled or not possible)
--   Donated(amount, total)                       a donation was granted: its Robux, and the player's total
--   Leaderboard(snapshot)                        top entries of every board (the Co-op board by pair) and the
--                                                player's own values (see LeaderboardService.Snapshot)
--   CoopInvited(inviteId, fromUserId, expiresAt, mode)
--                                                someone invited the player; expiresAt is in workspace:GetServerTimeNow(),
--                                                mode is "coop" or "pvp" (a Duel)
--   CoopInviteResult(otherUserId, result)        how an invitation with that player stands. The inviter hears sent,
--                                                declined, expired, busy, cooldown or left; the invited player hears
--                                                expired or cancelled (the invitation is gone)
--   CoopRoom(room)                               { id, mode, you, present, userIds } where you is the player's seat (1 or 2),
--                                                present and userIds go by seat; nil when the player has no room
--   CoopState(state, reason)                     the full Co-op run: { runId, seq, seat, userIds, session, takeOverAt? } with the
--                                                CoopSession snapshot; reason is "start", "resync", "takeover" (the
--                                                partner is gone and every piece is the player's now) or "revive" (the
--                                                run was revived: a new set and a cleared middle)
--   CoopEvent("move", runId, seq, seat, moveId, slot, x, y, score, set, isOver, takeOverAt)
--                                                an accepted move, in the order the server took them (seq counts the
--                                                run's moves and turns); set = new piece ids when it used the last piece of
--                                                the set; takeOverAt is when this player may take over (server time), or nil
--   CoopEvent("turn", runId, seq, seat, moveId, slot, charged)
--                                                a piece was turned; charged is "free", "paid" or nil (the piece had been
--                                                turned already), what it cost the player. Moves and turns share one remote
--                                                on purpose: only the events of a single RemoteEvent are guaranteed to
--                                                arrive in the order they were sent, and a turn that overtook the move before
--                                                it would put the partner's copy out of step
--   CoopReject(runId, moveId)                    that move or turn doesn't work (a move: the partner got there first); only the sender
--   CoopRematchVotes(votes)                      who has pressed Play again, by seat
--   CoopRewards(runId, rewards)                  after a Co-op game over, to each player still in the run: EXP gained,
--                                                level before and after, titles unlocked (as RunRewards)
--   CoopPartnerHover(slot, x, y)                 (unreliable) the partner's CoopHover, checked; no arguments when they
--                                                stopped aiming. A lost message must not leave a shadow behind: the client
--                                                drops one that isn't renewed within a second or so
--   PvpEvent("start", state) / PvpEvent("state", state)
--                                                a match begins, or its full state for a client out of step: { matchId,
--                                                kind, seat, startAt, endAt, you, opponent, userIds, names } with you the
--                                                PvpSession snapshot and every time in server time
--   PvpEvent("result", result)                   the player's move was accepted: { matchId, moveIndex, score, sent,
--                                                cancelled, pending, refill?, stuck? } (see PvpSync.Result)
--   PvpEvent("incoming", matchId, pending)       the opponent's attack changed the player's garbage queue
--   PvpEvent("end", info)                        the match is over: { matchId, kind, reason, results, scores, sent,
--                                                blocked } by seat (see PvpMatches.EndInfo)
--   PvpEvent("votes", matchId, votes)            who has pressed Play again, by seat
--                                                Everything about a match goes through PvpEvent, one remote, so it arrives
--                                                in the order it was sent
--   PvpOpponentBoard(board)                      (unreliable) the opponent's board as a 39-byte buffer (PvpBoardCodec),
--                                                after each of their moves and again every second
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

local function remote(className: "RemoteEvent" | "UnreliableRemoteEvent", name: string): any
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = folder
		return created
	end
	return folder:WaitForChild(name)
end

local function remoteEvent(name: string): RemoteEvent
	return remote("RemoteEvent", name)
end

-- For what the next message makes obsolete and a lost one doesn't hurt (it may be dropped or arrive out of order).
local function unreliableEvent(name: string): UnreliableRemoteEvent
	return remote("UnreliableRemoteEvent", name)
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
	CoopPlace = remoteEvent("CoopPlace"),
	CoopRotate = remoteEvent("CoopRotate"),
	CoopRequestState = remoteEvent("CoopRequestState"),
	CoopTakeOver = remoteEvent("CoopTakeOver"),
	CoopRematch = remoteEvent("CoopRematch"),
	CoopState = remoteEvent("CoopState"),
	CoopEvent = remoteEvent("CoopEvent"),
	CoopReject = remoteEvent("CoopReject"),
	CoopRematchVotes = remoteEvent("CoopRematchVotes"),
	CoopRewards = remoteEvent("CoopRewards"),
	CoopHover = unreliableEvent("CoopHover"),
	PvpPlace = remoteEvent("PvpPlace"),
	PvpRotate = remoteEvent("PvpRotate"),
	PvpRequestState = remoteEvent("PvpRequestState"),
	PvpForfeit = remoteEvent("PvpForfeit"),
	PvpRematch = remoteEvent("PvpRematch"),
	PvpEvent = remoteEvent("PvpEvent"),
	PvpOpponentBoard = unreliableEvent("PvpOpponentBoard"),
	CoopPartnerHover = unreliableEvent("CoopPartnerHover"),
	Donated = remoteEvent("Donated"),
	GameState = remoteEvent("GameState"),
	MoveResult = remoteEvent("MoveResult"),
	Profile = remoteEvent("Profile"),
	RunRewards = remoteEvent("RunRewards"),
	Leaderboard = remoteEvent("Leaderboard"),
	ReviveOffer = remoteEvent("ReviveOffer"),
	ReviveResult = remoteEvent("ReviveResult"),
}
