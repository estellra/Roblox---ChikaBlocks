--!strict
-- Co-op screen over the menu, in the same style as the Support and leaderboard screens: a cream card on the sky
-- with the other players in the server, one Invite button each, and the room the player is in. It only draws
-- what CoopController hands it (setState) and reports presses; the server decides everything.
-- Closing works by the X button, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Clay = require("./Clay")
local Theme = require("./Theme")
local create = require("./Create")

local ROW_HEIGHT = 44 + Theme.Spacing.ButtonLip + 8 -- the button meets the minimum touch size; the lip comes on top
local BUTTON_WIDTH = 112
local CLOSE_SIZE = 44
local OPEN_START_SCALE = 0.94 -- the card grows from this as the screen opens
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
}

-- Why somebody can't be invited, as their button says it (the server publishes it as the CoopBusy attribute).
local BUSY_TEXT: { [string]: string } = {
	room = "In a room",
	tutorial = "In tutorial",
	loading = "Joining…",
}

export type Person = { userId: number, name: string, level: number?, busy: string? }

export type State = {
	people: { Person },
	inRoom: boolean,
	partnerName: string?, -- the other player of the room
	partnerLeft: boolean,
	invitingUserId: number?, -- who the player has an invitation out to
	myBusy: string?, -- why the player can't invite right now: "tutorial" or "loading" (in a room is inRoom)
	status: string?, -- how the last invitation ended
	canInviteFriends: boolean,
}

type Callbacks = {
	onClose: () -> (),
	onInvite: (userId: number) -> (),
	onCancel: () -> (),
	onLeave: () -> (),
	onInviteFriends: () -> (),
}

type Row = {
	frame: Frame,
	name: TextLabel,
	level: TextLabel,
	button: Frame,
	face: TextButton,
	userId: number,
	action: ("invite" | "cancel")?, -- what pressing the button does; nil when it is disabled
}

local CoopView = {}
CoopView.__index = CoopView

export type CoopView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		list: Frame,
		rows: { Row },
		roomCard: Frame,
		roomText: TextLabel,
		note: TextLabel,
		status: TextLabel,
		empty: Frame,
		friendsButton: Frame,
		leaveButton: Frame,
		closeButton: TextButton,
		pop: UIScale,
		state: State,
		callbacks: Callbacks,
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	CoopView
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

-- A paragraph that wraps and grows with its text.
local function paragraph(name: string, order: number, font: Font, size: number, color: Color3): TextLabel
	return text(name, "", font, size, color, {
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- Dimmed and unpressable, or back to normal.
local function setEnabled(face: TextButton, enabled: boolean)
	face.Active = enabled
	face.Selectable = enabled
	face.BackgroundTransparency = if enabled then 0 else 0.55
	face.TextTransparency = if enabled then 0 else 0.45
end

local function newRow(index: number): Row
	local colors, fonts = Theme.Colors, Theme.Fonts
	local name = text("Name", "", fonts.Label, 17, colors.Text, {
		LayoutOrder = 1,
		Size = UDim2.fromScale(0, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local level = text("Level", "", fonts.Label, 15, colors.TextMuted, {
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
	})
	local button = Clay.button({
		name = "Action",
		text = "Invite",
		style = "primary",
		order = 3,
		size = UDim2.fromOffset(BUTTON_WIDTH, 44 + Theme.Spacing.ButtonLip),
		textSize = Theme.TextSize.Label,
	})
	local frame = create("Frame", {
		Name = `Person{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = colors.CellEmpty,
		BackgroundTransparency = if index % 2 == 0 then 1 else 0,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		name,
		level,
		button,
	})
	-- The name takes whatever width the level and button leave.
	create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = name })
	return { frame = frame, name = name, level = level, button = button, face = Clay.face(button), userId = 0 }
end

function CoopView.new(playerGui: PlayerGui, callbacks: Callbacks): CoopView
	local colors, fonts = Theme.Colors, Theme.Fonts

	-- Opaque full-screen sky over the menu; the card sits in the safe area above it.
	local backdrop = create("ScreenGui", {
		Name = "CoopBackdrop",
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
		text("Heading", "Co-op", fonts.Title, Theme.TextSize.Title, colors.Text, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, -60, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	local intro = paragraph("Intro", 1, fonts.Body, 15, colors.TextMuted)
	intro.Text = "Team up on one board. Invite someone who is in this server."
	local note = paragraph("Note", 2, fonts.Body, 15, colors.Title)
	local status = paragraph("Status", 3, fonts.Title, 16, colors.Title)

	local roomText = paragraph("RoomText", 1, fonts.Title, 18, colors.Text)
	local leaveRoot = Clay.button({
		name = "Leave",
		text = "Leave room",
		style = "secondary",
		order = 2,
		size = UDim2.new(1, 0, 0, 44 + Theme.Spacing.ButtonLip),
		textSize = Theme.TextSize.Label,
	})
	local roomCard = create("Frame", {
		Name = "Room",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Reward,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		roomText,
		leaveRoot,
	})

	local list = create("Frame", {
		Name = "People",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})

	local friendsRoot = Clay.button({
		name = "InviteFriends",
		text = "Invite friends",
		style = "primary",
		order = 2,
		size = UDim2.new(1, 0, 0, 44 + Theme.Spacing.ButtonLip),
		textSize = Theme.TextSize.Label,
	})
	friendsRoot.Visible = false
	local empty = create("Frame", {
		Name = "Empty",
		LayoutOrder = 6,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
		text("Message", "No one else is here yet.", fonts.Title, 18, colors.Text, {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		friendsRoot,
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
		note,
		status,
		roomCard,
		list,
		empty,
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
		}),
		closeButton, -- on top of the body, outside its layout
	})
	local gui = create("ScreenGui", {
		Name = "Coop",
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
		list = list,
		rows = {},
		roomCard = roomCard,
		roomText = roomText,
		note = note,
		status = status,
		empty = empty,
		friendsButton = friendsRoot,
		leaveButton = leaveRoot,
		closeButton = closeButton,
		pop = pop,
		state = {
			people = {},
			inRoom = false,
			partnerName = nil,
			partnerLeft = false,
			invitingUserId = nil,
			myBusy = nil,
			status = nil,
			canInviteFriends = false,
		},
		callbacks = callbacks,
		keyConnection = nil,
		connections = {},
	}, CoopView)

	table.insert(self.connections, closeButton.Activated:Connect(callbacks.onClose))
	table.insert(self.connections, Clay.face(leaveRoot).Activated:Connect(callbacks.onLeave))
	table.insert(self.connections, Clay.face(friendsRoot).Activated:Connect(callbacks.onInviteFriends))

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	self:render()
	return self
end

-- A row for each person, made when first needed and reused afterwards.
local function rowAt(self: CoopView, index: number): Row
	local row = self.rows[index]
	if not row then
		row = newRow(index)
		row.frame.Parent = self.list
		table.insert(
			self.connections,
			row.face.Activated:Connect(function()
				if row.action == "invite" then
					self.callbacks.onInvite(row.userId)
				elseif row.action == "cancel" then
					self.callbacks.onCancel()
				end
			end)
		)
		self.rows[index] = row
	end
	return row
end

-- What a person's button says and whether it can be pressed, given who the player is already inviting.
local function setAction(row: Row, person: Person, state: State)
	if state.invitingUserId == person.userId then
		row.action = "cancel"
		row.face.Text = "Cancel"
		Clay.setStyle(row.button, "secondary")
		setEnabled(row.face, true)
		return
	end
	Clay.setStyle(row.button, "primary")
	if person.busy ~= nil then
		row.action = nil
		row.face.Text = BUSY_TEXT[person.busy] or "Busy"
		setEnabled(row.face, false)
	elseif state.inRoom or state.myBusy ~= nil or state.invitingUserId ~= nil then
		row.action = nil -- the player can't invite anyone right now
		row.face.Text = "Invite"
		setEnabled(row.face, false)
	else
		row.action = "invite"
		row.face.Text = "Invite"
		setEnabled(row.face, true)
	end
end

-- Draws the whole screen from the last state.
function CoopView.render(self: CoopView)
	local state = self.state

	self.roomCard.Visible = state.inRoom
	if state.inRoom then
		self.roomText.Text = if state.partnerLeft
			then "Your partner left the room."
			else `In a room with {state.partnerName or "your partner"}.`
	end

	local note = if state.inRoom
		then ""
		elseif state.myBusy == "tutorial" then "Finish the tutorial to play Co-op."
		elseif state.myBusy == "loading" then "Loading your data…"
		else ""
	self.note.Text = note
	self.note.Visible = note ~= ""
	self.status.Text = state.status or ""
	self.status.Visible = self.status.Text ~= ""

	for index, person in state.people do
		local row = rowAt(self, index)
		row.userId = person.userId
		row.name.Text = person.name
		row.level.Text = if person.level then `Lv {person.level}` else ""
		row.frame.Visible = true
		setAction(row, person, state)
	end
	for index = #state.people + 1, #self.rows do
		self.rows[index].frame.Visible = false
		self.rows[index].action = nil
	end

	self.empty.Visible = #state.people == 0
	self.friendsButton.Visible = state.canInviteFriends
end

function CoopView.setState(self: CoopView, state: State)
	self.state = state
	self:render()
end

function CoopView.open(self: CoopView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	Clay.popIn(self.pop, OPEN_START_SCALE, Theme.Motion.Panel)
	self:render()
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		for _, row in self.rows do
			if row.frame.Visible and row.action ~= nil then
				GuiService.SelectedObject = row.face
				break
			end
		end
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and CLOSE_KEYS[input.KeyCode] then
				self.callbacks.onClose()
			end
		end)
	end
end

function CoopView.close(self: CoopView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function CoopView.isOpen(self: CoopView): boolean
	return self.gui.Enabled
end

-- For the Studio debug bridge: the notes, the room and each person with what their button says.
function CoopView.describe(self: CoopView): string
	local room = if self.roomCard.Visible then `"{self.roomText.Text}"` else "none"
	local lines = {
		`status="{self.status.Text}" note="{self.note.Text}" room={room} friendsButton={self.friendsButton.Visible} empty={self.empty.Visible}`,
	}
	for _, row in self.rows do
		if row.frame.Visible then
			table.insert(
				lines,
				`{row.name.Text} {row.level.Text} [{row.face.Text}{if row.action then "" else " (disabled)"}] id={row.userId}`
			)
		end
	end
	return table.concat(lines, "\n")
end

return CoopView
