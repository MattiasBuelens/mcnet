--[[

	Event loop

--]]

local EventEmitter		= require "event.EventEmitter"

-- Base event loop
local BaseEventLoop = EventEmitter:subclass("event.BaseEventLoop")
BaseEventLoop:has("running", {
	is = "rb"
})
function BaseEventLoop:initialize()
	super.initialize(self)
	-- Clean up on terminate
	self:on("terminate", self.stop, self)
end
function BaseEventLoop:run()
	-- Start
	self:start()
	-- Run event loop, catch errors
	local ok, err = pcall(function()
		while self:isRunning() do
			self:process()
		end
	end)
	-- Clean stop
	self:stop()
	-- Re-throw error
	if not ok then
		printError(err)
	end
end
function BaseEventLoop:process()
	error("event loop must implement process")
end
function BaseEventLoop:start()
	if self:isRunning() then return false end
	self.running = true
	return true
end
function BaseEventLoop:stop()
	if not self:isRunning() then return false end
	self.running = false
	-- Unregister all event handlers
	-- Necessary since this instance may be reused later
	self:offAll()
	return true
end

-- Global event loop
local GlobalEventLoop = BaseEventLoop:subclass("event.GlobalEventLoop")
function GlobalEventLoop:initialize()
	super.initialize(self)
	self.forward = {}
end
function GlobalEventLoop:process()
	self:trigger(os.pullEventRaw())
end
function GlobalEventLoop:addForward(eventLoop)
	assert(eventLoop ~= self, "cannot forward to self")
	self.forward[eventLoop] = true
end
function GlobalEventLoop:removeForward(eventLoop)
	self.forward[eventLoop] = nil
end
function GlobalEventLoop:trigger(event, ...)
	local forward = {}
	for eventLoop,_ in pairs(self.forward) do
		forward[eventLoop] = true
	end
	for eventLoop,_ in pairs(forward) do
		eventLoop:trigger(event, ...)
	end
	return super.trigger(self, event, ...)
end
function GlobalEventLoop:stop()
	if super.stop(self) then
		self.forward = {}
	end
end

-- Local event loop
local LocalEventLoop = BaseEventLoop:subclass("event.EventLoop")
function LocalEventLoop:initialize(parentEventLoop)
	super.initialize(self)
	self.parent = parentEventLoop
end
function LocalEventLoop:start()
	if super.start(self) then
		-- Start forwarding to this loop
		self.parent:addForward(self)
		-- Start parent
		self.parent:start()
	end
end
function LocalEventLoop:stop()
	if super.stop(self) then
		-- Stop forwarding to this loop
		self.parent:removeForward(self)
	end
end
function LocalEventLoop:process()
	-- Delegate to parent
	self.parent:process()
end

-- Event loop
local EventLoop = {
	global	= nil
}
function EventLoop.new()
	local eventLoop
	if EventLoop.global == nil then
		-- Create global event loop
		eventLoop = GlobalEventLoop:new()
		EventLoop.global = eventLoop
	else
		-- Create local event loop
		eventLoop = LocalEventLoop:new(EventLoop.global)
	end
	return eventLoop
end

-- Exports
return EventLoop