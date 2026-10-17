--!nocheck
--// cracked by numan

return {
	name = "VerticalFast",
	id = "Misc/4",
	group = "Misc",
	index = 4,
	nodes = {
		{
			class = "Part",
			name = "VerticalFast",
			properties = {
				Size = {
					t = "Vector3",
					v = { 4, 2.4998202323913574, 0.001000046730041504 },
				},
			},
		},
		{
			parent = 1,
			class = "Folder",
			name = "Top",
			properties = {  },
		},
		{
			parent = 2,
			class = "Attachment",
			name = "1",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { -0.00000762939453125, 1.2498948574066162, -0.0005035400390625, 0, -1, 0, 1, 0, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 2,
			class = "Attachment",
			name = "2",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { -0.00000762939453125, -1.2499141693115234, -0.0005035400390625, 0, -1, 0, 1, 0, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "BeamStars",
			properties = {
				FaceCamera = false,
				CurveSize1 = 0,
				ZOffset = 0,
				LightInfluence = 0,
				Segments = 10,
				Attachment0 = {
					t = "Ref",
					v = 3,
				},
				Brightness = 3000,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Static",
				},
				Attachment1 = {
					t = "Ref",
					v = 4,
				},
				Enabled = true,
				TextureSpeed = 1,
				Texture = "rbxassetid://17636295291",
				CurveSize0 = 0,
				TextureLength = 200,
				Color = {
					t = "ColorSequence",
					v = {
						{
							0,
							{
								t = "Color3",
								v = { 0, 0, 0 },
							},
						},
						{
							1,
							{
								t = "Color3",
								v = { 0, 0, 0 },
							},
						},
					},
				},
				LightEmission = 0,
				Transparency = {
					t = "NumberSequence",
					v = {
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Width0 = 7,
				Width1 = 7,
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "BeamStars",
			properties = {
				FaceCamera = false,
				CurveSize1 = 0,
				ZOffset = 0,
				LightInfluence = 0,
				Segments = 10,
				Attachment0 = {
					t = "Ref",
					v = 3,
				},
				Brightness = 3000,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Static",
				},
				Attachment1 = {
					t = "Ref",
					v = 4,
				},
				Enabled = true,
				TextureSpeed = 1,
				Texture = "rbxassetid://17636295291",
				CurveSize0 = 0,
				TextureLength = 200,
				Color = {
					t = "ColorSequence",
					v = {
						{
							0,
							{
								t = "Color3",
								v = { 0, 0, 0 },
							},
						},
						{
							1,
							{
								t = "Color3",
								v = { 0, 0, 0 },
							},
						},
					},
				},
				LightEmission = 0,
				Transparency = {
					t = "NumberSequence",
					v = {
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Width0 = 7,
				Width1 = 7,
			},
		},
	},
	label = "Vertical rush",
}
