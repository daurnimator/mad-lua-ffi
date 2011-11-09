-- FFI binding to libMAD

local general 				= require"general"
local current_script_dir 	= general.current_script_dir

local rel_dir = assert ( current_script_dir ( ) , "Current directory unknown" )

local assert , error 	= assert , error
local setmetatable 		= setmetatable
local bit 				= require"bit"
local band 				= bit.band
local rand				= math.random

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
		mad.mad_synth_finish ( o.synth )
		mad.mad_frame_finish ( o.frame )
		mad.mad_stream_finish ( o.stream )
	end ;
}

local function is_recoverable ( stream )
	return band ( stream[0].error , 0xff00 ) ~= 0
end

local function nsbsamples ( header )
	if header.layer == mad.MAD_LAYER_I then
		return 12
	elseif header.layer == mad.MAD_LAYER_III and band ( header.flags , mad.MAD_FLAG_LSF_EXT ) ~= 0 then
		return 18
	else
		return 36
	end
end

local function to16bit ( x )
	local y = x * 2^-( mad_defs.MAD_F_FRACBITS - 14 ) + ( rand ( ) - 0.5 )
	--if math.abs(y) > 2^15 then print("CLIPPED",y) end
	return y
end

function methods:reset ( )
	mad.mad_stream_init ( self.stream )
	mad.mad_frame_init ( self.frame )
	mad.mad_synth_init ( self.synth )
	self.input_bytes = 0
end

local header_methods = { }
local header_mt = { __index = header_methods }

function header_methods:channels ( )
	if self.mode == 0 then return 1
	else return 2 end
end

function header_methods:length ( )
	return 32 * nsbsamples ( self )
end

ffi.metatype ( "struct mad_header" , header_mt )

local DEFAULT_BUFF_SIZE = 8192
local function new ( buff_size )
	buff_size = buff_size or DEFAULT_BUFF_SIZE

	local stream = ffi.new ( "struct mad_stream[1]" )
	local frame = ffi.new ( "struct mad_frame[1]" )
	local synth = ffi.new ( "struct mad_synth[1]" )
	local buffer = ffi.new ( "char[?]", buff_size )

	local m = setmetatable ( {
		stream = stream ;
		frame = frame ;
		synth = synth ;

		buff_size = buff_size ;
		buffer = buffer ;
		input_bytes = 0 ;
	} , mt )
	m:reset ( )

	return m
end


function methods:skipframe ( getmore , n , func )
	for s = 1 , n+1 do
		while mad.mad_header_decode ( self.frame[0].header , self.stream ) == -1 do
			if self.stream[0].error == mad.MAD_ERROR_BUFLEN or self.stream[0].buffer == nil then
				local not_eof = self:fillbuffer ( getmore )
				if not not_eof then return false end
			elseif is_recoverable ( self.stream ) then
--			print("RECOV SKIP",ffi.string ( mad.mad_stream_errorstr ( self.stream ) ),s)
			else
				error ( ffi.string ( mad.mad_stream_errorstr ( self.stream ) ) )
			end
		end
		if func then func ( self.frame[0].header , self.stream[0] ) end
	end
	return true
end

function methods:fillbuffer ( getmore )
	local next_frame = self.stream[0].next_frame
	if next_frame ~= nil then
		self.input_bytes = ( self.buffer + self.input_bytes ) - next_frame
		ffi.copy ( self.buffer , next_frame , self.input_bytes )
	end

	local len = self.buff_size - self.input_bytes
	local got = getmore ( self.buffer + self.input_bytes , len , self.input_bytes ) -- Destination buffer, buffer length, last overshoot
	if not got then return false end

	self.input_bytes = self.input_bytes + got
	mad.mad_stream_buffer ( self.stream , self.buffer , self.input_bytes )
	return true
end

function methods:frames ( getmore )
	assert ( self:skipframe ( getmore , 0 ) , "Unexpected EOF" )

	return function ( self )
			while mad.mad_frame_decode ( self.frame , self.stream ) == -1 do
				if self.stream[0].error == mad.MAD_ERROR_BUFLEN or self.stream[0].buffer == nil then
					local not_eof = self:fillbuffer ( getmore )
					if not not_eof then return nil end
				elseif is_recoverable ( self.stream ) then
--				print("RECOV DECODE" , ffi.string ( mad.mad_stream_errorstr ( self.stream ) ))
				else
					error ( ffi.string ( mad.mad_stream_errorstr ( self.stream ) ) )
				end
			end
			mad.mad_synth_frame ( self.synth , self.frame )

			return self.frame[0].header , self.stream[0] , self.synth[0].pcm
		end , self , self.frame[0].header
end

return {
	version 	= version ;
	copyright 	= copyright ;
	author 		= author ;
	build 		= build ;

	new 		= new ;

	nsbsamples 	= nsbsamples ;
	to16bit 	= to16bit ;
}
