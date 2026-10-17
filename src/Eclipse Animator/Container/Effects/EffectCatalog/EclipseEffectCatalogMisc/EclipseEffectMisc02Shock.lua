--!nocheck
--// cracked by numan

return {
	name = "Shock",
	id = "Misc/2",
	group = "Misc",
	index = 2,
	nodes = {
		{
			class = "Part",
			name = "Shock",
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
			name = "Attachment",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { 0, 0, 0, 1, 0, 0, 0, -4.371138828673793e-8, 1, 0, -1, -4.371138828673793e-8 },
				},
			},
		},
		{
			parent = 3,
			class = "ParticleEmitter",
			name = "Impact131",
			properties = {
				ShapeStyle = {
					e = "ParticleEmitterShapeStyle",
					t = "EnumItem",
					v = "Volume",
				},
				FlipbookFramerate = {
					t = "NumberRange",
					v = { 1, 1 },
				},
				LightInfluence = 0,
				Lifetime = {
					t = "NumberRange",
					v = { 0.10000000149011612, 0.10000000149011612 },
				},
				FlipbookLayout = {
					e = "ParticleFlipbookLayout",
					t = "EnumItem",
					v = "None",
				},
				SpreadAngle = {
					t = "Vector2",
					v = { 0, 0 },
				},
				LockedToPart = true,
				FlipbookBlendFrames = true,
				Transparency = {
					t = "NumberSequence",
					v = {
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Orientation = {
					e = "ParticleOrientation",
					t = "EnumItem",
					v = "VelocityPerpendicular",
				},
				WindAffectsDrag = false,
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
				Drag = 0,
				FlipbookStartRandom = false,
				TimeScale = 1,
				Squash = {
					t = "NumberSequence",
					v = {
						{ 0, 0, 0 },
						{ 1, 0, 0 },
					},
				},
				Speed = {
					t = "NumberRange",
					v = { 0.0010000000474974513, 0.0010000000474974513 },
				},
				Brightness = 1,
				Size = {
					t = "NumberSequence",
					v = {
						{ 0, 3.125, 0 },
						{ 1, 0.43749988079071045, 0 },
					},
				},
				Enabled = true,
				Acceleration = {
					t = "Vector3",
					v = { 0, 0, 0 },
				},
				RotSpeed = {
					t = "NumberRange",
					v = { 0, 0 },
				},
				EmissionDirection = {
					e = "NormalId",
					t = "EnumItem",
					v = "Top",
				},
				ShapeInOut = {
					e = "ParticleEmitterShapeInOut",
					t = "EnumItem",
					v = "Outward",
				},
				Rate = 10,
				ZOffset = 0,
				Rotation = {
					t = "NumberRange",
					v = { 0, 0 },
				},
				ShapePartial = 1,
				FlipbookMode = {
					e = "ParticleFlipbookMode",
					t = "EnumItem",
					v = "OneShot",
				},
				Texture = "rbxassetid://13877773941",
				VelocityInheritance = 0,
				LightEmission = 0,
				Shape = {
					e = "ParticleEmitterShape",
					t = "EnumItem",
					v = "Box",
				},
				LocalTransparencyModifier = 0,
			},
		},
	},
	label = "Shock pulse",
}
