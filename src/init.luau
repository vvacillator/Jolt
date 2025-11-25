--!strict
local Jolt = {}

local RunService = game:GetService("RunService")

local Client = require("@self/Client")
local Server = require("@self/Server")

export type Config = Server.Config

export type Server = {
	Fire: (self: Server, player: Player, val: any) -> (),
	FireAll: (self: Server, val: any) -> (),
	Connect: (self: Server, callback: (player: Player, val: any) -> ()) -> { Disconnect: () -> () },
	OnInvoke: ((player: Player, val: any) -> any)?,
}

export type Client = {
	Fire: (self: Client, val: any) -> (),
	Invoke: (self: Client, val: any) -> any,
	Connect: (self: Client, callback: (val: any) -> ()) -> { Disconnect: () -> () },
}

function Jolt.Server(name: string, config: Config?): Server
	if not RunService:IsServer() then
		error("Jolt.Server can only be called on the server.")
	end

	return Server.new(name, config) :: any
end

function Jolt.Client(name: string): Client
	if not RunService:IsClient() then
		error("Jolt.Client can only be called on the client.")
	end

	return Client.new(name) :: any
end

return Jolt
