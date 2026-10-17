--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Defaults = require("Config").Defaults
local WindowFX = require("WindowFX")

local Alert = {}
local alertFrame, animatorFrame, headerLabel, descriptionLabel
local closing = false

function Alert.setRefs(refs)
	alertFrame, animatorFrame = refs.alertFrame, refs.animatorFrame
	headerLabel, descriptionLabel = refs.headerLabel, refs.descriptionLabel
end

local function enableButtons(enabled)
	for _, button in alertFrame.Buttons:GetChildren() do
		if button:IsA("GuiButton") then
			button.Interactable = enabled
		end
	end
end

function Alert.showReturnWarning()
	if not alertFrame or not animatorFrame or not headerLabel or not descriptionLabel then
		return
	end

	closing = false
	enableButtons(true)
	headerLabel.Text = Defaults.AlertHeader
	descriptionLabel.Text = Defaults.AlertUnsavedMessage
	alertFrame.Visible = true
	animatorFrame.Visible = false
	WindowFX.pop(alertFrame)
end

function Alert.hideReturnWarning(done)
	if closing then
		return
	end

	if not alertFrame or not alertFrame.Visible then
		if done then
			done()
		end

		return
	end

	closing = true
	enableButtons(false)
	WindowFX.shrink(alertFrame, function()
		alertFrame.Visible = false
		closing = false
		enableButtons(true)
		if done then
			done()
		end
	end)
end

return Alert
