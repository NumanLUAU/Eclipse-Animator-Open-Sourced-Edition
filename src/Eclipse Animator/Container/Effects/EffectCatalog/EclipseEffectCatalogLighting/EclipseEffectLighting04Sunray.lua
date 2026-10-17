--!nocheck
--// cracked by numan

return {
	name = "Sunray",
	id = "Lighting/4",
	group = "Lighting",
	index = 4,
	nodes = {
		{
			class = "Part",
			name = "Sunray",
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
			name = "Flare170New",
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
					v = { 1, 1 },
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
						{ 0, 0.5, 0 },
						{ 1, 0.5, 0 },
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
						{ 0, 1, 0 },
						{ 1, 1, 0 },
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
				Rate = 1,
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
				Texture = "rbxassetid://12105193694",
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
		{
			parent = 3,
			class = "ParticleEmitter",
			name = "Flare195New",
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
					v = { 1, 1 },
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
						{ 0, 0.800000011920929, 0 },
						{ 1, 0.800000011920929, 0 },
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
						{ 0, 2, 0 },
						{ 1, 2, 0 },
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
				Rate = 1,
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
				Texture = "rbxassetid://75202463",
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
		{
			parent = 2,
			class = "Attachment",
			name = "Attachment",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { -0.715087890625, -0.7370381355285645, 0, 0.9396926164627075, -1.6692294061874469e-15, -0.3420201539993286, 0.3420201539993286, -4.371138828673793e-8, 0.9396926164627075, -1.4950177984474067e-8, -1, -4.10752676316406e-8 },
				},
			},
		},
		{
			parent = 6,
			class = "ParticleEmitter",
			name = "Flare210New",
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
					v = { 1, 1 },
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
						{ 0, 0.800000011920929, 0 },
						{ 1, 0.800000011920929, 0 },
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
						{ 0, 2, 0 },
						{ 1, 2, 0 },
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
				Rate = 1,
				ZOffset = 0,
				Rotation = {
					t = "NumberRange",
					v = { 15, 15 },
				},
				ShapePartial = 1,
				FlipbookMode = {
					e = "ParticleFlipbookMode",
					t = "EnumItem",
					v = "OneShot",
				},
				Texture = "rbxassetid://14684195806",
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
		{
			parent = 2,
			class = "Attachment",
			name = "Attachment",
			properties = {
				Visible = false,
				CFrame = {
					t = "CFrame",
					v = { 0.7119407653808594, 0.3706415891647339, 0, 0.9396926164627075, -1.6692294061874469e-15, -0.3420201539993286, 0.3420201539993286, -4.371138828673793e-8, 0.9396926164627075, -1.4950177984474067e-8, -1, -4.10752676316406e-8 },
				},
			},
		},
		{
			parent = 8,
			class = "ParticleEmitter",
			name = "Flare234New",
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
					v = { 1, 1 },
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
						{ 0, 0.800000011920929, 0 },
						{ 1, 0.800000011920929, 0 },
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
						{ 0, 2, 0 },
						{ 1, 2, 0 },
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
				Rate = 1,
				ZOffset = 0,
				Rotation = {
					t = "NumberRange",
					v = { 15, 15 },
				},
				ShapePartial = 1,
				FlipbookMode = {
					e = "ParticleFlipbookMode",
					t = "EnumItem",
					v = "OneShot",
				},
				Texture = "rbxassetid://17268259842",
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
	label = "Sun rays",
}
