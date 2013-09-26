--[[

	MCNet
	Network layer

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"

-- Identifiers
local HEADER_PACKET			= "PKT"	-- Packet
local HEADER_RIP			= "RIP"	-- Routing fragment
local RIP_CMD_PUBLISH		= "PUB" -- Publish routing table

-- Routing configuration
local RIP_MAX_DISTANCE		= 16	-- The maximum distance
local RIP_ENTRY_LIFETIME	= 30	-- Maximum lifetime of a valid routing entry
local RIP_PUBLISH_DELAY		= 15	-- Time between two routing table publishes

-- Network configuration
local TTL_DEFAULT			= 10	-- Default time-to-live for packets on the network

-- Packet
local Packet = Object:subclass("mcnet.network.Packet")
function Packet:initialize(sourceAddress, destAddress, ttl, data)
	self.sourceAddress = tonumber(sourceAddress)
	self.destAddress = tonumber(destAddress)
	self.ttl = tonumber(ttl)
	self.data = data or ""
end
function Packet.class:parse(message)
	return self:new(string.match(message, "^"..HEADER_PACKET.."#(%d+)#(%d+)#(%d+)#(.*)$"))
end
function Packet.class:test(message)
	return string.find(message, "^"..HEADER_PACKET) ~= nil
end
function Packet:serialize()
	return HEADER_PACKET
		.. "#" .. tostring(self.sourceAddress)
		.. "#" .. tostring(self.destAddress)
		.. "#" .. tostring(self.ttl)
		.. "#" .. tostring(self.data)
end
function Packet.class:serialize(packet)
	-- Serialize packet for transmission
	if type(packet) == "table" then
		return packet:serialize()
	end
	return tostring(packet)
end

-- Routing table entry
local RoutingEntry = Object:subclass("mcnet.network.RoutingEntry")
function RoutingEntry:initialize(destination, ...)
	self.destination = destination
	self:set(...)
end
function RoutingEntry:set(distance, peer, persistent)
	self.distance = distance
	self.peer = peer
	self.persistent = persistent or false
	self:touch()
end
function RoutingEntry:touch()
	if self.persistent then
		-- Persistent entries do not need updates
		return false
	end
	-- Update last update time
	self.lastUpdate = os.clock()
	return true
end
function RoutingEntry:isValid()
	return self.persistent or self.distance < RIP_MAX_DISTANCE
end
function RoutingEntry:invalidate()
	if self.persistent then
		-- Persistent entries never become invalid
		return false
	end
	-- Invalidate distance
	self.distance = RIP_MAX_DISTANCE
	return true
end
function RoutingEntry:isExpired(currentClock)
	if self.persistent then
		-- Persistent entries never expire
		return false
	end
	-- Check last update time
	return (currentClock or os.clock()) > (self.lastUpdate + RIP_ENTRY_LIFETIME)
end

-- Routing fragment
local RoutingFragment = Object:subclass("mcnet.network.RoutingFragment")
function RoutingFragment:initialize(command, data)
	self.command = command
	self.data = data or ""
end
function RoutingFragment.class:parse(message)
	return self:new(string.match(message, "^"..HEADER_RIP.."#([^#]+)#(.*)$"))
end
function RoutingFragment.class:test(message)
	return string.find(message, "^"..HEADER_RIP) ~= nil
end
function RoutingFragment:serialize()
	return HEADER_RIP
		.. "#" .. tostring(self.command)
		.. "#" .. tostring(self.data)
end
function RoutingFragment.class:serialize(fragment)
	-- Serialize fragment for transmission
	if type(fragment) == "table" then
		return fragment:serialize()
	end
	return tostring(fragment)
end

-- Routing table
local RoutingTable = Object:subclass("mcnet.network.RoutingTable")
function RoutingTable:initialize()
	self:reset()
end
function RoutingTable:add(entry)
	self.entries[entry.destination] = entry
end
function RoutingTable:get(destination)
	return self.entries[destination] or nil
end
function RoutingTable:set(destination, ...)
	local entry = self:get(destination)
	if entry == nil then
		self:add(RoutingEntry:new(destination, ...))
	else
		entry:set(...)
	end
end
function RoutingTable:remove(destination)
	self.entries[destination] = nil
end
function RoutingTable:reset()
	self.entries = {}
end
function RoutingTable:publish()
	-- Create map from destinations to distances
	local t = {}
	for destination,entry in pairs(self.entries) do
		t[destination] = entry.distance
	end
	return t
end
function RoutingTable:merge(routerAddress, routerDistance, routerTable)
	-- Merge results from neighbour router into own table
	for destination,distance in pairs(routerTable) do
		local entry = self:get(destination)
		local totalDistance = distance + routerDistance
		if entry == nil then
			-- New entry
			self:set(destination, totalDistance, routerAddress)
		elseif entry.peer == routerAddress and distance >= RIP_MAX_DISTANCE then
			-- Neighbour router reports destination as unreachable
			entry:invalidate()
		elseif entry.peer == routerAddress and entry.distance == totalDistance then
			-- Entry still up to date
			entry:touch()
		elseif entry.distance > totalDistance then
			-- Update existing entry if shorter distance
			entry:set(totalDistance, routerAddress)
		end
	end
end
function RoutingTable:invalidate(routerAddress)
	-- Invalidate direct route to router
	local routerEntry = self:get(routerAddress)
	if routerEntry.peer == routerAddress then
		routerEntry:invalidate()
	end
	-- Invalidate routes through router
	for destination,entry in pairs(self.entries) do
		if entry.peer == routerAddress then
			entry:invalidate()
		end
	end
end
function RoutingTable:invalidateExpired()
	-- Invalidate expired routes
	local currentClock = os.clock()
	for destination,entry in pairs(self.entries) do
		if entry:isValid() and entry:isExpired(currentClock) then
			entry:invalidate()
		end
	end
end

-- Network
local Network = EventEmitter:subclass("mcnet.network.Network")
function Network:initialize(address)
	super.initialize(self)
	self.link = require("mcnet.Link")
	self.address = self.link.address
	self.bOpen = false
	self.table = RoutingTable:new()
	-- Open immediately
	self:open()
end
function Network:isOpen()
	return self.bOpen
end
function Network:open()
	if self:isOpen() then return false end
	self.bOpen = true
	-- Register event handlers
	EventLoop:on("timer", self.onTimer, self)
	EventLoop:on("terminate", self.close, self)
	self.link:on("receive", self.onReceive, self)
	self.link:on("connect", self.ripStart, self)
	self.link:on("disconnect", self.ripStop, self)
	self.link:on("peer_connect", self.ripPeerConnect, self)
	self.link:on("peer_disconnect", self.ripPeerDisconnect, self)
	-- Open link
	self.link:open()
	-- Initialize routing table
	self.table:reset()
	self.table:set(self.address, 0, self.address, true)
	for _,peer in pairs(self.link:getPeers()) do
		self:ripPeerConnect(peer)
	end
	self:trigger("open")
	return true
end
function Network:close()
	if not self:isOpen() then return false end
	self.bOpen = false
	-- Close link
	self.link:close()
	-- Clear routing table
	self.table:reset()
	-- Unregister event handlers
	EventLoop:off("timer", self.onTimer, self)
	EventLoop:off("terminate", self.close, self)
	self.link:off("receive", self.onReceive, self)
	self.link:off("connect", self.ripStart, self)
	self.link:off("disconnect", self.ripStop, self)
	self.link:off("peer_connect", self.ripPeerConnect, self)
	self.link:off("peer_disconnect", self.ripPeerDisconnect, self)
	self:trigger("close")
	return true
end
function Network:send(destAddress, data, ttl)
	assert(self:isOpen(), "cannot send packet over closed network")
	if ttl == nil then
		ttl = TTL_DEFAULT
	end
	self:route(Packet:new(self.address, destAddress, ttl, data))
end
function Network:ripPublish()
	-- Purge expired routing entries
	self.table:invalidateExpired()
	-- Publish routing table
	local data = textutils.serialize(self.table:publish())
	local fragment = RoutingFragment:new(RIP_CMD_PUBLISH, data)
	self.link:broadcast(fragment:serialize())
end
function Network:ripSchedulePublish()
	-- Schedule next update timer
	self.ripPublishTimer = os.startTimer(RIP_PUBLISH_DELAY)
end
function Network:ripStart()
	-- Initial publish
	self:ripPublish()
	self:ripSchedulePublish()
end
function Network:ripStop()
	-- Stop publish timer
	self.ripPublishTimer = nil
	-- No extra commands needed
	-- Peers will handle our disconnect
end
function Network:ripPeerConnect(peer)
	-- Add peer to routing table
	self.table:set(peer, 1, peer)
end
function Network:ripPeerDisconnect(peer)
	-- Invalidate router
	self.table:invalidate(peer)
end
function Network:handlePacket(peer, packet)
	-- Check destination
	if packet.destAddress == self.address then
		-- Our packet
		self:trigger("receive", packet.sourceAddress, packet.data)
		return
	end
	-- Decrease TTL
	packet.ttl = packet.ttl - 1
	if packet.ttl <= 0 then
		-- Drop packet, TTL below zero
		self:trigger("drop", packet, "ttl")
		return
	end
	-- Route packet
	return self:route(packet)
end
function Network:route(packet)
	assert(self:isOpen(), "cannot route packet over closed network")
	-- Route the packet to the next hop
	local entry = self.table:get(packet.destAddress)
	if entry ~= nil and entry:isValid() then
		-- Route found
		self:trigger("route", packet, entry.peer)
		self.link:send(entry.peer, Packet:serialize(packet))
	else
		-- Drop packet, no route found
		self:trigger("drop", packet, "route")
	end
end
function Network:ripHandleFragment(peer, fragment)
	if fragment.command == RIP_CMD_PUBLISH then
		-- Merge peer's routing table into own table
		self.table:merge(peer, 1, textutils.unserialize(fragment.data))
	end
end
function Network:onReceive(peer, data)
	if Packet:test(data) then
		-- Packet
		self:handlePacket(peer, Packet:parse(data))
	elseif RoutingFragment:test(data) then
		-- Routing fragment
		self:ripHandleFragment(peer, RoutingFragment:parse(data))
	end
end
function Network:onTimer(timerID)
	if timerID == self.ripPublishTimer then
		-- Publish and schedule next publish
		self:ripPublish()
		self:ripSchedulePublish()
	end
end

-- Exports
return Network:new()