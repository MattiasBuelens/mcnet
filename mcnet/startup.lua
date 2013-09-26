--[[

	MCNet
	Startup

]]--

-- Require
local lib = fs.combine(shell.getRunningProgram(), "/../../lib/")
dofile(fs.combine(lib, "/compat.lua"))
package.root = lib

-- Setup
local transport = require("mcnet.Transport")

-- Run event loop and shell
local loop = require("event.EventLoop")
local ok, err = pcall(function()
	parallel.waitForAny(
		function()
			os.run({}, "rom/programs/shell")
		end,
		function()
			loop:run()
		end)
end)
if not ok then
	printError( err )
end

-- Teardown
transport:close()
loop:stop()