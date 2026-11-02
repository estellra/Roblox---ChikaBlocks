--!strict
-- The mockups' "clay" look, built from plain UI objects so it needs no images:
--   button  a chunky outlined button with a colored lip under it that it sinks into when pressed
--   sky     the pastel sky gradient with soft clouds, behind every screen
-- Colors, radii and sizes all come from Theme.
local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local create = require("./Create")

export type ButtonStyle = "primary" | "secondary" | "reward"

type ButtonColors = { face: Color3, lip: Color3, text: Color3 }

local Clay = {}

local function colorsOf(style: ButtonStyle): ButtonColors
	local colors = Theme.Colors
	if style == "secondary" then
		return { face = colors.ButtonSecondary, lip = colors.ButtonSecondaryShadow, text = colors.ButtonSecondaryText }
	elseif style == "reward" then
		return { face = colors.Reward, lip = colors.RewardShadow, text = colors.RewardText }
	end
	return { face = colors.Button, lip = colors.ButtonShadow, text = colors.ButtonText }
end

local function rounded(radius: UDim): UICorner
	return create("UICorner", { CornerRadius = radius })
end

local function outline(thickness: number): UIStroke
	return create("UIStroke", {
		Color = Theme.Colors.Outline,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

export type ButtonProps = {
	name: string,
	text: string,
	style: ButtonStyle,
	order: number?,
	size: UDim2?, -- the whole button; its height includes the lip (default: full width, 56 + lip)
	textSize: number?,
}

-- A button made of a root Frame (what layouts see) holding the lip and the "Face" TextButton (what people
-- press: connect to Activated, set Text, select it for gamepads). Use Clay.face() to reach the face.
function Clay.button(props: ButtonProps): Frame
	local lip = Theme.Spacing.ButtonLip
	local style = colorsOf(props.style)
	local radius = Theme.Radius.Button
	local stroke = Theme.Stroke.Button

	local lipFrame = create("Frame", {
		Name = "Lip",
		Position = UDim2.fromOffset(0, lip),
		Size = UDim2.new(1, 0, 1, -lip),
		BackgroundColor3 = style.lip,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, { rounded(radius), outline(stroke) })
	local face = create("TextButton", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -lip),
		BackgroundColor3 = style.face,
		BorderSizePixel = 0,
		AutoButtonColor = false, -- the press animation below is the feedback
		FontFace = Theme.Fonts.Title,
		TextSize = props.textSize or Theme.TextSize.Button,
		TextColor3 = style.text,
		Text = props.text,
		ZIndex = 2,
	}, { rounded(radius), outline(stroke) })
	local root = create("Frame", {
		Name = props.name,
		LayoutOrder = props.order or 0,
		Size = props.size or UDim2.new(1, 0, 0, 56 + lip),
		BackgroundTransparency = 1,
	}, {
		lipFrame,
		face,
		create("UISizeConstraint", {
			MinSize = Vector2.new(Theme.MinTouchTarget.X, Theme.MinTouchTarget.Y + lip),
		}),
	})

	-- Pressing sinks the face onto its lip (all but two pixels of it).
	local info = TweenInfo.new(Theme.Motion.ButtonPress, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function sink(down: boolean)
		TweenService:Create(face, info, { Position = UDim2.fromOffset(0, if down then lip - 2 else 0) }):Play()
	end
	face.MouseButton1Down:Connect(function()
		sink(true)
	end)
	face.MouseButton1Up:Connect(function()
		sink(false)
	end)
	face.MouseLeave:Connect(function()
		sink(false)
	end)
	return root
end

function Clay.face(button: Frame): TextButton
	return button:FindFirstChild("Face") :: TextButton
end

-- Re-colors a button, e.g. a tab that is now selected.
function Clay.setStyle(button: Frame, style: ButtonStyle)
	local colors = colorsOf(style)
	local face = Clay.face(button)
	face.BackgroundColor3 = colors.face
	face.TextColor3 = colors.text
	local lip = button:FindFirstChild("Lip") :: Frame
	lip.BackgroundColor3 = colors.lip
end

export type PillProps = {
	name: string,
	text: string,
	icon: string?, -- image shown before the text
	style: ("panel" | "reward")?,
	order: number?,
}

-- A small rounded label with an outline (the Best and Combo pills): grows with its text.
function Clay.pill(props: PillProps): Frame
	local colors = Theme.Colors
	local children: { Instance } = {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		outline(Theme.Stroke.Pill),
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	}
	if props.icon then
		table.insert(
			children,
			create("ImageLabel", {
				Name = "Icon",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(18, 18),
				BackgroundTransparency = 1,
				Image = props.icon,
			})
		)
	end
	table.insert(
		children,
		create("TextLabel", {
			Name = "Text",
			LayoutOrder = 2,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Label,
			TextSize = 15,
			TextColor3 = colors.Text,
			Text = props.text,
		})
	)
	return create("Frame", {
		Name = props.name,
		LayoutOrder = props.order or 0,
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = if props.style == "reward" then colors.Reward else colors.Panel,
		BorderSizePixel = 0,
	}, children)
end

function Clay.pillLabel(pill: Frame): TextLabel
	return pill:FindFirstChild("Text") :: TextLabel
end

-- Resizes a pill (32 px high by default); its text and icon follow.
function Clay.setPillHeight(pill: Frame, height: number)
	pill.Size = UDim2.fromOffset(0, height)
	Clay.pillLabel(pill).TextSize = math.floor(height * 0.47)
	local icon = pill:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		icon.Size = UDim2.fromOffset(math.floor(height * 0.56), math.floor(height * 0.56))
	end
end

export type IconButtonProps = { name: string, image: string?, text: string?, order: number? }

-- The icon of an icon button: an image, or a short text such as "?".
local function iconOf(props: IconButtonProps): GuiObject
	if props.text then
		return create("TextLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Title,
			TextSize = 28,
			TextColor3 = Theme.Colors.Text,
			Text = props.text,
		})
	end
	return create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = props.image or "",
	})
end

-- A round button with an icon (pause, settings...): a cream disc with an outline that shrinks slightly when
-- pressed. Square, 52 px by default; size it from outside (the aspect ratio keeps it round).
function Clay.iconButton(props: IconButtonProps): TextButton
	local pressScale = create("UIScale", { Scale = 1 })
	local button = create("TextButton", {
		Name = props.name,
		LayoutOrder = props.order or 0,
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		outline(Theme.Stroke.Button),
		create("UIAspectRatioConstraint", { AspectRatio = 1 }),
		pressScale,
		iconOf(props),
	})
	local info = TweenInfo.new(Theme.Motion.ButtonPress, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function press(down: boolean)
		TweenService:Create(pressScale, info, { Scale = if down then 0.92 else 1 }):Play()
	end
	button.MouseButton1Down:Connect(function()
		press(true)
	end)
	button.MouseButton1Up:Connect(function()
		press(false)
	end)
	button.MouseLeave:Connect(function()
		press(false)
	end)
	return button
end

-- A cloud: a flat base with two bumps, all one solid color (a faded one would show where the bumps overlap).
local function cloud(width: number, x: number, y: number): Frame
	local function blob(position: UDim2, size: UDim2): Frame
		return create("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = Theme.Colors.Cloud,
			BorderSizePixel = 0,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	return create("Frame", {
		Name = "Cloud",
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(width, 1), -- the aspect ratio below fits it within this: width decides, height follows
		BackgroundTransparency = 1,
	}, {
		create("UIAspectRatioConstraint", { AspectRatio = 1 / 0.45, DominantAxis = Enum.DominantAxis.Width }),
		blob(UDim2.fromScale(0, 0.4), UDim2.fromScale(1, 0.6)),
		blob(UDim2.fromScale(0.17, 0.05), UDim2.fromScale(0.36, 0.8)),
		blob(UDim2.fromScale(0.42, 0), UDim2.fromScale(0.42, 0.95)),
	})
end

-- Full-screen sky: gradient from Background to SkyBottom with clouds in the corners. With `swallowClicks`
-- nothing underneath reacts to clicks on it.
function Clay.sky(name: string, swallowClicks: boolean?): Frame
	return create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), -- the gradient supplies the colors
		BorderSizePixel = 0,
		Active = swallowClicks == true,
	}, {
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Theme.Colors.Background, Theme.Colors.SkyBottom),
		}),
		cloud(0.18, 0.03, 0.1),
		cloud(0.13, 0.8, 0.08),
		cloud(0.16, 0.72, 0.8),
		cloud(0.12, 0.3, 0.84),
	})
end

return Clay
