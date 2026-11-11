--!strict
-- Invitation notices: a small card for the oldest open invitation, with Accept and Decline and a bar running down
-- to the moment it expires; a "+2" in its corner says others are waiting behind it. The card sits above
-- everything else, so an invitation shows up on the menu, on the Support screen and in the middle of a solo run
-- alike, and it is placed over the score area (setAnchor) so it never covers the board or the tray.
-- CoopController owns what is shown; this only draws.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Clay = require("./Clay")
local Theme = require("./Theme")
local create = require("./Create")

local MAX_WIDTH = 300
local MIN_WIDTH = 240
local TOP_MARGIN = 8 -- below the top of the screen when there is no anchor
local BUTTON_HEIGHT = 44 + Theme.Spacing.ButtonLip -- the face meets the minimum touch size; the lip comes on top
local BAR_HEIGHT = 6
local ARRIVE_START_SCALE = 0.9

type Toast = {
	id: number,
	frame: Frame,
	more: TextLabel,
	bar: Frame,
	pop: UIScale,
	countdown: Tween,
	connections: { RBXScriptConnection },
}

local CoopInviteView = {}
CoopInviteView.__index = CoopInviteView

export type CoopInviteView = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		holder: Frame,
		toasts: { Toast }, -- oldest first; only the first is shown
		anchorPosition: Vector2?, -- the area the card is centered over (the score area), in this screen's pixels
		anchorSize: Vector2?,
		onAnswer: (inviteId: number, accept: boolean) -> (),
	},
	CoopInviteView
))

function CoopInviteView.new(playerGui: PlayerGui, onAnswer: (inviteId: number, accept: boolean) -> ()): CoopInviteView
	local holder = create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
		Size = UDim2.fromScale(0.94, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(MAX_WIDTH, math.huge) }),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local gui = create("ScreenGui", {
		Name = "CoopInvites",
		DisplayOrder = 20,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, { holder })
	gui.Parent = playerGui
	return setmetatable({
		gui = gui,
		holder = holder,
		toasts = {},
		anchorPosition = nil,
		anchorSize = nil,
		onAnswer = onAnswer,
	}, CoopInviteView)
end

-- Puts the card over the middle of the top of this area (nil goes back to the top middle of the screen).
function CoopInviteView.setAnchor(self: CoopInviteView, position: Vector2?, size: Vector2?)
	self.anchorPosition, self.anchorSize = position, size
	local limit = self.holder:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	if position and size then
		local width = math.clamp(size.X, MIN_WIDTH, MAX_WIDTH)
		self.holder.AnchorPoint = Vector2.zero
		self.holder.Position = UDim2.fromOffset(math.max(0, position.X + (size.X - width) / 2), position.Y)
		self.holder.Size = UDim2.fromOffset(width, 0)
		limit.MaxSize = Vector2.new(width, math.huge)
	else
		self.holder.AnchorPoint = Vector2.new(0.5, 0)
		self.holder.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN)
		self.holder.Size = UDim2.fromScale(0.94, 0)
		limit.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	end
end

-- Shows the oldest card and counts the ones waiting behind it.
local function refresh(self: CoopInviteView)
	for index, toast in self.toasts do
		toast.frame.Visible = index == 1
		toast.more.Text = if index == 1 and #self.toasts > 1 then `+{#self.toasts - 1}` else ""
	end
	self.gui.Enabled = #self.toasts > 0
end

local function destroyToast(self: CoopInviteView, toast: Toast)
	local index = table.find(self.toasts, toast)
	if index then
		table.remove(self.toasts, index)
	end
	toast.countdown:Cancel()
	toast.countdown:Destroy()
	for _, connection in toast.connections do
		connection:Disconnect()
	end
	toast.frame:Destroy()
	refresh(self)
end

-- Adds an invitation from `name` that runs out `seconds` from now. Another notice for the same id replaces it.
function CoopInviteView.add(self: CoopInviteView, id: number, name: string, seconds: number)
	self:remove(id)
	local colors, fonts = Theme.Colors, Theme.Fonts

	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -32, 1, 0),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 17,
		TextColor3 = colors.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{name} invites you to Co-op`,
	})
	local more = create("TextLabel", {
		Name = "More",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(30, 22),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 15,
		TextColor3 = colors.Title,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local heading = create("Frame", {
		Name = "Heading",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
	}, { title, more })
	local decline = Clay.button({
		name = "Decline",
		text = "Decline",
		style = "secondary",
		order = 1,
		size = UDim2.new(0.5, -4, 1, 0),
		textSize = Theme.TextSize.Label,
	})
	local accept = Clay.button({
		name = "Accept",
		text = "Accept",
		style = "primary",
		order = 2,
		size = UDim2.new(0.5, -4, 1, 0),
		textSize = Theme.TextSize.Label,
	})
	local buttons = create("Frame", {
		Name = "Buttons",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		decline,
		accept,
	})
	local bar = create("Frame", {
		Name = "Bar",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Title,
		BorderSizePixel = 0,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local track = create("Frame", {
		Name = "Track",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = colors.ExpTrack,
		BorderSizePixel = 0,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), bar })
	local pop = create("UIScale", { Name = "Pop" })
	local frame = create("Frame", {
		Name = `Invite{id}`,
		LayoutOrder = id,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		pop,
		heading,
		buttons,
		track,
	})

	-- The bar starts at what is left of the invitation's whole length and runs down to nothing.
	local total = Config.COOP.INVITE_SECONDS
	local left = math.clamp(seconds, 0, total)
	bar.Size = UDim2.fromScale(left / total, 1)
	local countdown =
		TweenService:Create(bar, TweenInfo.new(left, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })

	local toast: Toast =
		{ id = id, frame = frame, more = more, bar = bar, pop = pop, countdown = countdown, connections = {} }
	table.insert(
		toast.connections,
		Clay.face(accept).Activated:Connect(function()
			self.onAnswer(id, true)
			self:remove(id)
		end)
	)
	table.insert(
		toast.connections,
		Clay.face(decline).Activated:Connect(function()
			self.onAnswer(id, false)
			self:remove(id)
		end)
	)
	table.insert(
		toast.connections,
		countdown.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				self:remove(id) -- ran out; the server says so too
			end
		end)
	)

	table.insert(self.toasts, toast)
	frame.Parent = self.holder
	refresh(self)
	if #self.toasts == 1 then
		Clay.popIn(pop, ARRIVE_START_SCALE, Theme.Motion.Panel)
	end
	countdown:Play()
end

function CoopInviteView.remove(self: CoopInviteView, id: number)
	for _, toast in table.clone(self.toasts) do
		if toast.id == id then
			destroyToast(self, toast)
		end
	end
end

function CoopInviteView.clear(self: CoopInviteView)
	for _, toast in table.clone(self.toasts) do
		destroyToast(self, toast)
	end
end

function CoopInviteView.count(self: CoopInviteView): number
	return #self.toasts
end

-- For the Studio debug bridge: each notice with its text and the share of the bar left, and where the first sits.
function CoopInviteView.describe(self: CoopInviteView): string
	local lines = {}
	for _, toast in self.toasts do
		local title = toast.frame:FindFirstChild("Title", true) :: TextLabel
		local position, size = toast.frame.AbsolutePosition, toast.frame.AbsoluteSize
		table.insert(
			lines,
			`#{toast.id} "{title.Text}" more="{toast.more.Text}" visible={toast.frame.Visible} bar={string.format(
				"%.2f",
				toast.bar.Size.X.Scale
			)} at {position.X // 1},{position.Y // 1} size {size.X // 1}x{size.Y // 1}`
		)
	end
	return if #lines > 0 then table.concat(lines, "\n") else "no invitations shown"
end

return CoopInviteView
