--[[

	MCNet
	Client

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Network	= require "mcnet.Network"
local network	= Network:new()

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == rightCtrl then
		-- Close and stop
		print("key:"..key)
		network:close()
		EventLoop:stop()
	end
end)
print("Press Ctrl to quit")

-- Ping client
network:on("receive", function(senderAddress, data)
	if data == "PING" then
		print("Received ping from "..senderAddress)
	end
end)
local pingAddress = ""
EventLoop:on("char", function(char)
	if tonumber(char) ~= nil then
		pingAddress = pingAddress .. char
		write(char)
	end
end)
EventLoop:on("key", function(key)
	if key == keys.enter or key == numPadEnter then
		print()
		print("Sent ping to "..pingAddress)
		network:send(pingAddress, 5, "PING")
		pingAddress = ""
	end
end)
print("Type an address and press Enter to ping")

-- Run
network:open()
EventLoop:run()