--[[

	MCNet
	Link layer

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"

-- Constants
local CHANNEL_BROADCAST = 65535

-- Identifiers
local LINK_CMD_CONNECT		= "CON"	-- Connect to peers
local LINK_CMD_DISCONNECT	= "DSC"	-- Disconnect from peers
local LINK_CMD_GREET		= "GRT"	-- Peer replies to connect
local LINK_CMD_DATA			= "DAT"	-- Data to peer
local LINK_CMD_PING			= "PIN"	-- Ping to peer
local LINK_CMD_PONG			= "PON"	-- Pong back to peer

-- Configuration
local PING_DELAY		= 30	-- Time between pings
local PONG_TIMEOUT		= 5		-- Pong timeout

local tValidSides = {}
for n,side in ipairs(rs.getSides()) do
	tValidSides[side] = true
end

-- Fragment
local Fragment = Object:subclass("mcnet.link.Fragment")

function Fragment:initialize(command, data)
	self.command = command or LINK_CMD_DATA
	self.data = data or ""
end
function Fragment.class:parse(message)
	return self:new(string.match(message, "^([^#]+)#(.*)$"))
end
function Fragment:serialize()
	return tostring(self.command) .. "#" .. tostring(self.data)
end
function Fragment.class:serialize(fragment)
	-- Serialize fragment for transmission
	if type(fragment) == "table" then
		return fragment:serialize()
	end
	return tostring(fragment)
end
function Fragment.class:forData(data)
	-- Build fragment for data
	return self:new(LINK_CMD_DATA, tostring(data))
end

-- Interface
local Interface = Object:subclass("mcnet.link.Interface")
Interface:has("side", {
	is = "r"
})
Interface:has("peers", {
	is = "r"
})

function Interface:initialize(side, replyChannel)
	self.side = side
	self.modem = peripheral.wrap(side)
	self.replyChannel = replyChannel
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
Link:has("address", {
	is = "r"
})

function Link:initialize(address)
	super.initialize(self)
	self.address = address or os.getComputerID()
	self.peers = {}
	self.peersPonged = {}
	self.interfaces = {}
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
		self:trigger("peer_connect", peer)
	end
end
function Link:removePeer(peer)
	local isRemoved = (self.peers[peer] ~= nil)
	self.peers[peer] = nil
	if isRemoved then
		self:trigger("peer_disconnect", peer)
	end
end
function Link:open()
	-- Open interfaces
	for _,side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" then
			local interface = Interface:new(side, self:getAddress())
			self.interfaces[side] = interface
			interface:open()
		end
	end
	self:trigger("open")
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
	self:trigger("close")
end
function Link:connect()
	-- Broadcast SYN
	self:broadcast(Fragment:new(LINK_CMD_CONNECT))
	self:trigger("connect")
	-- Schedule ping
	self:schedulePing()
end
function Link:disconnect()
	-- Remove timers
	self.pingTimer, self.pongTimer = nil, nil
	-- Broadcast FIN
	self:broadcast(Fragment:new(LINK_CMD_DISCONNECT))
	-- Clear peers
	self.peers = {}
	self:trigger("disconnect")
end
function Link.class:buildFragment(fragment)
	if type(fragment) == "string" then
		fragment = Fragment:forData(fragment)
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
	self:broadcast(Fragment:new(LINK_CMD_PING))
	-- Schedule pong timeout
	self.pongTimer = os.startTimer(PONG_TIMEOUT)
end
function Link:schedulePing()
	-- Start ping timer
	self.pingTimer = os.startTimer(PING_DELAY)
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
	for peer, bPonged in pairs(self.peersPonged) do
		if not bPonged then self:removePeer(peer) end
	end
	self.peersPonged = {}
end
function Link:onModemMessage(side, senderChannel, replyChannel, message, distance)
	local fragment = Fragment:parse(message)
	local command = fragment.command
	local peer = replyChannel
	-- Ignore own messages from a loop in the network
	if peer == self.address then return end
	-- Check command
	if command == LINK_CMD_DATA then
		-- Data fragment
		local isBroadcast = (senderChannel == CHANNEL_BROADCAST)
		self:trigger("receive", peer, fragment.data, distance, isBroadcast)
	elseif command == LINK_CMD_PING then
		-- Ping received, send pong
		self:send(peer, Fragment:new(LINK_CMD_PONG))
	elseif command == LINK_CMD_PONG then
		-- Pong received
		self:receivePong(peer, side)
	elseif command == LINK_CMD_CONNECT then
		-- Peer connected
		self:addPeer(peer, side)
		-- Greet peer
		self:send(peer, Fragment:new(LINK_CMD_GREET))
	elseif command == LINK_CMD_GREET then
		-- Peer greeted us
		self:addPeer(peer, side)
	elseif command == LINK_CMD_DISCONNECT then
		-- Peer disconnected
		self:removePeer(peer)
	end
end
function Link:onTimer(timerID)
	if timerID == self.pingTimer then
		-- Next ping
		self:ping()
	elseif timerID == self.pongTimer then
		-- Remove non-responding peers
		self:removeNotResponding()
		-- Schedule next ping
		self:schedulePing()
	end
end

-- Exports
return Link