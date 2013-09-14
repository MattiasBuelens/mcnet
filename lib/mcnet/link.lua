--[[

	MCNet
	Link layer

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"

-- Constants
local CHANNEL_BROADCAST = 65535
local FLAG_CONNECT		= "CON"	-- Connect to peers
local FLAG_DISCONNECT	= "DSC"	-- Disconnect from peers
local FLAG_GREET		= "GRT"	-- Peer replies to connect
local FLAG_MESSAGE		= "MSG"	-- Message to peer
local FLAG_PING			= "PIN"	-- Ping to peer
local FLAG_PONG			= "PON"	-- Pong back to peer

local PING_TIMEOUT		= 10	-- Time between pings

local tValidSides = {}
for n,side in ipairs(rs.getSides()) do
	tValidSides[side] = true
end

-- Fragment
local Fragment = Object:subclass("mcnet.link.Fragment")

function Fragment:initialize(flags, data)
	self.flags = self:parseFlags(flags)
	self.data = data or ""
end
function Fragment:hasFlag(flag)
	return self.flags[flag] or false
end
function Fragment:setFlag(flag, bSet)
	self.flags[flag] = bSet
end
function Fragment:getFlagsList()
	local aFlags = {}
	for sFlag, bSet in pairs(self.flags) do
		if bSet then table.insert(aFlags, sFlag) end
	end
	return aFlags
end
function Fragment.class:parse(message)
	return self:new(string.match(message, "^([^#]+)#(.*)$"))
end
function Fragment:parseFlags(flags)
	local tFlags = {}
	if type(flags) == "string" then
		for flag in string.gmatch(flags, "[^+]+") do
			tFlags[flag] = true
		end
	elseif type(flags) == "table" then
		for _,flag in pairs(flags) do
			tFlags[flag] = true
		end
	end
	return tFlags
end
function Fragment:serialize()
	return table.concat(self:getFlagsList(), "+") .. "#" .. tostring(self.data)
end
function Fragment.class:serialize(fragment)
	-- Serialize fragment for transmission
	if type(fragment) == "table" then
		return fragment:serialize()
	end
	return tostring(fragment)
end
function Fragment.class:forMessage(message)
	-- Build fragment for message
	return self:new(FLAG_MSG, tostring(message))
end

-- Interface
local Interface = Object:subclass("mcnet.link.Interface")
Interface:has("side", {
	is = "r"
})
Interface:has("peers", {
	is = "r"
})

function Interface:initialize(side)
	self.side = side
	self.modem = peripheral.wrap(side)
	self.replyChannel = os.getComputerID()
end
function Interface:open(callback)
	rednet.open(self:getSide())
end
function Interface:close()
	rednet.close(self:getSide())
end
function Interface:isOpen()
	return rednet.isOpen(self:getSide())
end
function Interface:broadcast(fragment)
	assert(self:isOpen())
	self.modem.transmit(CHANNEL_BROADCAST, self.replyChannel, Fragment:serialize(fragment))
end
function Interface:send(peer, fragment)
	assert(self:isOpen())
	self.modem.transmit(peer, self.replyChannel, Fragment:serialize(fragment))
end

-- Link
local Link = EventEmitter:subclass("mcnet.link.Link")
function Link:initialize()
	super.initialize(self)
	self.peers = {}
	self.peersPonged = nil
	self.interfaces = {}
	self.replyChannel = os.getComputerID()
end
function Link:getPeersList()
	local aPeers = {}
	for sPeer, sSide in pairs(self.peers) do
		if tValidSides[sSide] and self.interfaces[sSide]:isOpen() then
			table.insert(aPeers, sPeer)
		end
	end
	return aPeers
end
function Link:hasPeer(peer)
	return self.peers[peer] or false
end
function Link:addPeer(peer, side)
	local isAdded = (self.peers[peer] == nil)
	self.peers[peer] = side
	if isAdded then
		self:trigger("peer_connected", peer)
	end
end
function Link:removePeer(peer)
	local isRemoved = (self.peers[peer] ~= nil)
	self.peers[peer] = nil
	if isRemoved then
		self:trigger("peer_disconnected", peer)
	end
end
function Link:open()
	-- Open interfaces
	for _,side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" then
			local interface = Interface:new(side)
			self.interfaces[side] = interface
			interface:open()
		end
	end
	self:trigger("opened")
	-- Register event handlers
	EventLoop:on("modem_message", self.onModemMessage, self)
	EventLoop:on("timer", self.onTimer, self)
	-- Connect to peers
	self:connect()
end
function Link:close()
	-- Disconnect from peers
	self:disconnect()
	-- Unregister event handlers
	EventLoop:off("modem_message", self.onModemMessage, self)
	EventLoop:off("timer", self.onTimer, self)
	-- Close interfaces
	for side,interface in pairs(self.interfaces) do
		interface:close()
	end
	self.interfaces = {}
	self:trigger("closed")
end
function Link:connect()
	-- Broadcast SYN
	self:broadcast(Fragment:new(FLAG_CONNECT))
	self:trigger("connected")
	-- Schedule ping
	self:schedulePing()
end
function Link:disconnect()
	-- Remove ping timer
	self.pingTimer = nil
	-- Broadcast FIN
	self:broadcast(Fragment:new(FLAG_DISCONNECT))
	-- Clear peers
	self.peers = {}
	self:trigger("disconnected")
end
function Link.class:buildFragment(fragment)
	if type(fragment) == "string" then
		fragment = Fragment:forMessage(fragment)
	end
	return fragment
end
function Link:broadcast(fragment)
	-- Broadcast over all interfaces
	fragment = Fragment:serialize(Link:buildFragment(fragment))
	for side,interface in pairs(self.interfaces) do
		if interface:isOpen() then
			interface:broadcast(fragment)
		end
	end
end
function Link:send(peer, fragment)
	-- Send over single interface
	fragment = Fragment:serialize(Link:buildFragment(fragment))
	local side = self.peers[peer]
	if side ~= nil then
		local interface = self.interfaces[side]
		if interface ~= nil and interface:isOpen() then
			return interface:send(peer, fragment)
		end
	end
	return false
end
function Link:ping()
	self.peersPonged = {}
	for peer,side in pairs(self.peers) do
		self.peersPonged[peer] = false
	end
	-- Broadcast ping
	self:broadcast(Fragment:new(FLAG_PING))
	-- Schedule ping
	self:schedulePing()
end
function Link:schedulePing()
	-- Start timer
	self.pingTimer = os.startTimer(PING_TIMEOUT)
end
function Link:receivePong(peer, side)
	-- Mark as responding
	self.peersPonged[peer] = true
	-- Update side
	-- Handles peers connected through multiple modem links
	-- and one link is broken while others are still reachable
	self:addPeer(peer, side)
end
function Link:removeNotResponding()
	if type(self.peersPonged) == "table" then
		for peer, bPonged in pairs(self.peersPonged) do
			if not bPonged then self:removePeer(peer) end
		end
	end
	self.peersPonged = nil
end
function Link:onModemMessage(side, senderChannel, replyChannel, message, distance)
	local fragment = Fragment:parse(message)
	local peer = replyChannel
	-- Ignore own messages from a loop in the network
	if replyChannel == self.replyChannel then return end
	-- Check flags
	if fragment:hasFlag(FLAG_MESSAGE) then
		-- Message
		local isBroadcast = (senderChannel == CHANNEL_BROADCAST)
		self:trigger("message", message, peer, isBroadcast, distance)
	elseif fragment:hasFlag(FLAG_PING) then
		-- Ping received, send pong
		self:send(peer, Fragment:new(FLAG_PONG))
	elseif fragment:hasFlag(FLAG_PONG) then
		-- Pong received
		self:receivePong()
	elseif fragment:hasFlag(FLAG_CONNECT) then
		-- Peer connected
		self:addPeer(peer, side)
		-- Greet peer
		self:send(peer, Fragment:new(FLAG_GREET))
	elseif fragment:hasFlag(FLAG_GREET) then
		-- Peer greeted us
		self:addPeer(peer, side)
	elseif fragment:hasFlag(FLAG_DISCONNECT) then
		-- Peer disconnected
		self:removePeer(peer)
	end
end
function Link:onTimer(timerID)
	if timerID == self.pingTimer then
		-- Remove non-responding peers
		self:removeNotResponding()
		-- Next ping
		self:ping()
	end
end

-- Exports
return Link:new()