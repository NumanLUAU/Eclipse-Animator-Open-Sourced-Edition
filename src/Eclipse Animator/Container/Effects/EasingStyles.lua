--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local EasingStyles = {
	linear = {
		Name = "Linear",
		Enum = Enum.EasingStyle.Linear,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(132, 96, 255),
			UnselectedColor = Color3.fromRGB(210, 204, 255),
			HoverColor = Color3.fromRGB(165, 138, 255),
		},
	},

	sine = {
		Name = "Sine",
		Enum = Enum.EasingStyle.Sine,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(72, 190, 255),
			UnselectedColor = Color3.fromRGB(198, 235, 255),
			HoverColor = Color3.fromRGB(120, 210, 255),
		},
	},

	quad = {
		Name = "Quad",
		Enum = Enum.EasingStyle.Quad,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(255, 176, 72),
			UnselectedColor = Color3.fromRGB(255, 225, 185),
			HoverColor = Color3.fromRGB(255, 198, 112),
		},
	},

	cubic = {
		Name = "Cubic",
		Enum = Enum.EasingStyle.Cubic,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(255, 86, 112),
			UnselectedColor = Color3.fromRGB(255, 200, 210),
			HoverColor = Color3.fromRGB(255, 124, 145),
		},
	},

	quart = {
		Name = "Quart",
		Enum = Enum.EasingStyle.Quart,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(178, 104, 255),
			UnselectedColor = Color3.fromRGB(225, 205, 255),
			HoverColor = Color3.fromRGB(202, 146, 255),
		},
	},

	quint = {
		Name = "Quint",
		Enum = Enum.EasingStyle.Quint,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(255, 76, 194),
			UnselectedColor = Color3.fromRGB(255, 197, 234),
			HoverColor = Color3.fromRGB(255, 118, 211),
		},
	},

	exponential = {
		Name = "Exponential",
		Enum = Enum.EasingStyle.Exponential,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(64, 230, 150),
			UnselectedColor = Color3.fromRGB(190, 255, 220),
			HoverColor = Color3.fromRGB(105, 245, 178),
		},
	},

	circular = {
		Name = "Circular",
		Enum = Enum.EasingStyle.Circular,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(70, 150, 255),
			UnselectedColor = Color3.fromRGB(195, 220, 255),
			HoverColor = Color3.fromRGB(112, 178, 255),
		},
	},

	back = {
		Name = "Back",
		Enum = Enum.EasingStyle.Back,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(255, 112, 76),
			UnselectedColor = Color3.fromRGB(255, 205, 190),
			HoverColor = Color3.fromRGB(255, 148, 112),
		},
	},

	bounce = {
		Name = "Bounce",
		Enum = Enum.EasingStyle.Bounce,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(255, 214, 64),
			UnselectedColor = Color3.fromRGB(255, 238, 180),
			HoverColor = Color3.fromRGB(255, 226, 105),
		},
	},

	constant = {
		Name = "Constant",
		Enum = Enum.EasingStyle.Linear,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(160, 160, 160),
			UnselectedColor = Color3.fromRGB(220, 220, 220),
			HoverColor = Color3.fromRGB(190, 190, 190),
		},
	},

	elastic = {
		Name = "Elastic",
		Enum = Enum.EasingStyle.Elastic,
		Custom = false,

		Settings = {
			SelectedColor = Color3.fromRGB(64, 238, 238),
			UnselectedColor = Color3.fromRGB(185, 255, 255),
			HoverColor = Color3.fromRGB(112, 250, 250),
		},
	},
}

return EasingStyles
