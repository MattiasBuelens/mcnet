--[[

	MCNet
	Network ping test

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local LocalEventLoop	= require "event.LocalEventLoop"
local network			= require "mcnet.Network"

-- Ctrl to quit
LocalEventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == rightCtrl then
		-- Close and stop
		network:close()
		LocalEventLoop:stop()
		print("Stopped")
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
LocalEventLoop:on("char", function(char)
	if tonumber(char) ~= nil then
		pingAddress = pingAddress .. char
		write(char)
	end
end)
LocalEventLoop:on("key", function(key)
	if key == keys.enter or key == numPadEnter then
		print()
		print("Sent ping to "..pingAddress)
		network:send(pingAddress, "PING")
		pingAddress = ""
	end
end)
print("Type an address and press Enter to ping")

-- Run
LocalEventLoop:run()