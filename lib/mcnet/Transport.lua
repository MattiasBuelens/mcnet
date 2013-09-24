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
	self.protocols = self:createProtocols()
	self.network = Network:new(address)
end
function Transport:getProtocol(protocolId)
	return self.protocols[string.lower(protocolId)]
end
function Transport:addProtocol(protocol)
	self.protocols[string.lower(protocol:getIdentifier())] = protocol
end
function Transport:createProtocols()
	-- Instantiate protocols
	local protocols = {}
	for _,protocolClass in pairs(Transport.class.protocolClasses) do
		local protocol = protocolClass:new()
		-- Register send event handler
		protocol:on("send", function(...)
			self:rawSend(protocol, ...)
		end)
		self:addProtocol(protocol)
	end
	return protocols
end
function Protocol:isOpen()
	return self.open
end
function Transport:open()
	assert(not self:isOpen(), "attempted to open already opened transport entity")
	-- Open network
	self.network:open()
	-- Open protocols
	for _,protocol in pairs(self.protocols) do
		protocol:open()
	end
	-- Register event handlers
	self.network:on("receive", self.onReceive, self)
	self:trigger("open")
end
function Transport:close()
	assert(not self:isOpen(), "attempted to close already closed transport entity")
	-- Unregister event handlers
	self.network:off("receive", self.onReceive, self)
	-- Close protocols
	for _,protocol in pairs(self.protocols) do
		protocol:close()
	end
	-- Close network
	self.network:close()
	self:trigger("close")
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
	table.insert(Transport.class.protocolClasses, protocolClass)
end

-- Default protocols
Transport:registerProtocol(require("mcnet.transport.TCP"))
Transport:registerProtocol(require("mcnet.transport.UDP"))

-- Exports
return Transport