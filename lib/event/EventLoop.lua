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
	-- Start event loop
	self.running = true
	while self:isRunning() do
		self:trigger(os.pullEvent())
	end
	self:stop()
end
function EventLoop:stop()
	-- Break event loop
	self.running = false
	-- Unregister all event handlers
	-- Necessary since this instance may be reused later
	self:offAll()
end

-- Exports
return EventLoop:new()