-- A test for luajit ffi based libmad bindings

local ioopen = io.open

local general 				= require"general"
local pretty 				= general.pretty_print
local current_script_dir 	= general.current_script_dir
local rel_dir = assert ( current_script_dir ( ) , "Current directory unknown" )
package.path = package.path .. ";" .. rel_dir .. "../?/init.lua"

local mad = require"mad"

local ffi = require"ffi"

print ( "Version:" , mad.version )
print ( "Copyright:" , mad.copyright )
print ( "Author:" , mad.author )
print ( "Build:" , mad.build )
print ( )

local inputfile = assert ( arg[1] , "No input file" )

local file = ioopen ( inputfile , "rb" )
local m = mad.new ( )

local fo = ioopen ( "samples.raw" , "wb" )
local len = 0
local out

local channels , sample_rate

local getmore = function ( dest , len )
	local s = file:read ( len )
	if s == nil then -- EOF
		return false
	end
	ffi.copy ( dest , s , #s )
	return #s
end

for header , stream , pcm in m:frames ( getmore ) do
	sample_rate = header.samplerate

	local samples = pcm.length
	channels = pcm.channels

	if samples*channels > len then
		len = samples*channels
		out = ffi.new ( "int16_t[?]" , len )
	end

	for i=0 , samples-1 do
		for c=0 , channels-1 do
			out [ i*channels + c ] = mad.to16bit ( pcm.samples[c][i] )
		end
	end
	fo:write ( ffi.string ( out , samples*channels*2 ) )
end

print ( "Sample Rate:" , sample_rate )
print ( "Channels:" , channels )

fo:close()
