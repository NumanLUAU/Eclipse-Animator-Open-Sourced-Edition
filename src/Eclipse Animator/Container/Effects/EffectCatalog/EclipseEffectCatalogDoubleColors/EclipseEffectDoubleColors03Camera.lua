--!nocheck
--// cracked by numan

return {
	name = "Camera",
	id = "DoubleColors/3",
	group = "DoubleColors",
	index = 3,
	nodes = {
		{
			class = "Part",
			name = "Camera",
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
					v = { 2.000030517578125, 0.7389072179794312, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
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
					v = { -2, 0.7389072179794312, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "Beam83",
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
				TextureSpeed = 5,
				Texture = "rbxassetid://86583175913235",
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
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Width0 = 1,
				Width1 = 1,
			},
		},
		{
			parent = 2,
			class = "Beam",
			name = "Beam74",
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
				TextureSpeed = 5,
				Texture = "rbxassetid://89444331714664",
				CurveSize0 = 0,
				TextureLength = 1,
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
				Width0 = 0.5,
				Width1 = 0.5,
			},
		},
		{
			parent = 1,
			class = "Folder",
			name = "Bottom",
			properties = {  },
		},
		{
			parent = 7,
			class = "Beam",
			name = "Beam83",
			properties = {
				FaceCamera = false,
				CurveSize1 = 0,
				ZOffset = 0,
				LightInfluence = 0,
				Segments = 10,
				Attachment0 = {
					t = "Ref",
					v = 10,
				},
				Brightness = 15,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Stretch",
				},
				Attachment1 = {
					t = "Ref",
					v = 9,
				},
				Enabled = true,
				TextureSpeed = 5,
				Texture = "rbxassetid://86583175913235",
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
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Width0 = 1,
				Width1 = 1,
			},
		},
		{
			parent = 7,
			class = "Attachment",
			name = "2",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { -2, -0.9494045972824097, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 7,
			class = "Attachment",
			name = "1",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { 2.000030517578125, -0.9494045972824097, -0.024974822998046875, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				},
			},
		},
		{
			parent = 7,
			class = "Beam",
			name = "Beam74",
			properties = {
				FaceCamera = false,
				CurveSize1 = 0,
				ZOffset = 0,
				LightInfluence = 0,
				Segments = 10,
				Attachment0 = {
					t = "Ref",
					v = 10,
				},
				Brightness = 15,
				TextureMode = {
					e = "TextureMode",
					t = "EnumItem",
					v = "Stretch",
				},
				Attachment1 = {
					t = "Ref",
					v = 9,
				},
				Enabled = true,
				TextureSpeed = 5,
				Texture = "rbxassetid://89444331714664",
				CurveSize0 = 0,
				TextureLength = 1,
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
				Width0 = 0.5,
				Width1 = 0.5,
			},
		},
	},
	label = "Cross currents",
}
