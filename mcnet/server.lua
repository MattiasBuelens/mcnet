--[[

	MCNet
	Server

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local transport	= require "mcnet.Transport"
local loop		= EventLoop:new()
local connections = {}

-- Server
transport:listen("tcp", 80, function(conn)
	print("Connecting to client...")
	connections[conn] = true
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
		connections[conn] = nil
	end)
end)
print("Waiting for connection...")

-- Ctrl to quit
loop:on("key", function(key)
	if key == keys.leftCtrl or key == rightCtrl then
		-- Close and stop
		transport:stopListening("tcp", 80)
		for conn,_ in pairs(connections) do
			conn:close()
		end
		loop:stop()
		print("Stopped")
	end
end)
print("Press Ctrl to quit")

-- Run
loop:run()