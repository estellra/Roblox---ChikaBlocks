--!strict
-- Design tokens. Views read colors, fonts, text sizes, radii, spacing and image ids only from here, so a
-- purchasable theme (phase 4) changes these values without touching view code. The values follow the Figma
-- mockups (ChikaBlocks-UI, page Foundations): soft pastel surfaces, dark brown outlines, chunky buttons.

export type Theme = {
	Text: {
		GameTitle: string,
		LogoLines: { string }, -- the two lines of the logo, top to bottom
	},
	Colors: {
		Background: Color3, -- the sky behind everything, top (see SkyBottom)
		SkyBottom: Color3,
		Cloud: Color3,
		Outline: Color3, -- outlines of buttons, panels and the board
		Board: Color3,
		CellEmpty: Color3,
		TraySlot: Color3,
		Text: Color3,
		TextMuted: Color3,
		Overlay: Color3, -- scrim behind panels
		Panel: Color3,
		Button: Color3, -- primary button: face, lip underneath, text
		ButtonShadow: Color3,
		ButtonText: Color3,
		ButtonSecondary: Color3,
		ButtonSecondaryShadow: Color3,
		ButtonSecondaryText: Color3,
		ButtonDisabled: Color3, -- a button that can't be pressed right now: pale face and lip, grey text and outline
		ButtonDisabledShadow: Color3,
		ButtonDisabledText: Color3,
		ButtonDisabledOutline: Color3,
		RowBorder: Color3, -- the thin edge of a white list row
		Lavender: Color3, -- soft purple card (the Co-op room), edged with Title
		PartnerCard: Color3, -- the Co-op partner's side of the tray
		Reward: Color3, -- gold: revive, combo
		RewardShadow: Color3,
		RewardText: Color3,
		MedalSilver: Color3, -- second place on the leaderboard (first is Reward gold)
		MedalBronze: Color3,
		Selection: Color3, -- outline of the tray slot chosen with keyboard or gamepad
		Hand: Color3, -- tutorial hint pointer
		Gain: Color3, -- floating "+points" text
		Combo: Color3, -- floating "Combo xN" text
		Title: Color3, -- the player's title and newly unlocked titles
		ExpTrack: Color3, -- EXP bar background
		ExpFill: Color3,
		Pieces: { Color3 }, -- indexed by Piece.color (1..Config.COLOR_COUNT), then PVP garbage (Config.PVP.GARBAGE_COLOR)
		PieceOutlines: { Color3 }, -- the darker edge of each piece color
		Tiers: { [string]: Color3 }, -- the badge of each rank tier (Config.PVP.TIERS ids)
		RankUp: Color3, -- a rise in rank points
		RankDown: Color3, -- a fall in rank points
	},
	Transparency: {
		Overlay: number,
		TraySlot: number,
		TraySlotEmpty: number, -- a slot whose piece is in hand or placed
		Ghost: number, -- where the dragged piece would land
		PartnerAim: number, -- where the Co-op partner's held piece would land
		Blocked: number, -- a piece held with keys over cells it can't land on
		NoMoves: number, -- board dimmer at game over
	},
	Motion: { -- durations in seconds
		Pickup: number,
		Return: number,
		PlacePop: number,
		PlaceStep: number, -- between one cell of a placed piece and the next
		Land: number, -- the dropped piece gliding into its cells
		Clear: number,
		ClearStep: number, -- per cell of distance, as a clear spreads out from the placed piece
		Punch: number, -- the board settling after a clear of two lines or more
		Accent: number, -- the partner's piece's outline fading back to normal
		GhostGlide: number, -- the landing ghost moving from one cell to the next
		LinePop: number, -- a line the held piece would complete lighting up
		Deal: number, -- a new piece popping into the tray
		DealStep: number, -- between one tray slot and the next
		Turn: number, -- a piece turning in the tray
		WaitDelay: number, -- how long the tray stays empty before it shows it is waiting for a new set
		WaitPulse: number, -- one breath of an empty slot while it waits
		WaitStep: number, -- between one waiting slot's breath and the next
		SlotFade: number,
		Gain: number,
		ScoreCount: number, -- the score counting up to its new value
		ScorePop: number,
		FinalScoreCount: number, -- the final score counting up on the game over panel
		Panel: number, -- a panel or screen arriving
		Dim: number, -- the dimmer under a panel fading
		NoMovesFade: number,
		GameOverDelay: number, -- from the losing move to the game over panel
		HandMove: number, -- tutorial pointer sliding from the tray to the board
		HandPause: number,
		Tip: number, -- how long a tutorial tip stays up
		ExpFill: number, -- EXP bar filling up on the game over panel (per segment)
		ButtonPress: number,
		ButtonRelease: number,
	},
	Fonts: {
		Title: Font, -- headings, score, buttons (Fredoka)
		Body: Font, -- body text (Nunito Bold)
		Label: Font, -- small labels (Nunito ExtraBold)
	},
	TextSize: {
		ScoreMin: number,
		ScoreMax: number,
		HudLabelMin: number,
		HudLabelMax: number,
		GainMin: number,
		GainMax: number,
		HintMin: number,
		HintMax: number,
		MenuTitle: number,
		Label: number,
		Title: number,
		Button: number,
	},
	Radius: {
		Board: UDim,
		Cell: UDim,
		TraySlot: UDim,
		Panel: UDim,
		Button: UDim,
	},
	Stroke: { -- outline thickness in pixels
		Button: number,
		Panel: number,
		Pill: number,
	},
	Spacing: {
		ScreenPadding: UDim, -- around the whole layout
		Gap: UDim, -- between the HUD, board and tray
		BoardPadding: UDim, -- inside the board frame, around the grid
		CellInset: number, -- fraction of a cell left empty around each block
		TrayGap: UDim,
		TraySlotPadding: UDim, -- inside each tray slot, so a 5-cell piece doesn't touch the edges
		ButtonLip: number, -- pixels of the colored edge under a button
	},
	Images: { [string]: string }, -- rbxassetid:// of the exported mockup images (assets/)
	MinTouchTarget: Vector2,
}

local FREDOKA = "rbxasset://fonts/families/FredokaOne.json" -- one heavy weight, closest to Fredoka Bold
local NUNITO = "rbxasset://fonts/families/Nunito.json"

local Theme: Theme = {
	Text = {
		GameTitle = "ChikaBlocks",
		LogoLines = { "Chika", "Blocks" },
	},
	Colors = {
		Background = Color3.fromHex("#cfebff"),
		SkyBottom = Color3.fromHex("#fff1f6"),
		Cloud = Color3.fromHex("#f1f8ff"),
		Outline = Color3.fromHex("#4e3d4a"),
		Board = Color3.fromHex("#fffbf3"),
		CellEmpty = Color3.fromHex("#eaf4fb"),
		TraySlot = Color3.fromHex("#ffffff"),
		Text = Color3.fromHex("#4e3d4a"),
		TextMuted = Color3.fromHex("#7d6b78"),
		Overlay = Color3.fromHex("#4e3d4a"),
		Panel = Color3.fromHex("#fffbf3"),
		Button = Color3.fromHex("#ff9dbb"),
		ButtonShadow = Color3.fromHex("#e57fa0"),
		ButtonText = Color3.fromHex("#4e3d4a"),
		ButtonSecondary = Color3.fromHex("#a9dbff"),
		ButtonSecondaryShadow = Color3.fromHex("#62b2e8"),
		ButtonSecondaryText = Color3.fromHex("#2f4a66"),
		ButtonDisabled = Color3.fromHex("#d6eeff"),
		ButtonDisabledShadow = Color3.fromHex("#bddcf3"),
		ButtonDisabledText = Color3.fromHex("#9aa6b6"),
		ButtonDisabledOutline = Color3.fromHex("#a9a6b0"),
		RowBorder = Color3.fromHex("#ece2e8"),
		Lavender = Color3.fromHex("#f1ebfd"),
		PartnerCard = Color3.fromHex("#faf8ff"),
		Reward = Color3.fromHex("#ffd36e"),
		RewardShadow = Color3.fromHex("#e0a93a"),
		RewardText = Color3.fromHex("#4e3d4a"),
		MedalSilver = Color3.fromHex("#cfd8e3"),
		MedalBronze = Color3.fromHex("#e8956a"),
		Selection = Color3.fromHex("#ffd36e"),
		Hand = Color3.fromHex("#ffffff"),
		Gain = Color3.fromHex("#4e3d4a"),
		Combo = Color3.fromHex("#e0a93a"),
		Title = Color3.fromHex("#9f86e6"),
		ExpTrack = Color3.fromHex("#eaf4fb"),
		ExpFill = Color3.fromHex("#74c690"),
		Pieces = {
			Color3.fromHex("#ffe08a"), -- 1 butter (Dot)
			Color3.fromHex("#9fd8ff"), -- 2 sky (Bar)
			Color3.fromHex("#ffc4a0"), -- 3 peach (Corner)
			Color3.fromHex("#b4ebc4"), -- 4 mint (Block)
			Color3.fromHex("#ffb3c9"), -- 5 pink (L)
			Color3.fromHex("#cfbdff"), -- 6 lavender (T)
			Color3.fromHex("#9ee6e0"), -- 7 aqua (Zigzag)
			Color3.fromHex("#ff9e9e"), -- 8 coral (BigCorner)
			Color3.fromHex("#c9c3cd"), -- 9 garbage grey (PVP)
		},
		PieceOutlines = {
			Color3.fromHex("#e0b850"),
			Color3.fromHex("#62b2e8"),
			Color3.fromHex("#e8956a"),
			Color3.fromHex("#74c690"),
			Color3.fromHex("#e57fa0"),
			Color3.fromHex("#9f86e6"),
			Color3.fromHex("#5cc4bc"),
			Color3.fromHex("#e06a6a"),
			Color3.fromHex("#9d95a3"),
		},
		Tiers = {
			Bronze = Color3.fromHex("#e8956a"),
			Silver = Color3.fromHex("#cfd8e3"),
			Gold = Color3.fromHex("#ffd36e"),
			Platinum = Color3.fromHex("#9ee6e0"),
			Diamond = Color3.fromHex("#9fd8ff"),
			Master = Color3.fromHex("#cfbdff"),
		},
		RankUp = Color3.fromHex("#3f9a5c"),
		RankDown = Color3.fromHex("#c4566b"),
	},
	Transparency = {
		Overlay = 0.4,
		TraySlot = 0,
		TraySlotEmpty = 0.6,
		Ghost = 0.5,
		PartnerAim = 0.6,
		Blocked = 0.6,
		NoMoves = 0.45,
	},
	Motion = {
		Pickup = 0.14,
		Return = 0.18,
		PlacePop = 0.18,
		PlaceStep = 0.012,
		Land = 0.07,
		Clear = 0.22,
		ClearStep = 0.018,
		Punch = 0.22,
		Accent = 0.8,
		GhostGlide = 0.05,
		LinePop = 0.14,
		Deal = 0.22,
		DealStep = 0.05,
		Turn = 0.18,
		WaitDelay = 0.25, -- longer than a normal round trip, so a quick new set never flashes the effect
		WaitPulse = 0.5,
		WaitStep = 0.12,
		SlotFade = 0.12,
		Gain = 0.8,
		ScoreCount = 0.25,
		ScorePop = 0.2,
		FinalScoreCount = 0.6,
		Panel = 0.26,
		Dim = 0.16,
		NoMovesFade = 0.25,
		GameOverDelay = 0.8,
		HandMove = 1.0,
		HandPause = 0.5,
		Tip = 3,
		ExpFill = 0.6,
		ButtonPress = 0.06,
		ButtonRelease = 0.16,
	},
	Fonts = {
		Title = Font.new(FREDOKA),
		Body = Font.new(NUNITO, Enum.FontWeight.Bold),
		Label = Font.new(NUNITO, Enum.FontWeight.ExtraBold),
	},
	TextSize = {
		ScoreMin = 24,
		ScoreMax = 72,
		HudLabelMin = 14,
		HudLabelMax = 28,
		GainMin = 20,
		GainMax = 44,
		HintMin = 12,
		HintMax = 20,
		MenuTitle = 56,
		Label = 18,
		Title = 34,
		Button = 22,
	},
	Radius = {
		Board = UDim.new(0, 20),
		Cell = UDim.new(0.18, 0),
		TraySlot = UDim.new(0, 14),
		Panel = UDim.new(0, 24),
		Button = UDim.new(0, 18),
	},
	Stroke = {
		Button = 3,
		Panel = 3,
		Pill = 2,
	},
	Spacing = {
		ScreenPadding = UDim.new(0.02, 0),
		Gap = UDim.new(0.02, 0),
		BoardPadding = UDim.new(0.015, 0),
		CellInset = 0.08,
		TrayGap = UDim.new(0.03, 0),
		TraySlotPadding = UDim.new(0.08, 0),
		ButtonLip = 5,
	},
	Images = {
		Pause = "rbxassetid://106908472995505",
		Settings = "rbxassetid://122465849623180",
		Home = "rbxassetid://116096270975744",
		Replay = "rbxassetid://87647643240417",
		Trophy = "rbxassetid://95906368551480",
		Sound = "rbxassetid://124579777068793",
		Close = "rbxassetid://103108059044688",
		Crown = "rbxassetid://81606146791219",
		Hand = "rbxassetid://124249155588203",
		Sparkle = "rbxassetid://133617760185793",
		MascotHappy = "rbxassetid://118309270467534",
		MascotCheer = "rbxassetid://93948772498372",
		MascotSad = "rbxassetid://112838677243386",
	},
	MinTouchTarget = Vector2.new(44, 44),
}

return Theme
