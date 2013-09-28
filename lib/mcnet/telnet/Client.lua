--[[

	MCNet
	Telnet client

]]--

local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"

-- Constants
local TELNET_PORT	= 23

local Client = EventEmitter:subclass("mcnet.telnet.Client")
function Client:initialize(transport, serverAddress, serverPort)
	super.initialize(self)
	self.bOpen = false
	self.transport = transport
	self.serverAddress = tonumber(serverAddress)
	self.serverPort = tonumber(serverPort) or TELNET_PORT
end
function Client:isOpen()
	return self.bOpen
end
function Client:isConnected()
	return self.conn ~= nil and self.conn:isOpen()
end
function Client:open()
	if self:isOpen() then return false end
	self.bOpen = true
	if self.conn == nil then
		-- Connect to server
		self.conn = self.transport:connect("tcp", self.serverAddress, self.serverPort)
		self.conn:on("open", self.onOpen, self)
		self.conn:on("receive", self.onReceive, self)
		self.conn:on("closing", self.onClose, self)
		self.conn:on("close", self.onClose, self)
	end
	-- Register event handlers
	EventLoop:on("key", self.onKey, self)
	EventLoop:on("char", self.onChar, self)
	EventLoop:on("mouse_click", self.onMouseClick, self)
	EventLoop:on("mouse_scroll", self.onMouseClick, self)
	EventLoop:on("mouse_drag", self.onMouseDrag, self)
	return true
end
function Client:close()
	if not self:isOpen() then return false end
	self.bOpen = false
	-- Close connection
	if self.conn ~= nil then
		self.conn:off("open", self.onOpen, self)
		self.conn:off("receive", self.onReceive, self)
		self.conn:off("closing", self.onClose, self)
		self.conn:off("close", self.onClose, self)
		self.conn:close()
		self.conn = nil
	end
	-- Unregister event handlers
	EventLoop:off("key", self.onKey, self)
	EventLoop:off("char", self.onChar, self)
	EventLoop:off("mouse_click", self.onMouseClick, self)
	EventLoop:off("mouse_scroll", self.onMouseScroll, self)
	EventLoop:off("mouse_drag", self.onMouseDrag, self)
	self:trigger("close")
	return true
end
function Client:setup()
	local width, height = term.getSize()
	local isColor = term.isColor()
	-- Send setup data
	self:send({
		command = "setup",
		data	= {
			width	= width,
			height	= height,
			isColor	= isColor
		}
	})
	self:trigger("open")
end
function Client:send(message)
	if self.conn ~= nil and self.conn:isOpen() then
		self.conn:send(textutils.serialize(message))
	end
end
function Client:onOpen()
	self:setup()
end
function Client:onClose()
	self:close()
end
function Client:sendEvent(...)
	-- Send event message
	self:send({
		command	= "event",
		data	= { ... }
	})
end
function Client:onKey(...)
	self:sendEvent("key", ...)
end
function Client:onChar(...)
	self:sendEvent("char", ...)
end
function Client:onMouseClick(...)
	self:sendEvent("mouse_click", ...)
end
function Client:onMouseScroll(...)
	self:sendEvent("mouse_scroll", ...)
end
function Client:onMouseDrag(...)
	self:sendEvent("mouse_drag", ...)
end
function Client:onReceive(data)
	-- Unpack message
	local message = textutils.unserialize(data)
	if message.command == "terminal" then
		-- Remote terminal call
		term[message.fn](unpack(message.params))
	end
end

return Client