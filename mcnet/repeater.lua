--[[

	Repeater strategy
	- Receive *network* message
	- Check TTL, discard if (below) zero
	- Re-send through all other ports

]]--

local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat-5.1.lua"))
package.root = lib

local EventLoop	= require "event.EventLoop"
-- TODO Switch from link to network layer
local Link		= require "mcnet.link"

-- Setup
Link:open()

-- Run
EventLoop:run()