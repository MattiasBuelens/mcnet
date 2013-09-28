--[[

	MCNet
	TCP: Transport control protocol

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"
local Protocol		= require "mcnet.transport.Protocol"

-- Constants
local FLAG = {
	SYN		= "SYN",	-- Connect
	FIN		= "FIN",	-- Disconnect
	ACK		= "ACK",	-- Acknowledge
	PING	= "PIN",	-- Ping (alive test)
	PONG	= "PON"		-- Pong (alive reply)
}
local CONN_STATE = {
	IDLE			= 0,
	CONNECTING		= 1,
	ESTABLISHED		= 2,
	DISCONNECTING 	= 3
}
local CONTROL_TIMEOUT		= 10				-- Timeout for control retransmissions, in seconds
local CONTROL_LIMIT			= 5					-- Maximum amount of control retransmissions before closing
local DATA_TIMEOUT			= CONTROL_TIMEOUT	-- Timeout for data retransmissions, in seconds
local DATA_LIMIT			= 5					-- Maximum amount of data retransmissions before closing
local PING_TIMEOUT			= CONTROL_TIMEOUT	-- Timeout for pong replies, in seconds
local PING_LIMIT			= CONTROL_LIMIT		-- Maximum amount of failed pings before closing
local PING_DELAY			= 30				-- Time between pings, in seconds

-- Segment
local Segment = Object:subclass("mcnet.transport.tcp.Segment")
function Segment:initialize(sourcePort, destPort, flags, seqNumber, ackNumber, data)
	self.sourcePort = tonumber(sourcePort)
	self.destPort = tonumber(destPort)
	self.flags = Segment:parseFlags(flags)
	self.seqNumber = tonumber(seqNumber) or 0
	self.ackNumber = tonumber(ackNumber) or 0
	self.data = data or ""
end
function Segment:hasFlag(flag)
	return self.flags[flag] or false
end
function Segment:setFlag(flag, bSet)
	self.flags[flag] = bSet
end
function Segment:getFlags()
	local aFlags = {}
	for sFlag, bSet in pairs(self.flags) do
		if bSet then table.insert(aFlags, sFlag) end
	end
	return aFlags
end
function Segment.class:parse(message)
	return self:new(string.match(message, "^(%d+)#(%d+)#([^#]*)#(%d+)#(%d+)#(.*)$"))
end
function Segment.class:parseFlags(flags)
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
function Segment:serialize()
	return tostring(self.sourcePort)
		.. "#" .. tostring(self.destPort)
		.. "#" .. table.concat(self:getFlags(), "+")
		.. "#" .. tostring(self.seqNumber)
		.. "#" .. tostring(self.ackNumber)
		.. "#" .. tostring(self.data)
end
function Segment.class:serialize(segment)
	-- Serialize segment for transmission
	if type(segment) == "table" then
		return segment:serialize()
	end
	return tostring(segment)
end

local SendQueue = EventEmitter:subclass("mcnet.transport.tcp.SendQueue")
function SendQueue:initialize(timeout, limit)
	super.initialize(self)
	-- Configuration
	self.timeout = timeout				-- Timeout until retransmission
	self.limit = limit or math.huge		-- Maximum retransmissions
	-- State
	self.queue = {}						-- Queue of messages
	self.timer = nil					-- Timeout timer
	self.isSending = false				-- Whether currently sending
	self.attempt = 0					-- Number of send attempts
	-- Event handlers
	EventLoop:on("timer", self.onTimer, self)
end
function SendQueue:send(data, handler)
	-- Add to queue
	table.insert(self.queue, {
		data		= data,
		handler		= handler or nil
	})
	-- Send
	self:resend()
end
function SendQueue:resend()
	-- Must not be sending and must have something to send
	if self.isSending or #self.queue == 0 then
		return false
	end
	-- Increase attempt
	self.attempt = self.attempt + 1
	if self.attempt > self.limit then
		-- Hit limit
		self:trigger("limit")
	else
		-- Send next
		self.isSending = true
		self.timer = os.startTimer(self.timeout)
		self:sendNext()
	end
end
function SendQueue:sendNext()
	self:trigger("send", self.queue[1].data)
end
function SendQueue:deliver()
	-- Must be sending
	if #self.queue == 0 then
		return nil
	end
	-- Remove from queue
	local item = table.remove(self.queue, 1)
	-- Reset
	self.timer = nil
	self.isSending = false
	self.attempt = 0
	-- Call listener
	if item.handler then item.handler() end
	-- Send next
	self:resend()
	return item.data
end
function SendQueue:reset()
	-- Reset state
	self.queue = {}
	self.timer = nil
	self.isSending = false
	self.attempt = 0
end
function SendQueue:onTimer(timerID)
	if self.timer == timerID then
		-- Resend
		self.isSending = false
		self:resend()
	end
end

-- Data queue
local DataQueue = SendQueue:subclass("mcnet.transport.tcp.DataQueue")
function DataQueue:initialize(timeout, limit)
	super.initialize(self, timeout, limit)
	-- State
	self.sendAmount = 0					-- Amount of queue items being sent
end
function DataQueue:sendNext()
	local dataList = self:collectData()
	self:trigger("send", DataQueue:serializeData(dataList))
end
function DataQueue:collectData()
	-- Send whole queue if not resending
	if self.sendAmount == 0 then
		self.sendAmount = #self.queue
	end
	-- Make list of data in queue
	local dataList = {}
	for i=1,self.sendAmount do
		table.insert(dataList, self.queue[i].data)
	end
	return dataList
end
function DataQueue.class:serializeData(dataList)
	return textutils.serialize(dataList)
end
function DataQueue.class:parseData(data)
	return textutils.unserialize(data)
end
function DataQueue:deliver()
	-- Must be sending items
	if self.sendAmount == 0 then
		return {}
	end
	-- Reset
	self.timer = nil
	self.isSending = false
	self.attempt = 0
	-- Delivered items
	local delivered = {}
	for i=1,self.sendAmount do
		-- Remove from queue
		local item = table.remove(self.queue, 1)
		-- Add to delivered
		table.insert(delivered, item)
	end
	self.sendAmount = 0
	-- Delivered data
	local dataList = {}
	for i,item in ipairs(delivered) do
		-- Add to results
		table.insert(dataList, item.data)
		-- Call listener
		if item.handler then item.handler() end
	end
	-- Send next
	self:resend()
	return dataList
end
function DataQueue:reset()
	super.reset(self)
	self.sendAmount = 0
end

-- Connection
local Connection = EventEmitter:subclass("mcnet.transport.tcp.Connection")
function Connection:initialize(protocol, destAddress, destPort, sourcePort)
	super.initialize(self)
	self.protocol = protocol
	-- Addressing
	self.destAddress = tonumber(destAddress)
	self.destPort = tonumber(destPort)
	self.sourcePort = tonumber(sourcePort)
	-- Connection state
	self.state = CONN_STATE.IDLE
	-- Sliding window (stop and wait)
	self.sendSeq = nil					-- Sequence number of segment being sent
	self.receiveSeq = nil				-- Sequence number of next segment to receive
	-- Queues
	self.controlQueue = SendQueue:new(CONTROL_TIMEOUT, CONTROL_LIMIT)
	self.dataQueue = DataQueue:new(DATA_TIMEOUT, DATA_LIMIT)
	self.pingQueue = SendQueue:new(PING_TIMEOUT, PING_LIMIT)
	-- Timers
	self.pingDelay = nil				-- Timer for ping tests
end
function Connection:isOpen()
	return self.state == CONN_STATE.ESTABLISHED
end
function Connection:isClosed()
	return self.state == CONN_STATE.IDLE
end
function Connection:open()
	if self:isClosed() then
		-- Active connect
		self:handleOpening()
		self:control({FLAG.SYN})
	end
end
function Connection:close()
	if self:isOpen() then
		-- Active disconnect
		self:handleClosing()
		self:control({FLAG.FIN})
	end
end
function Connection:forceClose()
	if not self:isClosed() then
		-- Forced disconnect (no waiting for handshake)
		self:close()
		self:handleClose()
	end
end
function Connection:handleOpening()
	-- Initialize
	self.state = CONN_STATE.CONNECTING
	self.sendSeq = math.random(0, 1)
	-- Initialize queues
	self:resetQueues()
	self.controlQueue:on("send", self.sendControl, self)
	self.controlQueue:on("limit", self.handleTimeout, self)
	-- Call listeners
	self:trigger("opening")
end
function Connection:handleOpen()
	-- Initialize
	self.state = CONN_STATE.ESTABLISHED
	-- Initialize queues
	self:resetQueues()
	self.dataQueue:on("send", self.sendData, self)
	self.dataQueue:on("limit", self.handleTimeout, self)
	self.pingQueue:on("send", self.sendPing, self)
	self.pingQueue:on("limit", self.handleTimeout, self)
	-- Initialize ping
	EventLoop:on("timer", self.onTimer, self)
	self:scheduleAliveTest()
	-- Call listeners
	self:trigger("open")
end
function Connection:resetQueues()
	self.controlQueue:reset()
	self.dataQueue:reset()
	self.pingQueue:reset()
end
function Connection:handleClosing()
	-- Reset state
	self:resetQueues()
	-- Reset ping
	EventLoop:off("timer", self.onTimer, self)
	self.pingDelay = nil
	-- Call listeners
	if self.state ~= CONN_STATE.DISCONNECTING then
		self.state = CONN_STATE.DISCONNECTING
		self:trigger("closing")
	end
end
function Connection:handleClose()
	if not self:isClosed() then
		-- Reset state
		self:handleClosing()
		self.state = CONN_STATE.IDLE
		self.receiveSeq = nil
		-- Call listeners
		self:trigger("close")
	end
end
function Connection:handleTimeout()
	if self:isClosed() then
		-- Already closed
	elseif self.state == CONN_STATE.DISCONNECTING then
		-- Timeout while disconnecting
		self:forceClose()
	else
		-- Timeout while connecting or connected
		self:close()
	end
end
function Connection:send(data, handler)
	if not self:isOpen() then
		error("connection not open yet")
	end
	if type(data) ~= "string" then
		error("data must be string, "..type(data).." given: "..tostring(data))
	end
	if handler ~= nil and type(handler) ~= "function" then
		error("handler must be nil or function, "..type(handler).." given: "..tostring(handler))
	end
	self.dataQueue:send(data, handler)
end
function Connection:sendData(data)
	self:rawSend({}, data)
end
function Connection:sendControl(flags)
	self:rawSend(flags)
end
function Connection:sendAck()
	self:rawSend({FLAG.ACK})
end
function Connection:rawSend(flags, data)
	local segment = Segment:new(self.sourcePort, self.destPort, flags, self.sendSeq, self.receiveSeq, data)
	self.protocol:rawSend(self.destAddress, segment)
end
function Connection:control(flags)
	-- Remove previous control segment
	self.controlQueue:deliver()
	-- Send new control segment
	self.controlQueue:send(flags)
end
function Connection:ping()
	-- Send a ping
	self.pingQueue:send()
end
function Connection:handlePing()
	-- Ping received, reply
	self:rawSend({FLAG.PONG})
end
function Connection:handlePong()
	-- Pong received, still alive
	self.pingQueue:deliver()
	self:scheduleAliveTest()
end
function Connection:scheduleAliveTest()
	self.pingDelay = os.startTimer(PING_DELAY)
end
function Connection:sendPing()
	self:rawSend({FLAG.PING})
end
function Connection:handleData(segment)
	-- Check for duplicate with sender's sequence number
	if segment.seqNumber ~= self.receiveSeq then
		-- Sequence number mismatch, resend ACK
		self:trigger("log", "duplicate data segment received: "..segment.data)
		self:trigger("log", "exp: "..tostring(self.receiveSeq)..", rec: "..tostring(segment.seqNumber))
		return self:sendAck()
	end
	-- Update next sequence number from destination
	self.receiveSeq = self:nextSeq(self.receiveSeq)
	-- Send ACK
	self:sendAck()
	-- Call listeners
	local dataList = DataQueue:parseData(segment.data)
	for i,data in ipairs(dataList) do
		self:trigger("receive", data)
	end
end
function Connection:handleAck(segment)
	-- Check for expected ACK number
	local expectedSeq = self:nextSeq(self.sendSeq)
	if segment.ackNumber ~= expectedSeq then
		-- Sequence number mismatch, ignore
		self:trigger("log", "duplicate ack received: "..segment.ackNumber)
		self:trigger("log", "exp: "..tostring(expectedSeq)..", rec: "..tostring(segment.ackNumber))
		return
	end
	-- Successfully delivered
	self.sendSeq = expectedSeq
	local dataList = self.dataQueue:deliver()
	for i,data in ipairs(dataList) do
		self:trigger("deliver", data)
	end
end
function Connection:nextSeq(number)
	-- Get the next sequence number
	return math.fmod(number + 1, 2)
end
function Connection:verifyOwn(segment)
	if self.sendSeq ~= segment.ackNumber then
		-- Mismatch with own sequence number
		self:trigger("log", "own sequence number mismatch, closing")
		self:close()
		return false
	end
	return true
end
function Connection:verifyBoth(segment)
	if self.receiveSeq ~= segment.seqNumber then
		-- Mismatch with other sequence number
		self:trigger("log", "other sequence number mismatch, closing")
		self:close()
		return false
	end
	return self:verifyOwn(segment)
end
function Connection:onReceive(segment)
	-- Handle segment
	if segment:hasFlag(FLAG.SYN) then
		if segment:hasFlag(FLAG.ACK) then
			if self.state == CONN_STATE.CONNECTING then
				if self:verifyOwn(segment) then
					-- Active connect accepted
					self.receiveSeq = segment.seqNumber
					self:handleOpen()
					-- Send (unchecked) ACK
					self:sendAck()
				end
			end
		else
			if self.state == CONN_STATE.IDLE then
				-- Connect request, initialize sliding window
				self.receiveSeq = segment.seqNumber
				self:handleOpening()
				-- Send SYN/ACK
				self:control({FLAG.SYN, FLAG.ACK})
			end
		end
	elseif segment:hasFlag(FLAG.FIN) then
		if segment:hasFlag(FLAG.ACK) then
			if self.state == CONN_STATE.DISCONNECTING then
				-- Active disconnect accepted
				-- Send (unchecked) ACK
				self:sendAck()
				-- Clean disconnect
				self:handleClose()
			end
		else
			if self.state == CONN_STATE.ESTABLISHED then
				-- Disconnect request
				self:handleClosing()
				-- Send FIN/ACK
				self:control({FLAG.FIN, FLAG.ACK})
			end
		end
	elseif segment:hasFlag(FLAG.PING) then
		-- Ping
		self:handlePing()
	elseif segment:hasFlag(FLAG.PONG) then
		-- Pong
		self:handlePong()
	elseif segment:hasFlag(FLAG.ACK) then
		if self.state == CONN_STATE.ESTABLISHED then
			-- ACK
			self:handleAck(segment)
		elseif self.state == CONN_STATE.CONNECTING then
			if self:verifyBoth(segment) then
				-- Established, initialize sliding window
				self:handleOpen()
			end
		elseif self.state == CONN_STATE.DISCONNECTING then
			-- Clean disconnect
			self:handleClose()
		end
	else
		if self.state == CONN_STATE.ESTABLISHED then
			-- Data
			self:handleData(segment)
		end
	end
end
function Connection:onTimer(timerID)
	if timerID == self.pingDelay then
		-- Alive test
		self:ping()
	end
end

-- Protocol
local TCP = Protocol:subclass("mcnet.transport.tcp.Protocol")
function TCP:initialize()
	super.initialize(self)
	self.listenHandlers = {}
	self.connections = {}
end
function TCP:getIdentifier()
	return "TCP"
end
function TCP:close()
	if not self:isOpen() then return false end
	-- Unlink connections table (ignore removes)
	local connections = self.connections
	self.connections = {}
	-- Force close connections
	for key,conn in pairs(connections) do
		conn:forceClose()
	end
	return super.close(self)
end
function TCP:rawSend(destAddress, segment)
	super.rawSend(self, destAddress, Segment:serialize(segment))
end
function TCP:getListenHandler(sourcePort)
	return self.listenHandlers[sourcePort]
end
function TCP:isListening(sourcePort)
	return self:getListenHandler(sourcePort) ~= nil
end
function TCP:listen(sourcePort, handler)
	self.listenHandlers[sourcePort] = handler
end
function TCP:stopListening(sourcePort)
	self.listenHandlers[sourcePort] = nil
end
function TCP:connect(destAddress, destPort, sourcePort)
	sourcePort = tonumber(sourcePort) or self:getClientPort(destAddress, destPort)
	-- Active connect
	if self:hasConnection(destAddress, destPort, sourcePort) then
		error("already connected to "..destAddress..":"..destPort" on port "..sourcePort)
	end
	local conn = self:createConnection(destAddress, destPort, sourcePort)
	conn:open()
	return conn
end
function TCP:getClientPort(destAddress, destPort)
	-- Find a random open client port
	local sourcePort
	repeat
		sourcePort = self:getRandomClientPort()
	until not self:hasConnection(destAddress, destPort, sourcePort)
	return sourcePort
end
function TCP:hasConnection(destAddress, destPort, sourcePort)
	return self:getConnection(destAddress, destPort, sourcePort) ~= nil
end
function TCP:hasConnections()
	return next(self.connections) ~= nil
end
function TCP:getConnection(destAddress, destPort, sourcePort)
	return self.connections[self:getConnectionKey(destAddress, destPort, sourcePort)] or nil
end
function TCP:getConnectionKey(destAddress, destPort, sourcePort)
	return tostring(destAddress)
		.. "#" .. tostring(destPort)
		.. "#" .. tostring(sourcePort)
end
function TCP:createConnection(destAddress, destPort, sourcePort)
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
function TCP:onReceive(sourceAddress, data)
	-- Parse segment
	local segment = Segment:parse(data)
	-- Reverse source/destination terminology
	local destAddress, destPort, sourcePort = sourceAddress, segment.sourcePort, segment.destPort
	-- Incoming connection (SYN w/o ACK)
	if segment:hasFlag(FLAG.SYN) and not segment:hasFlag(FLAG.ACK) then
		-- Find listen handler
		local listenHandler = self:getListenHandler(sourcePort)
		if listenHandler ~= nil and not self:hasConnection(destAddress, destPort, sourcePort) then
			-- Listening, establish active connection
			local conn = self:createConnection(destAddress, destPort, sourcePort)
			-- Call handler
			listenHandler(conn)
		else
			-- Not listening or already connected, ignore
			return
		end
	end
	-- Get receiving connection
	local conn = self:getConnection(destAddress, destPort, sourcePort)
	if conn ~= nil then
		conn:onReceive(segment)
	end
end

-- Exports
return TCP