--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Visibility = {}

function Visibility.classify(data)
	local objects, groups, result = {}, {}, {}
	local editableCollections = {}
	for _, armature in data.armatures or {} do
		if type(armature.bone_collections) == "table" then
			editableCollections[armature.name] = true
		end
	end

	for _, object in data.objects or {} do
		objects[object.name] = object
	end

	for _, bone in data.bones do
		local group = groups[bone.armature]
		if not group then
			group = { hasShape = false, allConstrained = true }
			groups[bone.armature] = group
		end

		if bone.display and bone.display.vertices then
			group.hasShape = true
		end

		if #(bone.constraints or {}) == 0 then
			group.allConstrained = false
		end
	end

	for _, bone in data.bones do
		local object = objects[bone.armature] or {}
		local group = groups[bone.armature]
		local display = bone.display
		local empty = display
			and display.vertices
			and #(display.edges or {}) == 0
			and #(display.triangles or {}) == 0
		local scale = display and display.custom_shape_scale_xyz
		local zeroScale = scale and scale[1] == 0 and scale[2] == 0 and scale[3] == 0
		local objectHidden = object.view_layer_hidden == true or object.collection_hidden == true

		if
			object.viewport_visible == nil
			and data.primary_armature
			and bone.armature ~= data.primary_armature
			and not group.hasShape
			and group.allConstrained
		then
			objectHidden = true
		end

		local visibility = bone.visibility
		local boneHidden = bone.hidden == true
		if visibility then
			boneHidden = visibility.bone_hidden == true
		end

		local collectionHidden = not editableCollections[bone.armature]
				and visibility
				and visibility.collection_hidden == true
			or false
		local control = not empty and not objectHidden
		local unselectable = bone.hide_select == true or object.hide_select == true
		result[bone.id] = {
			control = control,
			boneHidden = boneHidden,
			collectionHidden = collectionHidden,
			objectHidden = objectHidden,
			unselectable = unselectable,
			hidden = not control
				or boneHidden
				or collectionHidden
				or object.hide_viewport == true
				or zeroScale == true,
		}
	end

	return result
end

return Visibility
