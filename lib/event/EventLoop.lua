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
	-- Run event loop
	self:start()
	while self:isRunning() do
		self:trigger(os.pullEvent())
	end
	self:stop()
end
function EventLoop:start()
	if self:isRunning() then return false end
	self.running = true
	return true
end
function EventLoop:stop()
	if not self:isRunning() then return false end
	self.running = false
	-- Unregister all event handlers
	-- Necessary since this instance may be reused later
	self:offAll()
	return true
end

-- Exports
return EventLoop:new()