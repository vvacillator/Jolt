--!strict
local Server = {}
Server.__index = Server

local Players = game:GetService("Players")

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

local PACKET_EVENT = 1
local PACKET_REQUEST = 2
local PACKET_RESPONSE = 3

local ActiveInstances = setmetatable({}, {__mode = "k"})

task.spawn(function()
	while task.wait(0.025) do
		for inst in pairs(ActiveInstances) do
			inst:_flush()
		end
	end
end)

export type Config = {
	Unreliable: boolean?,
}

function Server.new(name: string, config: Config?)
	local self = setmetatable({}, Server)

	self._remote = Remotes.Create(name, config and config.Unreliable)
	self._outgoing = {} :: {[Player]: Buffers.Writer}
	self._broadcast = nil :: Buffers.Writer?
	self._listeners = {} :: { (Player, any) -> () }

	self.OnInvoke = nil :: ((Player, any) -> any)?

	Players.PlayerRemoving:Connect(function(player)
		if self._outgoing[player] then
			Buffers.FreeWriter(self._outgoing[player])
			self._outgoing[player] = nil
		end
	end)

	self._remote.OnServerEvent:Connect(function(player, buff, insts)
		self:_incoming(player, buff, insts)
	end)

	ActiveInstances[self] = true

	return self
end

function Server:Connect(callback: (Player, any) -> ())
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

function Server:Fire(player: Player, val: any)
	local w = self._outgoing[player]

	if not w then
		w = Buffers.CreateWriter()
		self._outgoing[player] = w
	end

	Buffers.WriteByte(w, PACKET_EVENT)
	Buffers.WriteAny(w, val)
end

function Server:FireAll(val: any)
	local w = self._broadcast

	if not w then
		w = Buffers.CreateWriter()
		self._broadcast = w
	end

	Buffers.WriteByte(w, PACKET_EVENT)
	Buffers.WriteAny(w, val)
end

function Server:_flush()
	for p, w in pairs(self._outgoing) do
		local b, i = Buffers.Finalize(w)
		self._remote:FireClient(p, b, i)
		Buffers.FreeWriter(w)
	end

	table.clear(self._outgoing)

	if self._broadcast then
		local b, i = Buffers.Finalize(self._broadcast)
		self._remote:FireAllClients(b, i)
		Buffers.FreeWriter(self._broadcast)
		self._broadcast = nil
	end
end

function Server:_incoming(player: Player, b: buffer, i: {Instance})
	local r = Buffers.CreateReader(b, i)

	while r.cursor < r.len do
		local type = Buffers.ReadByte(r)

		if type == PACKET_EVENT then
			local val = Buffers.ReadAny(r)
			local listeners = table.clone(self._listeners)

			for _, cb in ipairs(listeners) do
				task.spawn(cb, player, val)
			end
		elseif type == PACKET_REQUEST then
			local id = Buffers.ReadVarInt(r)
			local val = Buffers.ReadAny(r)

			if self.OnInvoke then
				task.spawn(function()
					local ok, res = pcall(self.OnInvoke, player, val)
					local w = self._outgoing[player]

					if not w then
						w = Buffers.CreateWriter()
						self._outgoing[player] = w
					end

					Buffers.WriteByte(w, PACKET_RESPONSE)
					Buffers.WriteVarInt(w, id)
					Buffers.WriteByte(w, ok and 1 or 0)
					Buffers.WriteAny(w, res)
				end)
			end
		else
			break
		end
	end

	Buffers.FreeReader(r)
end

return Server
