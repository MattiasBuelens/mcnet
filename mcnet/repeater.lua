--[[

	MCNet
	Repeater

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Network	= require "mcnet.Network"

-- Debug
Network:on("open", function()
	print("Repeater started on address "..Network.address)
end)
Network:on("close", function()
	print("Repeater stopped")
end)
Network:on("route", function(packet, peer)
	print("Packet routed to "..peer)
	print("  src: "..packet.sourceAddress..", dst: "..packet.destAddress)
	print("  data: "..packet.data)
end)
Network:on("drop", function(packet, reason)
	print("Packet dropped because of "..reason)
	print("  src: "..packet.sourceAddress..", dst: "..packet.destAddress)
	print("  data: "..packet.data)
end)

-- Setup
Network:open()

-- Run
EventLoop:run()