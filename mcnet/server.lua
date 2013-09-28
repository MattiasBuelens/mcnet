--[[

	MCNet
	Server

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Transport	= require "mcnet.Transport"
local transport	= Transport:new()

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == keys.rightCtrl then
		-- Close and stop
		transport:close()
		EventLoop:stop()
		print("Stopped")
	end
end)
print("Press Ctrl to quit")

-- Server
transport:open()
local conn = transport:listen("tcp", 80, function(conn)
	print("Connecting to client...")
	conn:on("open", function()
		print("Connected")
	end)
	conn:on("receive", function(data)
		-- Reply with reversed message
		local reply = string.reverse(data)
		print("Received: '"..data.."', replying with: '"..reply.."'")
		conn:send(reply)
	end)
	conn:on("closing", function()
		print("Closing connection...")
	end)
	conn:on("close", function()
		print("Connection closed")
	end)
end)
print("Waiting for connection...")

-- Run
EventLoop:run()