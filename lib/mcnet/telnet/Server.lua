--[[

	MCNet
	Telnet server

]]--

local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"

-- Constants
local TELNET_PORT	= 23

local RemoteTerminal = EventEmitter:subclass("mcnet.telnet.RemoteTerminal")
function RemoteTerminal:initialize(server, width, height, isColor)
	super.initialize(self)
	-- Owner server
	self.server = server
	-- Sanitize input
	local ownWidth, ownHeight = term.getSize()
	width = tonumber(width) or ownWidth
	height = tonumber(height) or ownHeight
	isColor = not not isColor
	-- Redirect setters
	for functionName,v in pairs(term.native) do
		self[functionName] = function(...)
			-- Run in local terminal
			term.native[functionName](...)
			-- Run on remote client
			self:sendCommand(functionName, ...)
		end
	end
	-- Override getters
	self.getSize = function()
		return width, height
	end
	self.isColor = function()
		return isColor
	end
end
function RemoteTerminal:sendCommand(functionName, ...)
	-- Send terminal message
	self.server:send({
		command	= "terminal"
		fn		= functionName
		params	= arg
	})
end

local Server = EventEmitter:subclass("mcnet.telnet.Server")
function Server:initialize(transport, serverPort)
	super.initialize(self)
	self.transport = transport
	self.serverPort = tonumber(serverPort) or TELNET_PORT
	self.remoteTerminal = nil
	self.isRedirecting = false
end
function Server:start()
	-- Start listening
	self.transport:listen("tcp", self.serverPort, function(conn)
		self:onConnect(conn)
	end)
end
function Server:stop()
	-- Close
	self:close()
	-- Stop listening
	self.transport:stopListening("tcp", self.serverPort)
end
function Server:onConnect(conn)
	if self.conn ~= nil and self.conn:isOpen()
		-- Reject new connection
		conn:close()
	end
	-- Store client connection
	self.conn = conn
	-- Register event handlers
	self.conn:on("receive", self.onReceive, self)
	self.conn:on("closing", self.onClose, self)
	self.conn:on("close", self.onClose, self)
end
function Server:close()
	-- Close terminal
	self.remoteTerminal = nil
	if self.isRedirecting then
		term.restore()
	end
	if self.conn ~= nil then
		-- Unregister event handlers
		self.conn:off("receive", self.onReceive, self)
		self.conn:off("closing", self.onClose, self)
		self.conn:off("close", self.onClose, self)
		-- Close connection
		self.conn:close()
		self.conn = nil
	end
end
function Server:onSetup(setupData)
	-- Create remote terminal
	self.remoteTerminal = RemoteTerminal:new(self, setupData.width, setupData.height, setupData.isColor)
	-- Redirect terminal
	term.redirect(self.remoteTerminal)
end
function Server:onClose()
	self:close()
end
function Server:send(message)
	if self.conn:isOpen() then
		self.conn:send(textutils.serialize(message))
	end
end
function Server:onReceive(data)
	-- Unpack message
	local message = textutils.unserialize(data)
	if message.command == "event" then
		-- Queue event
		os.queueEvent(unpack(message.data))
	elseif message.command == "setup" then
		-- Start remote terminal
		self:onSetup(message.data)
	end
end

return Server