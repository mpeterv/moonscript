
module("moonscript.compile", package.seeall)
require "util"

local data = require "moonscript.data"

-- this doesn't work
-- setmetatable(_M, {
-- 	__call = setfenv(function(self, ...)
-- 		compile(...)
-- 	end, _G)
-- })

local map, bind = util.map, util.bind
local Stack = data.Stack

local indent_char = "  "

function ntype(node)
	if type(node) ~= "table" then return "value" end
	return node[1]
end

local compilers = {
	_indent = 0,
	_scope = Stack({}),

	push = function(self) self._scope:push{} end,
	pop = function(self) self._scope:pop() end,

	has_name = function(self, name)
		for i = #self._scope,1,-1 do
			if self._scope[i][name] then return true end
		end
		return false
	end,

	put_name = function(self, name)
		self._scope:top()[name] = true
	end,

	ichar = function(self)
		return indent_char:rep(self._indent)
	end,

	chain = function(self, node)
		local callee = node[2]
		local actions = {}
		for i = 3,#node do
			local t, arg = unpack(node[i])
			if t == "call" then
				table.insert(actions, "("..table.concat(self:values(arg), ', ')..")")
			elseif t == "index" then
				table.insert(actions, "["..self:value(arg).."]")
			else
				error("Unknown chain action: "..t)
			end
		end

		local callee_value = self:value(callee)
		if ntype(callee) == "exp" then
			callee_value = "("..callee_value..")"
		end

		return callee_value..table.concat(actions)
	end,

	fndef = function(self, node)
		local _, args, block = unpack(node)
		self:push()

		for _, arg_name in ipairs(args) do
			self:put_name(arg_name)
		end

		args = table.concat(args, ",")

		local out
		if #block == 0 then
			out = ("function(%s) end"):format(args)
		elseif #block == 1 then
			out = ("function(%s) %s end"):format(args, self:value(block[1]))
		else
			out = ("function(%s)\n%s\n%send"):format(
				args, self:block(block, 1), self:ichar())
		end

		self:pop()
		return out
	end,

	["if"] = function(self, node)
		local _, cond, block = unpack(node)
		return ("if %s then\n%s\n%send"):format(
			self:value(cond), self:block(block, 1), self:ichar())
	end,

	block = function(self, node, inc)
		self:push()
		if inc then self._indent = self._indent + inc end
		local lines = {}
		local i = self:ichar()
		for _, ln in ipairs(node) do
			table.insert(lines, i..self:value(ln))
		end
		if inc then self._indent = self._indent - inc end
		self:pop()
		return table.concat(lines, "\n")
	end,

	assign = function(self, node)
		local _, names, values = unpack(node)
		local assigns, current = {}, nil

		local function append(t, name, value)
			if not current or t ~= current[1] then
				current = {t, {name}, {value}}
				table.insert(assigns, current)
			else
				table.insert(current[2], name)
				table.insert(current[3], value)
			end
		end

		for i, assignee in ipairs(names) do
			local name_value = self:value(assignee)
			local value = self:value(values[i])

			if ntype(assignee) == "chain" or self:has_name(assignee) then
				append("non-local", name_value, value)
			else
				append("local", name_value, value)
			end

			if type(assignee) == "string" then
				self:put_name(assignee)
			end
		end

		local lines = {}
		for _, group in ipairs(assigns) do
			local t, names, values = unpack(group)
			if #values == 0 then values = {"nil"} end
			local line = table.concat(names, ", ").." = "..table.concat(values, ", ")
			table.insert(lines, t == "local" and "local "..line or line)
		end
		return table.concat(lines, "\n"..self:ichar())
	end,

	exp = function(self, node)
		local values = {}
		for i = 2, #node do
			table.insert(values, self:value(node[i]))
		end
		return table.concat(values, " ")
	end,

	string = function(self, node)
		local _, delim, inner, delim_end = unpack(node)
		return delim..inner..(delim_end or delim)
	end,

	value = function(self, node)
		if type(node) == "table" then 
			return self[node[1]](self, node)
		end

		return node
	end,

	-- a list of values
	values = function(self, items, start)
		start = start or 1
		local compiled = {}
		for i = start,#items do
			table.insert(compiled, self:value(items[i]))
		end
		return compiled
	end
}

_M.tree = function(tree)
	local buff = {}
	for _, line in ipairs(tree) do
		local op = type(line) == "table" and line[1] or "value"
		local fn = compilers[op]
		if not fn then error("Unknown op: "..tostring(op)) end
		table.insert(buff, compilers[op](compilers, line))
	end

	return table.concat(buff, "\n")
end


