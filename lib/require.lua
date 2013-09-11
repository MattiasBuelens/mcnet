--[[

	Require implementation in pure Lua

	Original from https://github.com/CoolisTheName007/loadreq
	Licensed under the MIT license

]]--

local fs=fs
local string=string
local loadfile=loadfile
local error=error

local log,search

local function getNameExpansion(s) --returns name and expansion from a filepath @s; special cases: ''->'',nil; '.'-> '','';
	local _,_,name,expa=string.find(s, '([^%./\\]*)%.(.*)$')
	return name or s,expa
end

local function getDir(s) --returns directory from filepath @s
	return string.match(s,'^(.*)/') or '/'
end

vars={} --to allow edition
vars.loaded={}

---iterator; replaces '?' in g by s and returns the resulting path if it is a file.
local function direct(g,s)
	g=string.gsub(g,'%?',s)
	if fs.exists(g) and not fs.isDir(g) then
		return g
	end
end
--add your finders here: must take (p,s) where p is where to search and s is what to search for.It must return a path.
vars.finders={direct}
vars.paths='?;?.lua;?/init.lua;lib/?;lib/?.lua;lib/?/init.lua;/'

--helper vars for lua_requirer; other requirers may index theirs vars in loadreq.vars
vars.lua_requirer={
required={}, --to unrequire filepath s do require[s]=nil
required_envs={}, --to prevent garbage collection
requiring={}, --to throw error in case of recursive requiring;
}

--[[lua_requirer(path,cenv,env,renv,rerun,args)
Accepts empty or .lua extensions. 
if the rerun flag is true, reloads the file even if it done it before;
if the file has been loaded already returns previous value;
if the file is being loaded returns nil, error_message
else:
loads file in @path;
sets it's env to @env, default {} with metatable with __index set to @renv, default _G;
calls the function with unpack(@args) and returns and saves either
	the function return
	a shallow copy of the functions environment
]]

local function lua_requirer(path,cenv,env,renv,rerun,args)
	local err_prefix='lua_requirer:'
	local vars=vars.lua_requirer
	local _,ext=getNameExpansion(path)
	if not (ext=='' or ext=='lua' or ext==nil) then
		return nil, err_prefix..'wrong extension:'..ext
	end
	
	if vars.requiring[path] then
		return nil, err_prefix..'file is being loaded'
	end
	if not rerun and vars.required[path] then
		return vars.required[path]
	end
	
	local f,e=loadfile(path,path)
	if not f then
		return nil,err_prefix..'loadfile:'..e
	end
	env=env or {}
	env.require = require
	env.include = include
	env.FILE_PATH=path
	vars.required_envs[path]=env
	setfenv(f,env)
	renv=renv or _G
	setmetatable(env,{__index=renv})
	vars.requiring[path]=true
	local r=f(args and unpack(args)) --raises useful error/traceback, no need to tamper with
	vars.requiring[path]=nil
	if r then
		vars.required[path]=r
		return r
	else
		local t={}
		for i,v in pairs(env) do t[i]=v end
		vars.required[path]=t
		return t
	end
end

--[[add your requirers here;
each must 
take as arguments (path,cenv,...) where
	path is the path to required file
	cenv is the environment of the caller of @require
	... are extra arguments passed to @require
return
	one value to be returned by @require
	false|nil, error_message in case of failure
]]
vars.requirers={lua=lua_requirer}

local function suffix(s)
	return string.gsub('@/?;@/?.lua;@/?/init.lua;@/?/?.lua;@/?/?;@','@',s)
end

local function _find(s,paths,caller_env)
	local err={'_find: finding '..tostring(s)}
	
	if paths then
	elseif caller_env.REQUIRE_PATH then
		paths=caller_env.REQUIRE_PATH
	elseif caller_env.PACKAGE_NAME and caller_env.FILE_PATH then
		paths=suffix(string.match(caller_env.FILE_PATH,'^(.-'..caller_env.PACKAGE_NAME..')'))..';'..vars.paths
	elseif	caller_env.FILE_PATH then
		paths=suffix(getDir(caller_env.FILE_PATH))..';'..vars.paths
	else
		paths=vars.paths
	end
	
	--replace . by / and .. by . 
	s=string.gsub(s,'([^%.])%.([^%.])','%1/%2') 
	s=string.gsub(s,'^%.([^%.])','/%1')
	s=string.gsub(s,'%.%.','.')
	
	local finders=vars.finders
	
	local finder,path
	for i=1,#finders do
		finder=finders[i]
		for search_path in string.gmatch(paths,';?([^;]+);?') do
			path=finder(search_path,s)
			if path then return path end
		end
	end
	table.insert(err,'_find:file not found:'..s..'\ncaller path='..(caller_env.FILE_PATH or 'not available'))
	local serr=table.concat(err,'\n')
	if log then log('loadreq','ERROR','_find:%s',serr) end
	return nil,serr
end
find=_find

local function _require(s,paths,caller_env,...)
	local err={}
	table.insert(err,'loadreq:require: while requiring '..tostring(s))
	local path,e=_find(s,paths,caller_env)
	if path==nil then
		table.insert(err,e)
		return nil, table.concat(err,'\n')
	end
	for req_name,requirer in pairs(vars.requirers) do
		local r,e=requirer(path,caller_env,...)
		if r then
			return r
		else
			table.insert(err,e)
		end
	end
	return nil, table.concat(err,'\n')
end

--[[require(s,paths,...)
@paths is a string of paths separated by ';' where there can be '?'
-acquires @paths variable, by the following order;
	0-arg @paths
		Example (FILE_PATH='myFolder/myFolder2/myAPI.lua'):
		myAPI=require('myFolder2.myAPI','myFolder/?.lua') 
	1-REQUIRE_PATH in the caller's path, if existent
		Example (FILE_PATH='myFolder/myFolder2/myAPI.lua'):
		REQUIRE_PATH='myFolder/?.lua'
		myAPI=require'myFolder2.myAPI' 
	2-directory named PACKAGE_NAME in FILE_PATH, if defined in the caller's environment
	with sufixes appended by @sufix and concatenated with @vars.paths.
	FILE_PATH is set, for instance, by lua_loader in the files it loads.
		Example (FILE_PATH='myFolder/myFolder3/myFolder/runningFile'):
		PACKAGE_NAME='myFolder'
		myAPI=require'myAPI' --@paths is 'myFolder/?;myFolder/?.lua;myFolder/?/init.lua;myFolder/?/?.lua;myFolder/?/?;myFolder'
	3-directory of FILE_PATH, if defined
	with sufixes appended by @sufix and concatenated with @vars.paths.
		Example (FILE_PATH='myFolder/runningFile'):
		myAPI=require'myAPI' --@paths is 'myFolder/?;myFolder/?.lua;myFolder/?/init.lua;myFolder/?/?.lua;myFolder/?/?;myFolder'
	4-@vars.paths as set in loadreq.vars.paths
-replaces '.' in @s by '/' and '..' by '.'
--for all search_path in @paths
 -	for all iterators in vars.finders, iterates over the paths returned;
	default iterator:	see @direct
-for the first valid path, calls the loaders sequentially until one succeds, 
in which case it returns the first value that the loader returns, else if it returns nil,e accumulates e as an error message
els, if all loaders fail, errors immediatly, printing all error messages
-in case of failure finding the path, errors with useful info
]]

function require(s,paths,...)
	local t,e=_require(s,paths,getfenv(2),...)
	if t==nil then
		if log then log('loadreq','ERROR','require:%s',e) end
		error(e,2)
	else
		if log then log('loadreq','INFO','require: success in requiring %s',s) end
		return t
	end
end

---same as require, but copies the returned API to the caller's environment
function include(s,paths,...)
	local caller_env=getfenv(2)
	local t,e=_require(s,paths,caller_env,...)
	if t then
		for i,v in pairs(t) do
			caller_env[i]=v
		end
		return true
	else
		if log then log('loadreq','ERROR','include:%s',e) end
		error(e,2)
	end
end