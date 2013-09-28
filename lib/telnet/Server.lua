--[[

	MCNet Telnet
	Server

]]--

local Object		= require "objectlua.Object"
local EventEmitter	= require "event.EventEmitter"
local EventLoop		= require "event.EventLoop"
local Command		= require "telnet.Command"

-- Constants
local TELNET_PORT	= 23

local RemoteTerminal = Object:subclass("telnet.RemoteTerminal")
function RemoteTerminal:initialize(server, width, height, isColor)
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
	self.getCursorPos = function()
		return term.native.getCursorPos()
	end
	self.getSize = function()
		return width, height
	end
	self.isColor = function()
		return isColor
	end
	self.isColour = self.isColor
end
function RemoteTerminal:sendCommand(...)
	-- Send terminal command
	self.server:send(Command:new("terminal", { ... }))
end

local Server = EventEmitter:subclass("telnet.Server")
function Server:initialize(transport, serverPort)
	super.initialize(self)
	self.transport = transport
	self.serverPort = tonumber(serverPort) or TELNET_PORT
end
function Server:start()
	-- Start listening
	self.transport:listen("tcp", self.serverPort, function(conn)
		self:onConnect(conn)
	end)
	self:trigger("start")
end
function Server:stop()
	-- Close
	self:close()
	-- Stop listening
	self.transport:stopListening("tcp", self.serverPort)
	self:trigger("stop")
end
function Server:isConnected()
	return self.conn ~= nil and self.conn:isOpen()
end
function Server:onConnect(conn)
	if self:isConnected() then
		-- Reject new connection
		conn:close()
		return
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
	if self.conn ~= nil then
		-- Unregister event handlers
		self.conn:off("receive", self.onReceive, self)
		self.conn:off("closing", self.onClose, self)
		self.conn:off("close", self.onClose, self)
		-- Close connection
		self.conn:close()
		self.conn = nil
		self:trigger("close")
	end
end
function Server:onSetup(setupData)
	-- Ready
	self:trigger("open")
	-- Redirect terminal
	local remoteTerminal = RemoteTerminal:new(self, setupData.width, setupData.height, setupData.isColor)
	term.redirect(remoteTerminal)
	self:clearTerminal()
	-- Start session
	local ok, err = pcall(function()
		parallel.waitForAny(
			function()
				-- Run session
				self:runSession()
			end,
			function()
				-- Keep processing events
				while self:isConnected() and EventLoop:isRunning() do
					EventLoop:process()
				end
				-- Force close session
				self:closeSession()
			end)
	end)
	-- Restore terminal
	term.restore()
	self:clearTerminal()
	-- Close session
	self:close()
	-- Print errors
	if not ok then
		printError(err)
	end
end
function Server:runSession()
	self:trigger("session")
	-- Run a non-root shell
	local parentShell = _G.shell
	-- If no root shell available, use a dummy root shell
	_G.shell = parentShell or require("telnet.DummyShell")
	os.run({}, "rom/programs/shell")
	-- Restore
	_G.shell = parentShell
end
function Server:closeSession()
	-- Close created shell
	if _G.shell then
		_G.shell.exit()
	end
end
function Server:clearTerminal()
	term.clear()
	term.setCursorPos(1, 1)
end
function Server:onClose()
	self:close()
end
function Server:send(command)
	if self:isConnected() then
		self.conn:send(Command:serialize(command))
	end
end
function Server:onReceive(data)
	-- Unpack message
	local message = Command:parse(data)
	if message.command == "event" then
		-- Queue event
		os.queueEvent(unpack(message.data))
	elseif message.command == "setup" then
		-- Start remote terminal
		self:onSetup(message.data)
	end
end

return Server