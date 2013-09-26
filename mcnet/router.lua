--[[

	MCNet
	Router

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local network	= require "mcnet.Network"

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == rightCtrl then
		network:close()
		EventLoop:stop()
	end
end)
print("Press Ctrl to quit")

-- Debug
print("Router started on address "..network.address)
network:on("close", function()
	print("Router stopped")
end)
network:on("route", function(packet, peer)
	print("Packet routed to "..peer)
	print("  src: "..packet.sourceAddress..", dst: "..packet.destAddress)
	print("  data: "..packet.data)
end)
network:on("drop", function(packet, reason)
	print("Packet dropped because of "..reason)
	print("  src: "..packet.sourceAddress..", dst: "..packet.destAddress)
	print("  data: "..packet.data)
end)

-- Run
EventLoop:run()