--[[

	MCNet
	Router

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Network	= require "mcnet.Network"
local network	= Network:new()

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == keys.rightCtrl then
		network:close()
		EventLoop:stop()
	end
end)
print("Press Ctrl to quit")

-- Debug
network:on("open", function()
	print("Router started on address "..network.address)
end)
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
network:open()
EventLoop:run()