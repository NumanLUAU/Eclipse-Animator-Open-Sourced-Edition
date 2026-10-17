--!nocheck
--// cracked by numan

return {
	name = "Wind",
	id = "Lighting/1",
	group = "Lighting",
	index = 1,
	nodes = {
		{
			class = "Part",
			name = "Wind",
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
			name = "Bottom",
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
					v = { 2.000030517578125, -0.9387065768241882, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
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
					v = { -2, -0.9387065768241882, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "BeamCurved smoke beam 2",
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
				Brightness = 15,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Stretch",
				},
				Attachment1 = {
					t = "Ref",
					v = 4,
				},
				Enabled = true,
				TextureSpeed = 1,
				Texture = "rbxassetid://13315699616",
				CurveSize0 = 0,
				TextureLength = 1,
				Color = {
					t = "ColorSequence",
					v = {
						{
							0,
							{
								t = "Color3",
								v = { 1, 1, 1 },
							},
						},
						{
							1,
							{
								t = "Color3",
								v = { 1, 1, 1 },
							},
						},
					},
				},
				LightEmission = 0,
				Transparency = {
					t = "NumberSequence",
					v = {
						{ 0, 0.949999988079071, 0 },
						{ 1, 0.949999988079071, 0 },
					},
				},
				Width0 = 0,
				Width1 = 4,
			},
		},
		{
			parent = 1,
			class = "Folder",
			name = "Top",
			properties = {  },
		},
		{
			parent = 6,
			class = "Attachment",
			name = "1",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { 2.000030517578125, 0.6581242084503174, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 6,
			class = "Attachment",
			name = "2",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { -2, 0.6581242084503174, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 6,
			class = "Beam",
			name = "BeamCurved smoke beam 2",
			properties = {
				FaceCamera = false,
				CurveSize1 = 0,
				ZOffset = 0,
				LightInfluence = 0,
				Segments = 10,
				Attachment0 = {
					t = "Ref",
					v = 7,
				},
				Brightness = 15,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Stretch",
				},
				Attachment1 = {
					t = "Ref",
					v = 8,
				},
				Enabled = true,
				TextureSpeed = 1,
				Texture = "rbxassetid://13315699616",
				CurveSize0 = 0,
				TextureLength = 1,
				Color = {
					t = "ColorSequence",
					v = {
						{
							0,
							{
								t = "Color3",
								v = { 1, 1, 1 },
							},
						},
						{
							1,
							{
								t = "Color3",
								v = { 1, 1, 1 },
							},
						},
					},
				},
				LightEmission = 0,
				Transparency = {
					t = "NumberSequence",
					v = {
						{ 0, 0.949999988079071, 0 },
						{ 1, 0.949999988079071, 0 },
					},
				},
				Width0 = 4,
				Width1 = 0,
			},
		},
	},
	label = "Wind trails",
}
