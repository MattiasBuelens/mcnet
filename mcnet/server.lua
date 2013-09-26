--[[

	MCNet
	Server

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local transport	= require "mcnet.Transport"
local conns = {}

-- Server
local conn = transport:listen("tcp", 80, function(conn)
	print("Connecting to client...")
	conns[conn] = true
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

-- Ctrl to quit
EventLoop:on("key", function(key)
	if key == keys.leftCtrl or key == rightCtrl then
		-- Close and stop
		for conn,_ in pairs(conns) do
			conn:close()
		end
		transport:stopListening("tcp", 80)
		EventLoop:stop()
		print("Stopped")
	end
end)
print("Press Ctrl to quit")

-- Run
print("Waiting for connection...")
EventLoop:run()