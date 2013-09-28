--[[

	MCNet Telnet
	Command

]]--

local Object	= require "objectlua.Object"

local Command = Object:subclass("telnet.Command")
function Command:initialize(command, data)
	self.command = command
	self.data = data or nil
end
function Command.class:parse(message)
	local command, data = string.match(message, "^([^#]*)#(.*)$")
	return self:new(command, textutils.unserialize(data))
end
function Command.class:parseData(data)
	if type(data) == "string" then
		return (data)
	end
	return data
end
function Command:serialize()
	return tostring(self.command)
		.. "#" .. textutils.serialize(self.data)
end
function Command.class:serialize(command)
	if type(command) == "table" then
		return command:serialize()
	end
	return tostring(command)
end

return Command