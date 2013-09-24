--[[

	MCNet
	Base transport protocol

]]--

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
	self.open = false
end
function Protocol:isOpen()
	return self.open
end
function Protocol:open()
	assert(not self:isOpen(), "attempted to open already opened protocol")
	self:trigger("open")
end
function Protocol:close()
	assert(self:isOpen(), "attempted to close already close protocol")
	self:trigger("close")
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
	assert(self:isOpen(), "attempted to send packet over closed protocol")
	-- Send packet
	self:trigger("send", destAddress, data)
end
function Protocol:onReceive(sourceAddress, data)
	-- Handle received packet
	error("protocol must implement onReceive")
end

-- Exports
return Protocol