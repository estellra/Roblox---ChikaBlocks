--!strict
-- Design tokens. Views read colors, fonts, text sizes, radii and spacing only from here, so the final look
-- (phase 2 mockups) or a purchasable theme (phase 4) changes these values without touching view code.
-- These are gray-box placeholder values.

export type Theme = {
	Colors: {
		Background: Color3,
		Board: Color3,
		CellEmpty: Color3,
		TraySlot: Color3,
		Text: Color3,
		TextMuted: Color3,
		Overlay: Color3,
		Panel: Color3,
		Button: Color3,
		ButtonText: Color3,
		Gain: Color3, -- floating "+points" text
		Combo: Color3, -- floating "Combo xN" text
		Pieces: { Color3 }, -- indexed by Piece.color (1..Config.COLOR_COUNT)
	},
	Transparency: {
		Overlay: number,
		TraySlot: number,
		Ghost: number, -- where the dragged piece would land
		NoMoves: number, -- board dimmer at game over
	},
	Motion: { -- durations in seconds
		Pickup: number,
		Return: number,
		PlacePop: number,
		Clear: number,
		Gain: number,
		NoMovesFade: number,
		GameOverDelay: number, -- from the losing move to the game over panel
	},
	Fonts: {
		Title: Font,
		Body: Font,
	},
	TextSize: {
		ScoreMin: number,
		ScoreMax: number,
		HudLabelMin: number,
		HudLabelMax: number,
		GainMin: number,
		GainMax: number,
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
	Spacing: {
		ScreenPadding: UDim, -- around the whole layout
		Gap: UDim, -- between the HUD, board and tray
		BoardPadding: UDim, -- inside the board frame, around the grid
		CellInset: number, -- fraction of a cell left empty around each block
		TrayGap: UDim,
		TraySlotPadding: UDim, -- inside each tray slot, so a 5-cell piece doesn't touch the edges
	},
	MinTouchTarget: Vector2,
}

local BUILDER_SANS = "rbxasset://fonts/families/BuilderSans.json"

local Theme: Theme = {
	Colors = {
		Background = Color3.fromRGB(34, 36, 44),
		Board = Color3.fromRGB(48, 51, 62),
		CellEmpty = Color3.fromRGB(62, 66, 80),
		TraySlot = Color3.fromRGB(48, 51, 62),
		Text = Color3.fromRGB(240, 240, 245),
		TextMuted = Color3.fromRGB(160, 164, 180),
		Overlay = Color3.fromRGB(0, 0, 0),
		Panel = Color3.fromRGB(56, 60, 74),
		Button = Color3.fromRGB(96, 168, 255),
		ButtonText = Color3.fromRGB(20, 22, 28),
		Gain = Color3.fromRGB(240, 240, 245),
		Combo = Color3.fromRGB(255, 214, 102),
		Pieces = {
			Color3.fromRGB(255, 214, 102), -- Dot
			Color3.fromRGB(102, 204, 255), -- Bar
			Color3.fromRGB(255, 153, 102), -- Corner
			Color3.fromRGB(153, 230, 128), -- Block
			Color3.fromRGB(255, 128, 170), -- L
			Color3.fromRGB(190, 150, 255), -- T
			Color3.fromRGB(102, 230, 204), -- Zigzag
			Color3.fromRGB(255, 110, 110), -- BigCorner
		},
	},
	Transparency = {
		Overlay = 0.35,
		TraySlot = 0.4,
		Ghost = 0.5,
		NoMoves = 0.45,
	},
	Motion = {
		Pickup = 0.1,
		Return = 0.15,
		PlacePop = 0.15,
		Clear = 0.2,
		Gain = 0.8,
		NoMovesFade = 0.25,
		GameOverDelay = 0.8,
	},
	Fonts = {
		Title = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
		Body = Font.new(BUILDER_SANS, Enum.FontWeight.Medium),
	},
	TextSize = {
		ScoreMin = 24,
		ScoreMax = 72,
		HudLabelMin = 14,
		HudLabelMax = 28,
		GainMin = 20,
		GainMax = 44,
		Label = 18,
		Title = 34,
		Button = 22,
	},
	Radius = {
		Board = UDim.new(0, 12),
		Cell = UDim.new(0.18, 0),
		TraySlot = UDim.new(0, 10),
		Panel = UDim.new(0, 16),
		Button = UDim.new(0, 10),
	},
	Spacing = {
		ScreenPadding = UDim.new(0.02, 0),
		Gap = UDim.new(0.02, 0),
		BoardPadding = UDim.new(0.015, 0),
		CellInset = 0.08,
		TrayGap = UDim.new(0.03, 0),
		TraySlotPadding = UDim.new(0.08, 0),
	},
	MinTouchTarget = Vector2.new(44, 44),
}

return Theme
