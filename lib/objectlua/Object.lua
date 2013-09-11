local objectlua = require 'objectlua.bootstrap'
local Object = objectlua.Object

local _G = _G

function Object.initialize(self)
end

function Object.isKindOf(self, class)
   return self.class == class or self.class:inheritsFrom(class)
end

function Object.clone(self, object)
    local clone = self.class:basicNew()
    for k, v in _G.pairs(self) do
        clone[k] = v
    end
    return clone
end

function Object.className(self)
    return self.class:name()
end

function Object.subclassResponsibility(self)
    _G.error("Error: subclass responsibility.")
end

return Object