-- FFI binding to libMAD

local general 				= require"general"
local current_script_dir 	= general.current_script_dir

local rel_dir = assert ( current_script_dir ( ) , "Current directory unknown" )

local bit 					= require"bit"
local band 					= bit.band

local rand					= math.random

local ffi 					= require"ffi"
local ffi_util 				= require"ffi_util"
local ffi_add_include_dir 	= ffi_util.ffi_add_include_dir
local ffi_defs 				= ffi_util.ffi_defs
local ffi_process_defines 	= ffi_util.ffi_process_defines

ffi_add_include_dir ( rel_dir )
ffi_defs ( rel_dir .. "defs.h" , { [[mad.h]] } )

local mad
if jit.os == "Windows" then
	mad = ffi.load ( rel_dir .. "libMAD" )
--elseif jit.os == "Linux" or jit.os == "OSX" or jit.os == "POSIX" or jit.os == "BSD" then
else
	error ( "Unknown platform" )
end

local mad_defs = ffi_process_defines( [[mad.h]] )


local version 		= ffi.string ( mad.mad_version )
local copyright  	= ffi.string ( mad.mad_copyright )
local author 		= ffi.string ( mad.mad_author )
local build 		= ffi.string ( mad.mad_build )

local methods = { }
local mt = {
	__index = methods ;
	__gc = function ( o )
		mad_synth_finish ( o.synth )
		mad_frame_finish ( o.frame )
		mad_stream_finish ( o.stream )
	end ;
}

local function is_recoverable ( stream )
	return band ( stream[0].error , 0xff00 ) ~= 0
end

local function to16bit ( x )
	local y = x/2^(mad_defs.MAD_F_FRACBITS-15)+( rand ( )-0.5)
	return y--ffi.cast ( "int16_t" , y )
end

local function new ()
	local stream = ffi.new ( "struct mad_stream[1]" )
	local frame = ffi.new ( "struct mad_frame[1]" )
	local synth = ffi.new ( "struct mad_synth[1]" )

	mad.mad_stream_init ( stream )
	mad.mad_frame_init ( frame )
	mad.mad_synth_init ( synth )

	return setmetatable ( {
		stream = stream ;
		frame = frame ;
		synth = synth ;
	} , mt )
end

local BUFF_SIZE = 8192
function methods:frames ( file )
	local input_bytes = 0
	local buffer = ffi.new ( "char[?]", BUFF_SIZE )
	local function fillbuffer ( stream )
		if stream[0].next_frame ~= nil then
			input_bytes = (buffer+input_bytes)-stream[0].next_frame
			ffi.copy ( buffer , stream[0].next_frame , input_bytes )
		end

		local len = BUFF_SIZE - input_bytes
		local s = file:read ( len )
		if s == nil then -- EOF
			return false
		end
		ffi.copy ( buffer+input_bytes , s , #s )

		input_bytes = input_bytes + #s
		mad.mad_stream_buffer ( stream , buffer , input_bytes )
		return true
	end

	return function ( m )
			while mad.mad_frame_decode ( m.frame , m.stream ) == -1 do
				if m.stream[0].error == mad.MAD_ERROR_BUFLEN or m.stream[0].buffer == nil then
					local eof = fillbuffer ( m.stream )
					if not eof then return nil end
				elseif is_recoverable ( m.stream ) then
					--print("RECOV" , ffi.string ( mad.mad_stream_errorstr ( m.stream ) ))
				else
					error ( ffi.string ( mad.mad_stream_errorstr ( m.stream ) ) )
				end
			end
			mad.mad_synth_frame ( m.synth , m.frame )

			return m.frame[0].header , m.synth[0].pcm
		end , self
end

return {
	version 	= version ;
	copyright 	= copyright ;
	author 		= author ;
	build 		= build ;

	new 		= new ;

	to16bit 	= to16bit ;
}
