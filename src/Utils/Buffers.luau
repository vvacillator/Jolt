--!strict
local Buffers = {}

local buffer_create = buffer.create
local buffer_len = buffer.len
local buffer_copy = buffer.copy
local buffer_writeu8 = buffer.writeu8
local buffer_readu8 = buffer.readu8
local buffer_writef32 = buffer.writef32
local buffer_readf32 = buffer.readf32
local buffer_writef64 = buffer.writef64
local buffer_readf64 = buffer.readf64
local buffer_writei32 = buffer.writei32
local buffer_readi32 = buffer.readi32
local buffer_writeu16 = buffer.writeu16
local buffer_readu16 = buffer.readu16
local buffer_writestring = buffer.writestring
local buffer_readstring = buffer.readstring

export type Writer = {
	buff: buffer,
	cursor: number,
	len: number,
	refs: {Instance},
}

export type Reader = {
	buff: buffer,
	cursor: number,
	len: number,
	refs: {Instance}?,
}

local INITIAL_BUFFER_SIZE = 1024

local TYPE_NIL = 0
local TYPE_NUMBER = 2
local TYPE_STRING = 3
local TYPE_TABLE = 4
local TYPE_VECTOR3 = 5
local TYPE_CFRAME_FULL = 6
local TYPE_COLOR3 = 7
local TYPE_INSTANCE = 8
local TYPE_CFRAME_POS = 18
local TYPE_BOOL_TRUE = 9
local TYPE_BOOL_FALSE = 10
local TYPE_ENUM = 11
local TYPE_UDIM = 12
local TYPE_UDIM2 = 13
local TYPE_TWEENINFO = 14
local TYPE_INTEGER = 15
local TYPE_BRICKCOLOR = 16
local TYPE_VECTOR2 = 17

local writerPool = {} :: {Writer}
local readerPool = {} :: {Reader}

local MAX_POOL_SIZE = 64

local function resize(w: Writer, needed: number)
	local newLen = math.max(w.len * 2, needed)
	local newBuff = buffer_create(newLen)
	buffer_copy(newBuff, 0, w.buff, 0, w.cursor)
	w.buff = newBuff
	w.len = newLen
end

local function ensure(w: Writer, n: number)
	if w.cursor + n > w.len then
		resize(w, w.cursor + n)
	end
end

function Buffers.CreateWriter(): Writer
	local w = table.remove(writerPool)
	if w then
		return w
	end
	return {
		buff = buffer_create(INITIAL_BUFFER_SIZE),
		cursor = 0,
		len = INITIAL_BUFFER_SIZE,
		refs = {},
	}
end

function Buffers.FreeWriter(w: Writer)
	if #writerPool < MAX_POOL_SIZE then
		w.cursor = 0
		w.len = INITIAL_BUFFER_SIZE
		w.buff = buffer_create(INITIAL_BUFFER_SIZE)
		table.clear(w.refs)
		table.insert(writerPool, w)
	end
end

function Buffers.CreateReader(b: buffer, refs: {Instance}?): Reader
	local r = table.remove(readerPool)
	if r then
		r.buff = b
		r.cursor = 0
		r.len = buffer_len(b)
		r.refs = refs
		return r
	end
	return {
		buff = b,
		cursor = 0,
		len = buffer_len(b),
		refs = refs,
	}
end

function Buffers.FreeReader(r: Reader)
	if #readerPool < MAX_POOL_SIZE then
		r.refs = nil
		table.insert(readerPool, r)
	end
end

function Buffers.Finalize(w: Writer): (buffer, {Instance})
	local b = buffer_create(w.cursor)
	buffer_copy(b, 0, w.buff, 0, w.cursor)
	return b, w.refs
end

function Buffers.WriteByte(w: Writer, v: number)
	ensure(w, 1)
	buffer_writeu8(w.buff, w.cursor, v)
	w.cursor += 1
end

function Buffers.ReadByte(r: Reader): number
	local v = buffer_readu8(r.buff, r.cursor)
	r.cursor += 1
	return v
end

function Buffers.WriteVarInt(w: Writer, v: number)
	ensure(w, 5)
	while v >= 128 do
		buffer_writeu8(w.buff, w.cursor, bit32.bor(bit32.band(v, 0x7F), 0x80))
		w.cursor += 1
		v = bit32.rshift(v, 7)
	end
	buffer_writeu8(w.buff, w.cursor, v)
	w.cursor += 1
end

function Buffers.ReadVarInt(r: Reader): number
	local result = 0
	local shift = 0
	local b
	repeat
		b = buffer_readu8(r.buff, r.cursor)
		r.cursor += 1
		result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), shift))
		shift += 7
	until bit32.band(b, 0x80) == 0
	return result
end

function Buffers.WriteZigZag(w: Writer, v: number)
	local z = bit32.bxor(bit32.lshift(v, 1), bit32.arshift(v, 31))
	Buffers.WriteVarInt(w, z)
end

function Buffers.ReadZigZag(r: Reader): number
	local z = Buffers.ReadVarInt(r)
	return bit32.bxor(bit32.rshift(z, 1), -bit32.band(z, 1))
end

function Buffers.WriteNumber(w: Writer, v: number)
	ensure(w, 8)
	buffer_writef64(w.buff, w.cursor, v)
	w.cursor += 8
end

function Buffers.ReadNumber(r: Reader): number
	local v = buffer_readf64(r.buff, r.cursor)
	r.cursor += 8
	return v
end

function Buffers.WriteString(w: Writer, v: string)
	local len = #v
	Buffers.WriteVarInt(w, len)
	ensure(w, len)
	buffer_writestring(w.buff, w.cursor, v, len)
	w.cursor += len
end

function Buffers.ReadString(r: Reader): string
	local len = Buffers.ReadVarInt(r)
	local v = buffer_readstring(r.buff, r.cursor, len)
	r.cursor += len
	return v
end

function Buffers.WriteVector2(w: Writer, v: Vector2)
	ensure(w, 8)
	buffer_writef32(w.buff, w.cursor, v.X)
	buffer_writef32(w.buff, w.cursor + 4, v.Y)
	w.cursor += 8
end

function Buffers.ReadVector2(r: Reader): Vector2
	local x = buffer_readf32(r.buff, r.cursor)
	local y = buffer_readf32(r.buff, r.cursor + 4)
	r.cursor += 8
	return Vector2.new(x, y)
end

function Buffers.WriteVector3(w: Writer, v: Vector3)
	ensure(w, 12)
	buffer_writef32(w.buff, w.cursor, v.X)
	buffer_writef32(w.buff, w.cursor + 4, v.Y)
	buffer_writef32(w.buff, w.cursor + 8, v.Z)
	w.cursor += 12
end

function Buffers.ReadVector3(r: Reader): Vector3
	local x = buffer_readf32(r.buff, r.cursor)
	local y = buffer_readf32(r.buff, r.cursor + 4)
	local z = buffer_readf32(r.buff, r.cursor + 8)
	r.cursor += 12
	return Vector3.new(x, y, z)
end

local PI = math.pi
local TWO_PI = 2 * PI
local U16_MAX = 65535

function Buffers.WriteCFrame(w: Writer, cf: CFrame)
	ensure(w, 20)

	local b = w.buff
	local o = w.cursor
	buffer_writef32(b, o, cf.X)
	buffer_writef32(b, o + 4, cf.Y)
	buffer_writef32(b, o + 8, cf.Z)

	local axis, angle = cf:ToAxisAngle()

	local phi = math.atan2(axis.X, axis.Z)
	local theta = math.acos(axis.Y)

	local phi_u16 = math.round(((phi + PI) / TWO_PI) * U16_MAX)
	local theta_u16 = math.round((theta / PI) * U16_MAX)

	buffer_writeu16(b, o + 12, phi_u16)
	buffer_writeu16(b, o + 14, theta_u16)
	buffer_writef32(b, o + 16, angle)

	w.cursor += 20
end

function Buffers.ReadCFrame(r: Reader): CFrame
	local b = r.buff
	local o = r.cursor

	local px = buffer_readf32(b, o)
	local py = buffer_readf32(b, o + 4)
	local pz = buffer_readf32(b, o + 8)

	local phi_u16 = buffer_readu16(b, o + 12)
	local theta_u16 = buffer_readu16(b, o + 14)
	local angle = buffer_readf32(b, o + 16)

	r.cursor += 20

	if angle == 0 then
		return CFrame.new(px, py, pz)
	end

	local phi = ((phi_u16 / U16_MAX) * TWO_PI) - PI
	local theta = (theta_u16 / U16_MAX) * PI

	local sin_theta = math.sin(theta)

	local axis_x = sin_theta * math.sin(phi)
	local axis_y = math.cos(theta)
	local axis_z = sin_theta * math.cos(phi)

	local axis = Vector3.new(axis_x, axis_y, axis_z)

	return CFrame.new(px, py, pz) * CFrame.fromAxisAngle(axis, angle)
end

function Buffers.WriteColor3(w: Writer, c: Color3)
	ensure(w, 3)
	local b = w.buff
	local o = w.cursor
	buffer_writeu8(b, o, math.round(c.R * 255))
	buffer_writeu8(b, o + 1, math.round(c.G * 255))
	buffer_writeu8(b, o + 2, math.round(c.B * 255))
	w.cursor += 3
end

function Buffers.ReadColor3(r: Reader): Color3
	local b = r.buff
	local o = r.cursor
	local rr = buffer_readu8(b, o) / 255
	local gg = buffer_readu8(b, o + 1) / 255
	local bb = buffer_readu8(b, o + 2) / 255
	r.cursor += 3
	return Color3.new(rr, gg, bb)
end

function Buffers.WriteBrickColor(w: Writer, bc: BrickColor)
	ensure(w, 2)
	buffer_writeu16(w.buff, w.cursor, bc.Number)
	w.cursor += 2
end

function Buffers.ReadBrickColor(r: Reader): BrickColor
	local n = buffer_readu16(r.buff, r.cursor)
	r.cursor += 2
	return BrickColor.new(n)
end

function Buffers.WriteInstance(w: Writer, inst: Instance)
	table.insert(w.refs, inst)
	Buffers.WriteVarInt(w, #w.refs)
end

function Buffers.ReadInstance(r: Reader): Instance?
	local idx = Buffers.ReadVarInt(r)
	return if r.refs then r.refs[idx] else nil
end

function Buffers.WriteEnum(w: Writer, e: EnumItem)
	Buffers.WriteString(w, tostring(e))
end

function Buffers.ReadEnum(r: Reader): EnumItem?
	local s = Buffers.ReadString(r)
	local parts = s:split(".")

	if #parts == 3 then
		local enumName = parts[2]
		local itemName = parts[3]
		local enum = (Enum :: any)[enumName]

		if enum then
			return enum[itemName]
		end
	end

	return nil
end

function Buffers.WriteUDim(w: Writer, u: UDim)
	ensure(w, 8)
	buffer_writef32(w.buff, w.cursor, u.Scale)
	buffer_writei32(w.buff, w.cursor + 4, u.Offset)
	w.cursor += 8
end

function Buffers.ReadUDim(r: Reader): UDim
	local s = buffer_readf32(r.buff, r.cursor)
	local o = buffer_readi32(r.buff, r.cursor + 4)
	r.cursor += 8
	return UDim.new(s, o)
end

function Buffers.WriteUDim2(w: Writer, u: UDim2)
	ensure(w, 16)
	buffer_writef32(w.buff, w.cursor, u.X.Scale)
	buffer_writei32(w.buff, w.cursor + 4, u.X.Offset)
	buffer_writef32(w.buff, w.cursor + 8, u.Y.Scale)
	buffer_writei32(w.buff, w.cursor + 12, u.Y.Offset)
	w.cursor += 16
end

function Buffers.ReadUDim2(r: Reader): UDim2
	local xs = buffer_readf32(r.buff, r.cursor)
	local xo = buffer_readi32(r.buff, r.cursor + 4)
	local ys = buffer_readf32(r.buff, r.cursor + 8)
	local yo = buffer_readi32(r.buff, r.cursor + 12)
	r.cursor += 16
	return UDim2.new(xs, xo, ys, yo)
end

function Buffers.WriteTweenInfo(w: Writer, t: TweenInfo)
	Buffers.WriteNumber(w, t.Time)
	Buffers.WriteEnum(w, t.EasingStyle)
	Buffers.WriteEnum(w, t.EasingDirection)
	Buffers.WriteNumber(w, t.RepeatCount)
	Buffers.WriteByte(w, t.Reverses and 1 or 0)
	Buffers.WriteNumber(w, t.DelayTime)
end

function Buffers.ReadTweenInfo(r: Reader): TweenInfo
	local time = Buffers.ReadNumber(r)
	local style = Buffers.ReadEnum(r) or Enum.EasingStyle.Quad
	local dir = Buffers.ReadEnum(r) or Enum.EasingDirection.Out
	local repeatCount = Buffers.ReadNumber(r)
	local reverses = Buffers.ReadByte(r) == 1
	local delayTime = Buffers.ReadNumber(r)
	return TweenInfo.new(time, style :: Enum.EasingStyle, dir :: Enum.EasingDirection, repeatCount, reverses, delayTime)
end

function Buffers.WriteTable(w: Writer, t: {[any]: any})
	for k, v in pairs(t) do
		Buffers.WriteAny(w, k)
		Buffers.WriteAny(w, v)
	end
	Buffers.WriteByte(w, TYPE_NIL)
end

function Buffers.ReadTable(r: Reader): {[any]: any}
	local t = {}
	while true do
		local k = Buffers.ReadAny(r)
		if k == nil then break end
		local v = Buffers.ReadAny(r)
		t[k] = v
	end
	return t
end

local TypeWriters = {
	number = function(w, v)
		if v % 1 == 0 and v >= -2147483648 and v <= 2147483647 then
			Buffers.WriteByte(w, TYPE_INTEGER)
			Buffers.WriteZigZag(w, v)
		else
			Buffers.WriteByte(w, TYPE_NUMBER)
			Buffers.WriteNumber(w, v)
		end
	end,
	string = function(w, v)
		Buffers.WriteByte(w, TYPE_STRING)
		Buffers.WriteString(w, v)
	end,
	boolean = function(w, v)
		Buffers.WriteByte(w, v and TYPE_BOOL_TRUE or TYPE_BOOL_FALSE)
	end,
	table = function(w, v)
		Buffers.WriteByte(w, TYPE_TABLE)
		Buffers.WriteTable(w, v)
	end,
	Instance = function(w, v)
		Buffers.WriteByte(w, TYPE_INSTANCE)
		Buffers.WriteInstance(w, v)
	end,
	Vector3 = function(w, v)
		Buffers.WriteByte(w, TYPE_VECTOR3)
		Buffers.WriteVector3(w, v)
	end,
	CFrame = function(w, v)
		local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()

		if r00 == 1 and r01 == 0 and r02 == 0 and r10 == 0 and r11 == 1 and r12 == 0 and r20 == 0 and r21 == 0 and r22 == 1 then
			Buffers.WriteByte(w, TYPE_CFRAME_POS)
			Buffers.WriteVector3(w, v.Position)
		else
			Buffers.WriteByte(w, TYPE_CFRAME_FULL)
			Buffers.WriteCFrame(w, v)
		end
	end,
	Color3 = function(w, v)
		Buffers.WriteByte(w, TYPE_COLOR3)
		Buffers.WriteColor3(w, v)
	end,
	BrickColor = function(w, v)
		Buffers.WriteByte(w, TYPE_BRICKCOLOR)
		Buffers.WriteBrickColor(w, v)
	end,
	Vector2 = function(w, v)
		Buffers.WriteByte(w, TYPE_VECTOR2)
		Buffers.WriteVector2(w, v)
	end,
	EnumItem = function(w, v)
		Buffers.WriteByte(w, TYPE_ENUM)
		Buffers.WriteEnum(w, v)
	end,
	UDim2 = function(w, v)
		Buffers.WriteByte(w, TYPE_UDIM2)
		Buffers.WriteUDim2(w, v)
	end,
	UDim = function(w, v)
		Buffers.WriteByte(w, TYPE_UDIM)
		Buffers.WriteUDim(w, v)
	end,
	TweenInfo = function(w, v)
		Buffers.WriteByte(w, TYPE_TWEENINFO)
		Buffers.WriteTweenInfo(w, v)
	end,
	["nil"] = function(w, v)
		Buffers.WriteByte(w, TYPE_NIL)
	end,
}

local TypeReaders = {
	[TYPE_NUMBER] = Buffers.ReadNumber,
	[TYPE_INTEGER] = Buffers.ReadZigZag,
	[TYPE_STRING] = Buffers.ReadString,
	[TYPE_BOOL_TRUE] = function() return true end,
	[TYPE_BOOL_FALSE] = function() return false end,
	[TYPE_TABLE] = Buffers.ReadTable,
	[TYPE_INSTANCE] = Buffers.ReadInstance,
	[TYPE_VECTOR3] = Buffers.ReadVector3,
	[TYPE_CFRAME_FULL] = Buffers.ReadCFrame,
	[TYPE_CFRAME_POS] = function(r) return CFrame.new(Buffers.ReadVector3(r)) end,
	[TYPE_COLOR3] = Buffers.ReadColor3,
	[TYPE_BRICKCOLOR] = Buffers.ReadBrickColor,
	[TYPE_VECTOR2] = Buffers.ReadVector2,
	[TYPE_ENUM] = Buffers.ReadEnum,
	[TYPE_UDIM2] = Buffers.ReadUDim2,
	[TYPE_UDIM] = Buffers.ReadUDim,
	[TYPE_TWEENINFO] = Buffers.ReadTweenInfo,
	[TYPE_NIL] = function() return nil end,
}

function Buffers.WriteAny(w: Writer, v: any)
	local t = typeof(v)
	local writer = TypeWriters[t]

	if writer then
		writer(w, v)
	else
		warn("Unsupported type:", t)
		Buffers.WriteByte(w, TYPE_NIL)
	end
end

function Buffers.ReadAny(r: Reader): any
	local t = Buffers.ReadByte(r)
	local reader = TypeReaders[t]

	if reader then
		return reader(r)
	else
		warn("Unknown type tag:", t)
		return nil
	end
end

function Buffers.Pack(w: Writer, ...)
	local n = select("#", ...)
	Buffers.WriteByte(w, n)
	for i = 1, n do
		Buffers.WriteAny(w, select(i, ...))
	end
end

function Buffers.Unpack(r: Reader): {any}
	local n = Buffers.ReadByte(r)
	local results = table.create(n)
	for i = 1, n do
		results[i] = Buffers.ReadAny(r)
	end
	return results
end

return Buffers
