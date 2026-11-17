--!strict
-- Co-op screen over the menu, in the same style as the Support and leaderboard screens: a cream card on the sky
-- with the other players in the server, an Invite button each (and a Duel button beside it once PVP is playable, for
-- a friendly match), and the room the player is in. It only draws
-- what CoopController hands it (setState) and reports presses; the server decides everything. The card is as tall
-- as what it holds (up to the screen), like the mockups.
-- Closing works by the X button, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Clay = require("./Clay")
local Theme = require("./Theme")
local create = require("./Create")

local BUTTON_HEIGHT = 52 + Theme.Spacing.ButtonLip -- the face is above the minimum touch size; the lip comes on top
local ROW_HEIGHT = BUTTON_HEIGHT + 20
local BUTTON_WIDTH = 140
local PAIR_BUTTON_WIDTH = 100 -- each of Duel and Invite, side by side
local CLOSE_SIZE = 44
local HEADER_HEIGHT = 44
local BODY_PADDING = 12 -- above and below what the card holds
local BODY_GAP = 8 -- between the header and the list
local CARD_MARGIN = 16 -- left free above and below the card
local MASCOT_SIZE = 120
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
	canDuel: boolean, -- PVP is playable: free people get a Duel button too
}

type Callbacks = {
	onClose: () -> (),
	onInvite: (userId: number) -> (),
	onDuel: (userId: number) -> (),
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
	duelButton: Frame,
	duelFace: TextButton,
	userId: number,
	action: ("invite" | "cancel")?, -- what pressing the button does; nil when it is disabled
}

local CoopView = {}
CoopView.__index = CoopView

export type CoopView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		card: Frame,
		content: ScrollingFrame,
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
		order = 4,
		size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		textSize = Theme.TextSize.Label,
	})
	local duelButton = Clay.button({
		name = "Duel",
		text = "Duel",
		style = "secondary",
		order = 3,
		size = UDim2.fromOffset(PAIR_BUTTON_WIDTH, BUTTON_HEIGHT),
		textSize = Theme.TextSize.Label,
	})
	duelButton.Visible = false
	-- A white card with a thin edge, like the mockups' rows.
	local frame = create("Frame", {
		Name = `Person{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = colors.TraySlot,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIStroke", { Color = colors.RowBorder, Thickness = 2 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 10) }),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
		}),
		name,
		level,
		duelButton,
		button,
	})
	-- The name takes whatever width the level and button leave.
	create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = name })
	return {
		frame = frame,
		name = name,
		level = level,
		button = button,
		face = Clay.face(button),
		duelButton = duelButton,
		duelFace = Clay.face(duelButton),
		userId = 0,
	}
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
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
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
	local status = paragraph("Status", 3, fonts.Title, 18, colors.Title)

	-- The room the player is in: a soft purple card with who they are with and the way out.
	local roomText = paragraph("RoomText", 1, fonts.Title, 18, colors.Text)
	roomText.TextXAlignment = Enum.TextXAlignment.Center
	local leaveRoot = Clay.button({
		name = "Leave",
		text = "Leave room",
		style = "secondary",
		order = 2,
		size = UDim2.new(0.7, 0, 0, BUTTON_HEIGHT),
		textSize = Theme.TextSize.Label,
	})
	local roomCard = create("Frame", {
		Name = "Room",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Lavender,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIStroke", { Color = colors.Title, Thickness = 2 }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
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
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
	})

	-- Invite friends: under the list (blue) when there are people to invite, in the middle of the empty screen (pink)
	-- when there are none. render() moves it.
	local friendsRoot = Clay.button({
		name = "InviteFriends",
		text = "Invite friends",
		style = "secondary",
		order = 7,
		size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
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
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
		}),
		create("UIPadding", { PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 12) }),
		create("ImageLabel", {
			Name = "Mascot",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(MASCOT_SIZE, MASCOT_SIZE),
			BackgroundTransparency = 1,
			Image = Theme.Images.MascotHappy,
		}),
		text("Message", "No one else is here yet.", fonts.Title, 18, colors.Text, {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
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
		Size = UDim2.new(0.94, 0, 1, -CARD_MARGIN), -- fitCard() shrinks it to what it holds
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
				PaddingTop = UDim.new(0, BODY_PADDING),
				PaddingBottom = UDim.new(0, BODY_PADDING),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, BODY_GAP),
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
		card = card,
		content = content,
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
			canDuel = false,
		},
		callbacks = callbacks,
		keyConnection = nil,
		connections = {},
	}, CoopView)

	table.insert(self.connections, closeButton.Activated:Connect(callbacks.onClose))
	table.insert(self.connections, Clay.face(leaveRoot).Activated:Connect(callbacks.onLeave))
	table.insert(self.connections, Clay.face(friendsRoot).Activated:Connect(callbacks.onInviteFriends))
	-- The card follows what it holds, and the screen it has to fit on.
	table.insert(
		self.connections,
		(content:FindFirstChildOfClass("UIListLayout") :: UIListLayout)
			:GetPropertyChangedSignal("AbsoluteContentSize")
			:Connect(function()
				self:fitCard()
			end)
	)
	table.insert(
		self.connections,
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:fitCard()
		end)
	)
	-- The list's window is only known once the card is laid out; measuring it settles the card in one more step.
	table.insert(
		self.connections,
		content:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			self:fitCard()
		end)
	)

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	self:render()
	return self
end

-- Makes the card as tall as the header and what is under it, but never taller than the screen. Once the card is laid
-- out, the part of it that isn't the list is measured rather than added up, so the list gets exactly the room its
-- content needs: a few pixels short would clip the last button's lip and show a scroll bar for nothing.
function CoopView.fitCard(self: CoopView)
	local layout = self.content:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local scale = self.pop.Scale -- the opening pop scales every absolute size alike
	local window = self.content.AbsoluteWindowSize.Y
	local chrome = HEADER_HEIGHT + BODY_GAP + 2 * BODY_PADDING
	if window > 0 and scale > 0 then
		chrome = (self.card.AbsoluteSize.Y - window) / scale
	end
	local wanted = chrome + layout.AbsoluteContentSize.Y / math.max(scale, 0.01)
	local room = self.gui.AbsoluteSize.Y - CARD_MARGIN
	if room <= 0 then
		return -- not laid out yet
	end
	local height = math.ceil(math.min(wanted, room))
	if math.abs(self.card.AbsoluteSize.Y / math.max(scale, 0.01) - height) >= 1 then
		self.card.Size = UDim2.new(0.94, 0, 0, height)
	end
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
		table.insert(
			self.connections,
			row.duelFace.Activated:Connect(function()
				if row.action == "invite" then
					self.callbacks.onDuel(row.userId)
				end
			end)
		)
		self.rows[index] = row
	end
	return row
end

-- What a person's button says and whether it can be pressed, given who the player is already inviting. A button
-- that can't be pressed is pale, whatever the reason.
local function setAction(row: Row, person: Person, state: State)
	-- Duel shows beside Invite only while the person can be invited; any other state is one button.
	local free = person.busy == nil and state.invitingUserId ~= person.userId
	local pair = state.canDuel and free
	row.duelButton.Visible = pair
	row.button.Size = UDim2.fromOffset(if pair then PAIR_BUTTON_WIDTH else BUTTON_WIDTH, BUTTON_HEIGHT)
	if pair then
		Clay.setEnabled(row.duelButton, not (state.inRoom or state.myBusy ~= nil or state.invitingUserId ~= nil))
	end
	if state.invitingUserId == person.userId then
		row.action = "cancel"
		row.face.Text = "Cancel"
		Clay.setStyle(row.button, "secondary")
		Clay.setEnabled(row.button, true)
		return
	end
	Clay.setStyle(row.button, "primary")
	if person.busy ~= nil then
		row.action = nil
		row.face.Text = BUSY_TEXT[person.busy] or "Busy"
		Clay.setEnabled(row.button, false)
	elseif state.inRoom or state.myBusy ~= nil or state.invitingUserId ~= nil then
		row.action = nil -- the player can't invite anyone right now
		row.face.Text = "Invite"
		Clay.setEnabled(row.button, false)
	else
		row.action = "invite"
		row.face.Text = "Invite"
		Clay.setEnabled(row.button, true)
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

	-- While an invitation is out, the line says who it waits for; afterwards, how the last one ended.
	local waitingFor: string? = nil
	for _, person in state.people do
		if person.userId == state.invitingUserId then
			waitingFor = person.name
		end
	end
	self.status.Text = if waitingFor then `Waiting for {waitingFor} to answer…` else state.status or ""
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
	local friends = self.friendsButton
	if #state.people == 0 then
		Clay.setStyle(friends, "primary")
		friends.Size = UDim2.new(0.64, 0, 0, BUTTON_HEIGHT)
		friends.LayoutOrder = 3
		friends.Parent = self.empty
	else
		Clay.setStyle(friends, "secondary")
		friends.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
		friends.LayoutOrder = 7
		friends.Parent = self.content
	end
	friends.Visible = state.canInviteFriends
	self:fitCard()
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
		`status="{self.status.Text}" note="{self.note.Text}" room={room} friendsButton={self.friendsButton.Visible} empty={self.empty.Visible} card={self.card.AbsoluteSize.X // 1}x{self.card.AbsoluteSize.Y // 1}`,
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
