--!strict
local Remotes = {}

function Remotes.Get(name: string): RemoteEvent | UnreliableRemoteEvent
	local remote = script:FindFirstChild(name)
	if not remote then
		error("Remote '" .. name .. "' doesn't exist. Ensure it is created on the server first.")
	end

	return remote :: RemoteEvent | UnreliableRemoteEvent
end

function Remotes.Create(name: string, unreliable: boolean?): RemoteEvent | UnreliableRemoteEvent
	local className = unreliable and "UnreliableRemoteEvent" or "RemoteEvent"
	local remote = script:FindFirstChild(name)

	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = script
	elseif not remote:IsA(className) then
		error("Existing instance '" .. name .. "' in " .. script:GetFullName() .. " is not a " .. className)
	end

	return remote :: RemoteEvent | UnreliableRemoteEvent
end

return Remotes
