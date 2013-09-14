--[[

	Event loop

--]]

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"

local EventLoop = EventEmitter:subclass("event.EventLoop")
EventLoop:has("running", {
	is = "rb"
})
function EventLoop:run()
	self.running = true
	while self:isRunning() do
		self:trigger(os.pullEvent())
	end
	self.running = false
end
function EventLoop:stop()
	self.running = false
end

-- Exports
return EventLoop:new()