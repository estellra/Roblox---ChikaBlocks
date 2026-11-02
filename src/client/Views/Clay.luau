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
		TextSize = Theme.TextSize.Button,
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
