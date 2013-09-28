--[[

	MCNet
	Client

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
local Transport	= require "mcnet.Transport"
local transport	= Transport:new()

-- Read server address
local serverAddress = nil
repeat
	write("Server address: ")
	serverAddress = read()
until tonumber(serverAddress) ~= nil

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

-- Client
transport:open()
local conn = transport:connect("tcp", tonumber(serverAddress), 80)
conn:on("open", function()
	print("Connected")
	print("Type a message and press Enter to send")
	local message = ""
	EventLoop:on("char", function(char)
		if not conn:isOpen() then return end
		message = message .. char
		write(char)
	end)
	EventLoop:on("key", function(key)
		if not conn:isOpen() then return end
		if key == keys.enter or key == numPadEnter then
			local sendMessage = message
			message = ""
			print()
			print("Sending '"..sendMessage.."'...")
			conn:send(sendMessage, function()
				print("  Message '"..sendMessage.."' delivered")
			end)
		end
	end)
	conn:on("receive", function(data)
		print("Received reply: '"..data.."'")
	end)
end)
conn:on("closing", function()
	print("Closing connection...")
end)
conn:on("close", function()
	print("Connection closed")
end)
print("Connecting...")

-- Run
EventLoop:run()