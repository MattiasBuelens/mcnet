--[[

	MCNet
	UDP: Unreliable datagram protocol

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local Protocol		= require "mcnet.transport.Protocol"

-- Datagram
local Datagram = Object:subclass("mcnet.transport.udp.Datagram")
function Datagram:initialize(sourcePort, destPort, data)
	self.sourcePort = tonumber(sourcePort)
	self.destPort = tonumber(destPort)
	self.data = data or ""
end
function Datagram.class:parse(message)
	return self:new(string.match(message, "^(%d+)#(%d+)#(.*)$"))
end
function Datagram:serialize()
	return tostring(self.sourcePort)
		.. "#" .. tostring(self.destPort)
		.. "#" .. tostring(self.data)
end
function Datagram.class:serialize(datagram)
	-- Serialize datagram for transmission
	if type(datagram) == "table" then
		return datagram:serialize()
	end
	return tostring(datagram)
end

-- Connection
local Connection = EventEmitter:subclass("mcnet.transport.udp.Connection")
function Connection:initialize(protocol, destAddress, destPort, sourcePort)
	super.initialize(self)
	self.protocol = protocol
	-- Addressing
	self.destAddress = tonumber(destAddress)
	self.destPort = tonumber(destPort)
	self.sourcePort = tonumber(sourcePort)
	-- Connection state
	self.open = true
end
function Connection:isOpen()
	return self.open
end
function Connection:close()
	if self:isOpen() then
		self.open = false
		self:trigger("close")
	end
end
function Connection:send(data)
	if not self:isOpen() then
		error("connection already closed")
	end
	if type(data) ~= "string" then
		error("data must be string, "..type(data).." given: "..tostring(data))
	end
	local datagram = Datagram:new(self.sourcePort, self.destPort, data)
	self.protocol:rawSend(self.destAddress, datagram)
end
function Connection:onReceive(datagram)
	-- Handle datagram
	self:trigger("receive", datagram.data)
end

-- Protocol
local UDP = Protocol:subclass("mcnet.transport.udp.Protocol")
function UDP:initialize()
	super.initialize(self)
	self.listenHandlers = {}
	self.connections = {}
end
function UDP:getIdentifier()
	return "UDP"
end
function UDP:close()
	-- Unlink connections table (ignore removes)
	local connections = self.connections
	self.connections = {}
	-- Close connections
	for key,conn in pairs(connections) do
		conn:close()
	end
	super.close(self)
end
function UDP:rawSend(destAddress, datagram)
	super.rawSend(self, destAddress, Datagram:serialize(datagram))
end
function UDP:getListenHandler(sourcePort)
	return self.listenHandlers[sourcePort]
end
function UDP:isListening(sourcePort)
	return self:getListenHandler(sourcePort) ~= nil
end
function UDP:listen(sourcePort, handler)
	self.listenHandlers[sourcePort] = handler
end
function UDP:stopListening(sourcePort)
	self.listenHandlers[sourcePort] = nil
end
function UDP:connect(destAddress, destPort, sourcePort)
	sourcePort = tonumber(sourcePort) or self:getClientPort(destAddress, destPort)
	if self:hasConnection(destAddress, destPort, sourcePort) then
		error("already connected to "..destAddress..":"..destPort" on port "..sourcePort)
	end
	return self:createConnection(destAddress, destPort, sourcePort)
end
function UDP:getClientPort(destAddress, destPort)
	-- Find a random open client port
	local sourcePort
	repeat
		sourcePort = self:getRandomClientPort()
	until not self:hasConnection(destAddress, destPort, sourcePort)
	return sourcePort
end
function UDP:hasConnection(destAddress, destPort, sourcePort)
	return self:getConnection(destAddress, destPort, sourcePort) ~= nil
end
function UDP:hasConnections()
	return next(self.connections) ~= nil
end
function UDP:getConnection(destAddress, destPort, sourcePort)
	return self.connections[self:getConnectionKey(destAddress, destPort, sourcePort)] or nil
end
function UDP:getConnectionKey(destAddress, destPort, sourcePort)
	return tostring(destAddress)
		.. "#" .. tostring(destPort)
		.. "#" .. tostring(sourcePort)
end
function UDP:createConnection(destAddress, destPort, sourcePort)
	local conn = Connection:new(self, destAddress, destPort, sourcePort)
	-- Store connection
	local key = self:getConnectionKey(destAddress, destPort, sourcePort)
	self.connections[key] = conn
	-- Register remove handler
	conn:on("close", function()
		if self:hasConnections() and self.connections[key] == conn then
			self.connections[key] = nil
		end
	end, self)
	return conn
end
function UDP:onReceive(sourceAddress, data)
	-- Parse datagram
	local datagram = Datagram:parse(data)
	-- Reverse source/destination terminology
	local destAddress, destPort, sourcePort = sourceAddress, datagram.sourcePort, datagram.destPort
	-- New connection
	if not self:hasConnection(destAddress, destPort, sourcePort) then
		-- Find listen handler
		local listenHandler = self:getListenHandler(sourcePort)
		if listenHandler ~= nil then
			-- Listening, establish active connection
			local conn = self:createConnection(destAddress, destPort, sourcePort)
			-- Call handler
			listenHandler(conn)
		else
			-- Not listening, ignore
			return
		end
	end
	-- Get receiving connection
	local conn = self:getConnection(destAddress, destPort, sourcePort)
	if conn ~= nil then
		conn:onReceive(datagram)
	end
end

-- Exports
return UDP