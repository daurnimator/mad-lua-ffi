-- A test for luajit ffi based libmad bindings

local FILE = assert ( arg[1] , "No input file" )

package.path = "./?/init.lua;" .. package.path
package.loaded [ "mad" ] = dofile ( "init.lua" )
local mad = require"mad"

local ffi = require"ffi"

print ( "Version:" , mad.version )
print ( "Copyright:" , mad.copyright )
print ( "Author:" , mad.author )
print ( "Build:" , mad.build )
print ( )

local file = io.open ( FILE , "rb" )
local m = mad.new ( )

local outfilename = "samples.raw"
local fo = io.open ( outfilename , "wb" )
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

	fo:write ( ffi.string ( out , samples * channels * ffi.sizeof ( "int16_t" ) ) )
end
fo:close()

print ( "Sample Rate:" , sample_rate )
print ( "Channels:" , channels )
