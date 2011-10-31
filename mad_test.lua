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

local fo = io.open ( "samples.raw" , "wb" )
local len = 0
local out

local channels , sample_rate
for header , frame in m:frames ( file ) do
	sample_rate = header.samplerate

	local samples = m.synth[0].pcm.length
	channels = m.synth[0].pcm.channels
	--local bitrate = m.frame[0].header.bitrate

	if samples*channels > len then
		len = samples*channels
		out = ffi.new ( "int16_t[?]" , len )
	end

	for i=0 , samples-1 do
		for c=0 , channels-1 do
			out [ i*channels + c ] = mad.to16bit ( m.synth[0].pcm.samples[c][i] )
		end
	end
	fo:write ( ffi.string ( out , len*2 ) )
end

print ( "Sample Rate:" , sample_rate )
print ( "Channels:" , channels )

fo:close()
