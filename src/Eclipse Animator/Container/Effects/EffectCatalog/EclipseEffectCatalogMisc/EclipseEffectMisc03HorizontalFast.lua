--!nocheck
--// cracked by numan

return {
	name = "HorizontalFast",
	id = "Misc/3",
	group = "Misc",
	index = 3,
	nodes = {
		{
			class = "Part",
			name = "HorizontalFast",
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
					v = { 1.9999847412109375, 0.0000019073486328125, -0.0005035400390625, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
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
					v = { -2, 0.0000019073486328125, -0.0005035400390625, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
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
				Width0 = 2,
				Width1 = 2,
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
				Width0 = 2,
				Width1 = 2,
			},
		},
	},
	label = "Horizontal rush",
}
