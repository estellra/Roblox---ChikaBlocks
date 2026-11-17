--!strict
-- The ranked queue screen over the menu (mockups 08-queue-searching and 09-queue-empty-options), in the style of the
-- Co-op screen: a cream card with the player's rank, three bouncing dots and "Finding an opponent…", how long they have
-- waited and how many others could be matched here, and Cancel. After a while with nobody to play it offers Keep
-- waiting, Practice vs bot and Invite friends. A player who can't queue sees why instead. It only draws what
-- QueueController hands it (setState) and reports presses.
-- Closing works by the X button, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Clay = require("./Clay")
local RankBadge = require("./RankBadge")
local Theme = require("./Theme")
local create = require("./Create")

local CARD_WIDTH = 520
local BUTTON_HEIGHT = 52 + Theme.Spacing.ButtonLip
local CLOSE_SIZE = 44
local BADGE_SIZE = 44
local DOT_SIZE = 12
local DOT_COLORS = { Theme.Colors.Button, Theme.Colors.Reward, Theme.Colors.ButtonSecondaryShadow }
local OPEN_START_SCALE = 0.94
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
}

export type State = {
	tier: string,
	rankLine: string, -- "Gold · 1,320"
	recordLine: string, -- "14W 9L · Season 2026M12"
	searching: boolean, -- in the queue: the dots bounce and Cancel shows
	status: string, -- "Finding an opponent…", or why the player can't queue
	waitedLine: string, -- "Waited 0:12 · 3 other players can be matched here"; "" hides it
	offer: boolean, -- nobody to play: Keep waiting, Practice vs bot, Invite friends
	canInviteFriends: boolean,
}

export type Callbacks = {
	onClose: () -> (),
	onKeepWaiting: () -> (),
	onPractice: () -> (),
	onInviteFriends: () -> (),
}

local QueueView = {}
QueueView.__index = QueueView

export type QueueView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		pop: UIScale,
		badge: Frame,
		rankLabel: TextLabel,
		recordLabel: TextLabel,
		dots: Frame,
		dotTweens: { Tween },
		statusLabel: TextLabel,
		waitedLabel: TextLabel,
		offerNote: TextLabel,
		cancelRoot: Frame,
		keepRoot: Frame,
		practiceRoot: Frame,
		friendsRoot: Frame,
		callbacks: Callbacks,
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	QueueView
))

local function label(name: string, order: number, font: Font, size: number, color: Color3): TextLabel
	return create("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = true,
		Text = "",
	})
end

local function button(name: string, text: string, style: Clay.ButtonStyle, order: number, width: number): Frame
	return Clay.button({
		name = name,
		text = text,
		style = style,
		order = order,
		size = UDim2.new(width, 0, 0, BUTTON_HEIGHT),
		textSize = Theme.TextSize.Label + 2,
	})
end

function QueueView.new(playerGui: PlayerGui, callbacks: Callbacks): QueueView
	local colors, fonts = Theme.Colors, Theme.Fonts

	local backdrop = create("ScreenGui", {
		Name = "QueueBackdrop",
		DisplayOrder = 12,
		ResetOnSpawn = false,
		Enabled = false,
	}, { Clay.sky("Fill", true) })
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local badge = RankBadge.new(BADGE_SIZE, "Silver", 1)
	local rankLabel = create("TextLabel", {
		Name = "Rank",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 22,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local recordLabel = create("TextLabel", {
		Name = "Record",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = fonts.Label,
		TextSize = 14,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local rankRow = create("Frame", {
		Name = "RankRow",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
		}),
		badge,
		create("Frame", {
			Name = "Text",
			LayoutOrder = 2,
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			rankLabel,
			recordLabel,
		}),
	})

	local dots = create("Frame", {
		Name = "Dots",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(3 * DOT_SIZE + 2 * 10, DOT_SIZE + 8),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	for i, color in DOT_COLORS do
		create("Frame", {
			Name = `Dot{i}`,
			LayoutOrder = i,
			Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = dots,
		}, {
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke", { Color = colors.Outline, Thickness = 1.5 }),
			create("UIScale", {}),
		})
	end

	local statusLabel = label("Status", 4, fonts.Title, 20, colors.Text)
	local waitedLabel = label("Waited", 5, fonts.Label, 14, colors.TextMuted)
	local offerNote = label("Offer", 6, fonts.Label, 15, colors.Title)
	offerNote.Text = "Nobody to play right now. You can keep waiting, or:"
	local cancelRoot = button("Cancel", "Cancel", "secondary", 7, 0.5)
	local keepRoot = button("KeepWaiting", "Keep waiting", "secondary", 8, 1)
	local practiceRoot = button("Practice", "Practice vs bot", "primary", 9, 1)
	local friendsRoot = button("InviteFriends", "Invite friends", "secondary", 10, 1)

	local closeButton = Clay.iconButton({ name = "Close", image = Theme.Images.Close })
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	closeButton.ZIndex = 5

	local pop = create("UIScale", { Name = "Pop" })
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		pop,
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UISizeConstraint", { MaxSize = Vector2.new(CARD_WIDTH, math.huge) }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 22),
			PaddingLeft = UDim.new(0, 22),
			PaddingRight = UDim.new(0, 22),
		}),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		create("TextLabel", {
			Name = "Heading",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			FontFace = fonts.Title,
			TextSize = Theme.TextSize.Title,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Ranked",
		}),
		rankRow,
		dots,
		statusLabel,
		waitedLabel,
		offerNote,
		cancelRoot,
		keepRoot,
		practiceRoot,
		friendsRoot,
	})
	local gui = create("ScreenGui", {
		Name = "Queue",
		DisplayOrder = 13,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, { card })
	-- The close button sits in the heading's row, at the card's corner (outside the list's layout).
	closeButton.Position = UDim2.new(1, 10, 0, -6)
	closeButton.Parent = card:FindFirstChild("Heading")

	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		pop = pop,
		badge = badge,
		rankLabel = rankLabel,
		recordLabel = recordLabel,
		dots = dots,
		dotTweens = {},
		statusLabel = statusLabel,
		waitedLabel = waitedLabel,
		offerNote = offerNote,
		cancelRoot = cancelRoot,
		keepRoot = keepRoot,
		practiceRoot = practiceRoot,
		friendsRoot = friendsRoot,
		callbacks = callbacks,
		keyConnection = nil,
		connections = {},
	}, QueueView)
	table.insert(self.connections, closeButton.Activated:Connect(callbacks.onClose))
	table.insert(self.connections, Clay.face(cancelRoot).Activated:Connect(callbacks.onClose))
	table.insert(self.connections, Clay.face(keepRoot).Activated:Connect(callbacks.onKeepWaiting))
	table.insert(self.connections, Clay.face(practiceRoot).Activated:Connect(callbacks.onPractice))
	table.insert(self.connections, Clay.face(friendsRoot).Activated:Connect(callbacks.onInviteFriends))
	backdrop.Parent = playerGui
	gui.Parent = playerGui
	return self
end

local function bounce(self: QueueView, on: boolean)
	for _, tween in self.dotTweens do
		tween:Cancel()
	end
	table.clear(self.dotTweens)
	for index, dot in self.dots:GetChildren() do
		local scale = dot:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1
			if on then
				local info =
					TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, index * 0.12)
				local tween = TweenService:Create(scale, info, { Scale = 1.35 })
				table.insert(self.dotTweens, tween)
				tween:Play()
			end
		end
	end
end

--- Draws the screen from `state`.
function QueueView.setState(self: QueueView, state: State)
	RankBadge.paint(self.badge, state.tier)
	self.rankLabel.Text = state.rankLine
	self.recordLabel.Text = state.recordLine
	self.statusLabel.Text = state.status
	self.waitedLabel.Text = state.waitedLine
	self.waitedLabel.Visible = state.waitedLine ~= ""
	self.dots.Visible = state.searching
	local offer = state.searching and state.offer
	self.offerNote.Visible = offer
	self.keepRoot.Visible = offer
	self.practiceRoot.Visible = offer
	self.friendsRoot.Visible = offer and state.canInviteFriends
	self.cancelRoot.Visible = state.searching and not offer
	if state.searching ~= (#self.dotTweens > 0) then
		bounce(self, state.searching and self.gui.Enabled)
	end
end

function QueueView.open(self: QueueView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	Clay.popIn(self.pop, OPEN_START_SCALE, Theme.Motion.Panel)
	bounce(self, self.dots.Visible)
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and CLOSE_KEYS[input.KeyCode] then
				self.callbacks.onClose()
			end
		end)
	end
end

function QueueView.close(self: QueueView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	bounce(self, false)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function QueueView.isOpen(self: QueueView): boolean
	return self.gui.Enabled
end

--- For the Studio debug bridge.
function QueueView.describe(self: QueueView): string
	local buttons = {}
	for _, root in { self.cancelRoot, self.keepRoot, self.practiceRoot, self.friendsRoot } do
		if root.Visible then
			table.insert(buttons, root.Name)
		end
	end
	return `open={self.gui.Enabled} rank="{self.rankLabel.Text}" record="{self.recordLabel.Text}" status="{self.statusLabel.Text}" waited="{self.waitedLabel.Text}" buttons={table.concat(
		buttons,
		","
	)}`
end

return QueueView
