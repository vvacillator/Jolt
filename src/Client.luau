--!strict
local Client = {}
Client.__index = Client

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

local tableunpack = table.unpack

local PACKET_EVENT = 1
local PACKET_REQUEST = 2
local PACKET_RESPONSE = 3
local REQUEST_TIMEOUT = 60

local ActiveInstances = setmetatable({}, {__mode = "k"})

task.spawn(function()
	while task.wait(0.025) do
		for inst in pairs(ActiveInstances) do
			inst:_flush()
		end
	end
end)

function Client.new(name: string)
	local self = setmetatable({}, Client)

	self._remote = Remotes.Get(name)
	self._outgoing = nil :: Buffers.Writer?
	self._requests = {} :: {[number]: thread}
	self._listeners = {} :: {[(...any) -> ()]: true}
	self._reqId = 0

	self._remote.OnClientEvent:Connect(function(buff, insts)
		self:_incoming(buff, insts)
	end)

	return self
end

function Client:Connect(callback: (...any) -> ())
	self._listeners[callback] = true

	return {
		Disconnect = function()
			self._listeners[callback] = nil
		end,
	}
end

function Client:Fire(...: any)
	local w = self._outgoing

	if not w then
		w = Buffers.CreateWriter()
		self._outgoing = w
		ActiveInstances[self] = true
	end

	Buffers.WriteByte(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Client:Invoke(...: any)
	local id = self._reqId
	self._reqId += 1

	local w = self._outgoing

	if not w then
		w = Buffers.CreateWriter()
		self._outgoing = w
		ActiveInstances[self] = true
	end

	Buffers.WriteByte(w, PACKET_REQUEST)
	Buffers.WriteVarInt(w, id)
	Buffers.Pack(w, ...)

	local thread = coroutine.running()
	self._requests[id] = thread

	task.delay(REQUEST_TIMEOUT, function()
		if self._requests[id] == thread then
			self._requests[id] = nil
			task.spawn(thread, false, "Request timed out")
		end
	end)

	local success, result = coroutine.yield()

	if not success then
		error(result)
	end

	return result
end

function Client:_flush()
	local w = self._outgoing
	if w then
		local b, i = Buffers.Finalize(w)
		self._remote:FireServer(b, i)

		Buffers.FreeWriter(w)
		self._outgoing = nil
		ActiveInstances[self] = nil
	end
end

function Client:_incoming(b: buffer, i: {Instance})
	local r = Buffers.CreateReader(b, i)

	while r.cursor < r.len do
		local type = Buffers.ReadByte(r)

		if type == PACKET_EVENT then
			local vals = Buffers.Unpack(r)

			for cb in pairs(self._listeners) do
				task.spawn(cb, tableunpack(vals))
			end
		elseif type == PACKET_RESPONSE then
			local id = Buffers.ReadVarInt(r)
			local ok = Buffers.ReadByte(r) == 1
			local vals = Buffers.Unpack(r)
			local thread = self._requests[id]

			if thread then
				self._requests[id] = nil
				task.spawn(thread, ok, tableunpack(vals))
			end
		else
			break
		end
	end
	Buffers.FreeReader(r)
end

return Client
