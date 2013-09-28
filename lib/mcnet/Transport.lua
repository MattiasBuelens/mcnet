--[[

	MCNet
	Transport layer

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"
local Network		= require "mcnet.Network"

-- Transport
local Transport = EventEmitter:subclass("mcnet.transport.Transport")
function Transport:initialize(address)
	super.initialize(self)
	self.bOpen = false
	self.protocols = {}
	self.network = Network:new(address)
	self:createProtocols()
end
function Transport:getProtocol(protocolId)
	return self.protocols[string.lower(protocolId)]
end
function Transport:addProtocol(protocol)
	self.protocols[string.lower(protocol:getIdentifier())] = protocol
end
function Transport:createProtocols()
	-- Instantiate protocols
	for _,protocolClass in pairs(Transport.protocolClasses) do
		local protocol = protocolClass:new()
		-- Register send event handler
		protocol:on("send", function(...)
			self:rawSend(protocol, ...)
		end)
		self:addProtocol(protocol)
	end
end
function Transport:isOpen()
	return self.bOpen
end
function Transport:open()
	if self:isOpen() then return false end
	self.bOpen = true
	-- Open network
	self.network:open()
	-- Open protocols
	for _,protocol in pairs(self.protocols) do
		protocol:open()
	end
	-- Register event handlers
	self.network:on("receive", self.onReceive, self)
	self:trigger("open")
	return true
end
function Transport:close()
	if not self:isOpen() then return false end
	self.bOpen = false
	-- Unregister event handlers
	self.network:off("receive", self.onReceive, self)
	-- Close protocols
	for _,protocol in pairs(self.protocols) do
		protocol:close()
	end
	-- Close network
	self.network:close()
	self:trigger("close")
	return true
end
function Transport:connect(protocolId, ...)
	assert(self:isOpen(), "attempted to connect using closed transport entity")
	local protocol = self:getProtocol(protocolId)
	assert(protocol ~= nil, "unknown protocol: "..protocolId)
	return protocol:connect(...)
end
function Transport:listen(protocolId, ...)
	assert(self:isOpen(), "attempted to listen using closed transport entity")
	local protocol = self:getProtocol(protocolId)
	assert(protocol ~= nil, "unknown protocol: "..protocolId)
	return protocol:listen(...)
end
function Transport:stopListening(protocolId, ...)
	assert(self:isOpen(), "attempted to stop listening using closed transport entity")
	local protocol = self:getProtocol(protocolId)
	assert(protocol ~= nil, "unknown protocol: "..protocolId)
	return protocol:stopListening(...)
end
function Transport:parsePacket(packet)
	-- Parse protocol identifier and data
	local protocolId, data = string.match(packet, "^([^#]+)#(.*)$")
	local protocol = self:getProtocol(protocolId)
	-- Check for protocol
	if protocol ~= nil then
		return protocol, data
	else
		return nil, nil
	end
end
function Transport:serializePacket(protocol, data)
	-- Add protocol identifier in front
	return protocol:getIdentifier().."#"..tostring(data)
end
function Transport:rawSend(protocol, destAddress, data)
	-- Send using protocol
	self.network:send(destAddress, self:serializePacket(protocol, data))
end
function Transport:onReceive(sourceAddress, data)
	-- Pass on to protocol
	local protocol, data = self:parsePacket(data)
	if protocol ~= nil and protocol:isOpen() then
		protocol:onReceive(sourceAddress, data)
	end
end

-- Protocol class registry
Transport.class.protocolClasses = {}
function Transport.class:registerProtocol(protocolClass)
	table.insert(self.protocolClasses, protocolClass)
end

-- Default protocols
Transport:registerProtocol(require("mcnet.transport.TCP"))
Transport:registerProtocol(require("mcnet.transport.UDP"))

-- Exports
return Transport