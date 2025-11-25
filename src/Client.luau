--!strict
local Client = {}
Client.__index = Client

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

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
	self._listeners = {} :: { (any) -> () }
	self._reqId = 0

	self._remote.OnClientEvent:Connect(function(buff, insts)
		self:_incoming(buff, insts)
	end)

	ActiveInstances[self] = true

	return self
end

function Client:Connect(callback: (any) -> ())
	table.insert(self._listeners, callback)

	return {
		Disconnect = function()
			local idx = table.find(self._listeners, callback)

			if idx then 
				table.remove(self._listeners, idx) 
			end
		end
	}
end

function Client:Fire(val: any)
	local w = self._outgoing

	if not w then
		w = Buffers.CreateWriter()
		self._outgoing = w
	end

	Buffers.WriteByte(w, PACKET_EVENT)
	Buffers.WriteAny(w, val)
end

function Client:Invoke(val: any)
	local id = self._reqId
	self._reqId += 1

	local w = self._outgoing

	if not w then
		w = Buffers.CreateWriter()
		self._outgoing = w
	end

	Buffers.WriteByte(w, PACKET_REQUEST)
	Buffers.WriteVarInt(w, id)
	Buffers.WriteAny(w, val)

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
	if self._outgoing then
		local b, i = Buffers.Finalize(self._outgoing)
		self._remote:FireServer(b, i)

		Buffers.FreeWriter(self._outgoing)
		self._outgoing = nil
	end
end

function Client:_incoming(b: buffer, i: {Instance})
	local r = Buffers.CreateReader(b, i)

	while r.cursor < r.len do
		local type = Buffers.ReadByte(r)

		if type == PACKET_EVENT then
			local val = Buffers.ReadAny(r)
			local listeners = table.clone(self._listeners)

			for _, cb in ipairs(listeners) do
				task.spawn(cb, val)
			end
		elseif type == PACKET_RESPONSE then
			local id = Buffers.ReadVarInt(r)
			local ok = Buffers.ReadByte(r) == 1
			local val = Buffers.ReadAny(r)
			local thread = self._requests[id]

			if thread then
				self._requests[id] = nil
				task.spawn(thread, ok, val)
			end
		else
			break
		end
	end
	Buffers.FreeReader(r)
end

return Client
