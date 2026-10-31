--!strict
-- Main menu: title, saved best, Play and How to play. A gray-box placeholder until the mockups arrive.
-- Play works by click/tap, Enter or Space, and the gamepad A button (Play is selected for gamepads).
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require("./Theme")
local create = require("./Create")

local PLAY_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.Space] = true,
}

local MenuView = {}
MenuView.__index = MenuView

export type MenuView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		bestLabel: TextLabel,
		playButton: TextButton,
		howToButton: TextButton,
		ready: boolean, -- false until the saved profile has arrived
		onPlay: () -> (),
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	MenuView
))

local function button(name: string, text: string, order: number, primary: boolean): TextButton
	local colors = Theme.Colors
	return create("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = if primary then colors.Button else colors.ButtonSecondary,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Button,
		TextColor3 = if primary then colors.ButtonText else colors.ButtonSecondaryText,
		Text = text,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
	})
end

function MenuView.new(playerGui: PlayerGui, onPlay: () -> (), onHowToPlay: () -> ()): MenuView
	local colors, fonts, sizes = Theme.Colors, Theme.Fonts, Theme.TextSize

	-- Opaque full-screen background under the notch and top bar; the content sits in the safe area above it.
	local backdrop = create("ScreenGui", {
		Name = "MenuBackdrop",
		DisplayOrder = 10,
		ResetOnSpawn = false,
		Enabled = false,
	}, {
		create("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.Background,
			BorderSizePixel = 0,
			Active = true, -- swallow clicks meant for the game underneath
		}),
	})
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local bestLabel = create("TextLabel", {
		Name = "Best",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = fonts.Body,
		TextSize = sizes.Label + 2,
		TextColor3 = colors.TextMuted,
		Text = "Best —",
	})
	local playButton = button("Play", "Loading…", 3, true)
	local howToButton = button("HowToPlay", "How to play", 4, false)
	local gui = create("ScreenGui", {
		Name = "Menu",
		DisplayOrder = 11,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, {
		create("Frame", {
			Name = "Column",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			create("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 16),
			}),
			create("TextLabel", {
				Name = "Title",
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				FontFace = fonts.Title,
				TextSize = sizes.MenuTitle,
				TextWrapped = true,
				TextColor3 = colors.Text,
				Text = Theme.Text.GameTitle,
			}),
			bestLabel,
			playButton,
			howToButton,
		}),
	})

	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		bestLabel = bestLabel,
		playButton = playButton,
		howToButton = howToButton,
		ready = false,
		onPlay = onPlay,
		keyConnection = nil,
		connections = {},
	}, MenuView)
	table.insert(
		self.connections,
		playButton.Activated:Connect(function()
			if self.ready then
				onPlay()
			end
		end)
	)
	table.insert(
		self.connections,
		howToButton.Activated:Connect(function()
			if self.ready then
				onHowToPlay()
			end
		end)
	)

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	return self
end

-- Called once the saved profile is known; until then Play shows "Loading…" and does nothing.
function MenuView.setReady(self: MenuView, best: number)
	self.ready = true
	self.playButton.Text = "Play"
	self.bestLabel.Text = `Best {best}`
end

function MenuView.show(self: MenuView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.playButton
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and PLAY_KEYS[input.KeyCode] and self.ready then
				self.onPlay()
			end
		end)
	end
end

function MenuView.hide(self: MenuView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected == self.playButton or selected == self.howToButton then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function MenuView.isOpen(self: MenuView): boolean
	return self.gui.Enabled
end

function MenuView.destroy(self: MenuView)
	self:hide()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.backdrop:Destroy()
	self.gui:Destroy()
end

return MenuView
