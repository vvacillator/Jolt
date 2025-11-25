--!strict

local Jolt = {}

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local Client = require("@self/Client")
local Server = require("@self/Server")

export type Config = Server.Config

export type Server = {
	Fire: (self: Server, player: Player, ...any) -> (),
	FireAll: (self: Server, ...any) -> (),
	Connect: (self: Server, callback: (player: Player, ...any) -> ()) -> { Disconnect: () -> () },
	OnInvoke: ((player: Player, ...any) -> ...any)?,
}

export type Client = {
	Fire: (self: Client, ...any) -> (),
	Invoke: (self: Client, ...any) -> ...any,
	Connect: (self: Client, callback: (...any) -> ()) -> { Disconnect: () -> () },
}

local Jolt = table.freeze({
	Server = function(name: string, config: Config?): Server
	if not IS_SERVER then
		error("Jolt.Server can only be called on the server.")
	end

		return Server.new(name, config) :: any
	end,

	Client = function(name: string): Client
	if IS_SERVER then
		error("Jolt.Client can only be called on the client.")
	end

		return Client.new(name) :: any
	end,
})

return Jolt