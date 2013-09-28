--[[

	Dummy shell
	Parent shell with defaults from rom/startup

]]--

local shell = {}
shell.dir = function()
	return ""
end
shell.path = function()
	local sPath = ".:/rom/programs"
	if turtle then
		sPath = sPath..":/rom/programs/turtle"
	else
		sPath = sPath..":/rom/programs/computer"
	end
	if http then
		sPath = sPath..":/rom/programs/http"
	end
	if term.isColor() then
		sPath = sPath..":/rom/programs/color"
	end
	return sPath
end
shell.aliases = function()
	return {
		ls		= "list",
		dir		= "dir",
		cp		= "copy",
		mv		= "move",
		rm		= "delete",
		preview	= "edit"
	}
end
return shell