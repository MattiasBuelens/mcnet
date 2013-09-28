--[[

	MCNet
	Base transport protocol

]]--

local EventEmitter	= require "event.EventEmitter"

local Protocol = EventEmitter:subclass("mcnet.transport.Protocol")

-- Constants
Protocol.class.PORT = {
	-- Reserved ports
	MIN_RESERVED	= 1,
	MAX_RESERVED	= 255,
	-- Client ports
	MIN_CLIENT		= 256,
	MAX_CLIENT		= 65535
}

function Protocol:initialize()
	super.initialize(self)
	self.bOpen = false
end
function Protocol:isOpen()
	return self.bOpen
end
function Protocol:open()
	if self:isOpen() then return false end
	self.bOpen = true
	self:trigger("open")
	return true
end
function Protocol:close()
	if not self:isOpen() then return false end
	self.bOpen = false
	self:trigger("close")
	return true
end
function Protocol:getRandomClientPort()
	return math.random(Protocol.PORT.MIN_CLIENT, Protocol.PORT.MAX_CLIENT)
end
function Protocol:getIdentifier()
	-- Protocol identifier
	error("protocol must implement getIdentifier")
end
function Protocol:connect(...)
	-- Active connect
	error("protocol does not support active connections")
end
function Protocol:listen(...)
	-- Listen for connection
	error("protocol does not support listening for connections")
end
function Protocol:rawSend(destAddress, data)
	-- Send packet
	if not self:isOpen() then return false end
	self:trigger("send", destAddress, data)
	return true
end
function Protocol:onReceive(sourceAddress, data)
	-- Handle received packet
	error("protocol must implement onReceive")
end

-- Exports
return Protocol