--[[

	MCNet
	Telnet server

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Server	= require "mcnet.telnet.Server"
local Transport	= require "mcnet.Transport"
local transport	= Transport:new()

-- Close and stop
local function stop()
	transport:close()
	EventLoop:stop()
	print("Stopped")
end

-- Server
transport:open()
local server = Server:new(transport)
server:on("open", function()
	print("Connected")
end)
server:on("close", function()
	print("Connection closed")
end)
server:on("stop", function()
	print("Server stopped")
	stop()
end)
server:on("session", function()
	print("Telnet running on #"..os.getComputerID())
	print("Enter exit to disconnect")
end)
print("Waiting for connection...")

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == keys.rightCtrl then
		-- Ignore Ctrl while connected
		if not server:isConnected() then
			server:stop()
		end
	end
end)
print("Press Ctrl to quit")

-- Run
server:start()
EventLoop:run()