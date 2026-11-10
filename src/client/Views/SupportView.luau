--!strict
-- Support screen over the menu, in the same style as the leaderboard: a cream card on the sky with a short
-- explanation, one button per donation tier (the price comes from Roblox), the top supporters and the player's
-- own total. Everything scrolls, so it works on short phone screens too. It only draws what SupportController
-- hands it; choosing a tier calls `onDonate(tier)`, and the server does the rest.
-- Closing works by the X button, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Clay = require("./Clay")
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

local SUPPORTERS_KEY = "Supporters_all"
local ROWS = 10 -- the server sends this many supporters
local ROW_HEIGHT = 44
local TIER_HEIGHT = 44 + Theme.Spacing.ButtonLip -- the face meets the minimum touch size; the lip comes on top
local CLOSE_SIZE = 44
local OPEN_START_SCALE = 0.94 -- the card grows from this as the screen opens
local PRESS_GAP_SECONDS = 2 -- a second press waits this long: the purchase prompt is opening
local THANKS_SECONDS = 6
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
}

export type Entry = { rank: number, userId: number, name: string, title: string?, value: number }
export type Snapshot = { boards: { [string]: { Entry } }, updatedAt: number, you: { donated: number } }

type Row = { frame: Frame, medal: Frame, rank: TextLabel, name: TextLabel, value: TextLabel }

local SupportView = {}
SupportView.__index = SupportView

export type SupportView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		tiers: { [number]: Frame }, -- tier -> Clay button, only for tiers that have a product
		rows: { Row },
		status: TextLabel,
		thanks: TextLabel,
		youPill: Frame,
		closeButton: TextButton,
		pop: UIScale,
		snapshot: Snapshot?,
		total: number?, -- what the player has given; fresher than the snapshot after a donation
		thanksToken: number,
		pressedAt: number,
		onClose: () -> (),
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	SupportView
))

local function text(
	name: string,
	value: string,
	font: Font,
	size: number,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = value,
	})
	for key, prop in props or {} do
		(label :: any)[key] = prop
	end
	return label
end

-- The color of the medal behind a rank: gold, silver, bronze, or nothing.
local function medalColor(rank: number): Color3?
	if rank == 1 then
		return Theme.Colors.Reward
	elseif rank == 2 then
		return Theme.Colors.MedalSilver
	elseif rank == 3 then
		return Theme.Colors.MedalBronze
	end
	return nil
end

local function newRow(index: number): Row
	local colors, fonts = Theme.Colors, Theme.Fonts
	local rank = text("Rank", "", fonts.Title, 16, colors.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	local medal = create("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = colors.Reward,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", {
			Color = colors.Outline,
			Thickness = Theme.Stroke.Pill,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
		}),
		rank,
	})
	local name = text("Name", "", fonts.Label, 16, colors.Text, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 48, 0.5, 0),
		Size = UDim2.new(1, -170, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local value = text("Value", "", fonts.Title, 18, colors.Text, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local frame = create("Frame", {
		Name = `Row{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = colors.CellEmpty,
		BackgroundTransparency = if index % 2 == 0 then 1 else 0,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		medal,
		name,
		value,
	})
	return { frame = frame, medal = medal, rank = rank, name = name, value = value }
end

-- What a tier's button says: its price, as Roblox lists it (the server publishes it as an attribute).
local function tierText(tier: number): string
	local price = ReplicatedStorage:GetAttribute(`DonatePrice{tier}`)
	return if typeof(price) == "number" then `R$ {Format.withCommas(price)}` else "Support"
end

function SupportView.new(playerGui: PlayerGui, onClose: () -> (), onDonate: (tier: number) -> ()): SupportView
	local colors, fonts = Theme.Colors, Theme.Fonts

	-- Opaque full-screen sky over the menu; the card sits in the safe area above it.
	local backdrop = create("ScreenGui", {
		Name = "SupportBackdrop",
		DisplayOrder = 12,
		ResetOnSpawn = false,
		Enabled = false,
	}, { Clay.sky("Fill", true) })
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local header = create("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
	}, {
		create("ImageLabel", {
			Name = "Crown",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
			Image = Theme.Images.Crown,
		}),
		text("Heading", "Support us", fonts.Title, Theme.TextSize.Title, colors.Text, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 46, 0.5, 0),
			Size = UDim2.new(1, -110, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	local intro = text(
		"Intro",
		"Enjoying ChikaBlocks? Chip in to support the developer. It gives no items; your name just appears on the Supporters board.",
		fonts.Body,
		15,
		colors.TextMuted,
		{
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Left,
		}
	)
	local thanks = text("Thanks", "", fonts.Title, 18, colors.Title, {
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
	})

	-- One button per tier that has a product, three to a row.
	local tiers: { [number]: Frame } = {}
	local grid = create("Frame", {
		Name = "Tiers",
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIGridLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			CellSize = UDim2.new(0.33, -6, 0, TIER_HEIGHT),
			CellPadding = UDim2.fromOffset(8, 8),
		}),
	})
	for tier, productId in Config.DONATE_PRODUCTS do
		if productId ~= 0 then
			local button = Clay.button({
				name = `Tier{tier}`,
				text = tierText(tier),
				style = "reward",
				order = tier,
				textSize = Theme.TextSize.Label,
			})
			button.Parent = grid
			tiers[tier] = button
		end
	end

	local rows = table.create(ROWS)
	local list = create("Frame", {
		Name = "Supporters",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	for i = 1, ROWS do
		rows[i] = newRow(i)
		rows[i].frame.Parent = list
	end
	local status = text("Status", "", fonts.Body, Theme.TextSize.Label, colors.TextMuted, {
		LayoutOrder = 6,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
	})

	local content = create("ScrollingFrame", {
		Name = "Content",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = true, -- the gamepad's stick scrolls it once selected
	}, {
		create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
		create("UIPadding", { PaddingRight = UDim.new(0, 10) }), -- clear of the scroll bar
		intro,
		thanks,
		grid,
		text("SupportersHeading", "Top supporters", fonts.Title, Theme.TextSize.Label, colors.Text, {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		list,
		status,
	})

	local youPill = Clay.pill({ name = "You", text = "", icon = Theme.Images.Crown, order = 1 })
	local youRow = create("Frame", {
		Name = "You",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		youPill,
	})

	local closeButton = Clay.iconButton({ name = "Close", image = Theme.Images.Close })
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	closeButton.ZIndex = 5

	local pop = create("UIScale", { Name = "Pop" })
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 1, -16),
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		pop,
		create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
		create("Frame", {
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			create("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			header,
			content,
			youRow,
		}),
		closeButton, -- on top of the body, outside its layout
	})
	local gui = create("ScreenGui", {
		Name = "Support",
		DisplayOrder = 13,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, { card })

	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		tiers = tiers,
		rows = rows,
		status = status,
		thanks = thanks,
		youPill = youPill,
		closeButton = closeButton,
		pop = pop,
		snapshot = nil,
		total = nil,
		thanksToken = 0,
		pressedAt = -math.huge,
		onClose = onClose,
		keyConnection = nil,
		connections = {},
	}, SupportView)

	for tier, button in tiers do
		table.insert(
			self.connections,
			Clay.face(button).Activated:Connect(function()
				local now = os.clock()
				if now - self.pressedAt < PRESS_GAP_SECONDS then
					return
				end
				self.pressedAt = now
				onDonate(tier)
			end)
		)
		-- The prices arrive from the server after the game has loaded.
		table.insert(
			self.connections,
			ReplicatedStorage:GetAttributeChangedSignal(`DonatePrice{tier}`):Connect(function()
				Clay.face(button).Text = tierText(tier)
			end)
		)
	end
	table.insert(self.connections, closeButton.Activated:Connect(onClose))

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	self:render()
	return self
end

-- Draws the supporters and the player's total from the last snapshot (or "Loading…" before one arrives).
function SupportView.render(self: SupportView)
	local snapshot = self.snapshot
	local entries = if snapshot then snapshot.boards[SUPPORTERS_KEY] else nil
	local me = Players.LocalPlayer.UserId
	for i, row in self.rows do
		local entry = entries and entries[i]
		row.frame.Visible = entry ~= nil
		if entry then
			local medal = medalColor(entry.rank)
			row.medal.BackgroundTransparency = if medal then 0 else 1
			(row.medal:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = medal ~= nil
			if medal then
				row.medal.BackgroundColor3 = medal
			end
			row.rank.Text = tostring(entry.rank)
			row.name.Text = entry.name
			row.value.Text = `R$ {Format.withCommas(entry.value)}`
			-- The player's own row stands out in gold; the others alternate pale stripes.
			local isMe = entry.userId == me
			row.frame.BackgroundColor3 = if isMe then Theme.Colors.Reward else Theme.Colors.CellEmpty
			row.frame.BackgroundTransparency = if isMe then 0.35 elseif i % 2 == 0 then 1 else 0
		end
	end

	local youLabel = Clay.pillLabel(self.youPill)
	if not snapshot then
		self.status.Text = "Loading…"
		youLabel.Text = "—"
		return
	end
	self.status.Text = if entries and #entries > 0 then "" else "Nobody yet. Be the first supporter!"
	self.status.Visible = self.status.Text ~= ""
	youLabel.Text = `Your total: R$ {Format.withCommas(self.total or snapshot.you.donated)}`
end

function SupportView.setSnapshot(self: SupportView, snapshot: Snapshot)
	self.snapshot = snapshot
	self.total = nil -- the snapshot knows the latest total
	self:render()
end

-- A donation went through: thank the player for a few seconds and show their new total.
function SupportView.showThanks(self: SupportView, amount: number, total: number)
	self.thanksToken += 1
	local token = self.thanksToken
	self.total = total
	self.thanks.Text = if amount > 0
		then `Thank you! R$ {Format.withCommas(amount)} received.`
		else "Thank you for your support!"
	self.thanks.Visible = true
	self.pressedAt = -math.huge -- another tier can be picked right away
	self:render()
	task.delay(THANKS_SECONDS, function()
		if token == self.thanksToken then
			self.thanks.Visible = false
		end
	end)
end

function SupportView.open(self: SupportView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	Clay.popIn(self.pop, OPEN_START_SCALE, Theme.Motion.Panel)
	for tier, button in self.tiers do
		Clay.face(button).Text = tierText(tier)
	end
	self:render()
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		local first = next(self.tiers)
		if first then
			GuiService.SelectedObject = Clay.face(self.tiers[first])
		end
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and CLOSE_KEYS[input.KeyCode] then
				self.onClose()
			end
		end)
	end
end

function SupportView.close(self: SupportView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	self.thanks.Visible = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function SupportView.isOpen(self: SupportView): boolean
	return self.gui.Enabled
end

-- For the Studio debug bridge: the tier buttons and the visible rows as lines.
function SupportView.describe(self: SupportView): string
	local labels = {}
	for tier = 1, #Config.DONATE_PRODUCTS do
		local button = self.tiers[tier]
		table.insert(labels, if button then Clay.face(button).Text else "-")
	end
	local lines = {
		`tiers: {table.concat(labels, " | ")}`,
		`status="{self.status.Text}" thanks="{if self.thanks.Visible then self.thanks.Text else ""}" you="{Clay.pillLabel(
			self.youPill
		).Text}"`,
	}
	for _, row in self.rows do
		if row.frame.Visible then
			table.insert(lines, `#{row.rank.Text} {row.name.Text} {row.value.Text}`)
		end
	end
	return table.concat(lines, "\n")
end

return SupportView
