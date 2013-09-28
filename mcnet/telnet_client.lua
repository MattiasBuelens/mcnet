--[[

	MCNet
	Telnet client

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Client	= require "mcnet.telnet.Client"
local Transport	= require "mcnet.Transport"
local transport	= Transport:new()

-- Read server address
local serverAddress = nil
repeat
	write("Server address: ")
	serverAddress = read()
until tonumber(serverAddress) ~= nil

-- Close and stop
local function stop()
	transport:close()
	EventLoop:stop()
	print("Stopped")
end

-- Client
transport:open()
local client = Client:new(transport, tonumber(serverAddress))
client:on("open", function()
	print("Connected, waiting for server...")
end)
client:on("close", function()
	-- Newline keeps last line visible
	print()
	print("Connection closed")
	stop()
end)
print("Connecting...")

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == keys.rightCtrl then
		-- Ignore Ctrl while connected
		if not client:isConnected() then
			client:close()
		end
	end
end)
print("Press Ctrl to quit")

-- Run
client:open()
EventLoop:run()