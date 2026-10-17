--!nocheck
--// cracked by numan

return {
	name = "Suspense",
	id = "Misc/1",
	group = "Misc",
	index = 1,
	nodes = {
		{
			class = "Part",
			name = "Suspense",
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
					v = { 0.0000152587890625, -1.2499046325683594, -0.0005035400390625, 0, 1, 0, -1, 0, 0, 0, 0, 1 },
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
					v = { 0.0000152587890625, 1.2499101161956787, -0.0005035400390625, 0, 1, 0, -1, 0, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "BeamBeam399",
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
				TextureSpeed = 15,
				Texture = "rbxassetid://13712010201",
				CurveSize0 = 0,
				TextureLength = 15,
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
						{ 0, 0.5, 0 },
						{ 1, 0.5, 0 },
					},
				},
				Width0 = 4,
				Width1 = 4,
			},
		},
	},
	label = "Suspense",
}
