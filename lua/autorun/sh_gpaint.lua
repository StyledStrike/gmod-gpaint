GPaint = GPaint or {}

if CLIENT then
    -- Width/height for every render target created by GPaint
    GPaint.RT_SIZE = 512
end

-- Max. number of strokes on a net message
GPaint.MAX_STROKES = 15

-- Used on net.WriteUInt for the command ID
GPaint.COMMAND_SIZE = 4

-- Command IDs (Max. ID when COMMAND_SIZE = 4 is 15)
GPaint.SUBSCRIBE = 0
GPaint.UNSUBSCRIBE = 1
GPaint.CLEAR = 2
GPaint.PEN_STROKES = 3
GPaint.REQUEST_DATA = 4
GPaint.SET_LOADING = 5
GPaint.UPDATE_WHITELIST = 6

CreateConVar(
    "gpaint_max_render_distance",
    "3000",
    bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED ),
    "How close players need to be to render screens.",
    300, 9999
)

function GPaint.PrintF( str, ... )
    MsgC( SERVER and Color( 0, 0, 255 ) or Color( 182, 0, 206 ), "[GPaint] ",
        Color( 255, 255, 255 ), string.format( str, ... ), "\n" )
end

function GPaint.IsGPaintScreen( ent )
    return IsValid( ent ) and ( ent:GetClass() == "ent_gpaint_base" or ent.Base == "ent_gpaint_base" )
end

function GPaint.StartCommand( id, ent )
    net.Start( "gpaint.command", false )
    net.WriteEntity( ent )
    net.WriteUInt( id, GPaint.COMMAND_SIZE )
end

local WriteUInt = net.WriteUInt

function GPaint.WriteStrokes( strokes )
    local count = math.min( #strokes, GPaint.MAX_STROKES )

    WriteUInt( count, 5 )

    for i = 1, count do
        local s = strokes[i]

        -- start pos
        WriteUInt( s[1], 10 )
        WriteUInt( s[2], 10 )

        -- end pos
        WriteUInt( s[3], 10 )
        WriteUInt( s[4], 10 )

        -- thickness
        WriteUInt( s[5], 8 )

        -- r, g, b
        WriteUInt( s[6], 8 )
        WriteUInt( s[7], 8 )
        WriteUInt( s[8], 8 )
    end
end

local ReadUInt = net.ReadUInt

function GPaint.ReadStrokes()
    local count = math.min( ReadUInt( 5 ), GPaint.MAX_STROKES )
    if count < 1 then return {} end

    local strokes = {}

    for i = 1, count do
        strokes[i] = {
            -- start pos
            ReadUInt( 10 ),
            ReadUInt( 10 ),

            -- end pos
            ReadUInt( 10 ),
            ReadUInt( 10 ),

            -- thickness
            ReadUInt( 8 ),

            -- r, g, b
            ReadUInt( 8 ),
            ReadUInt( 8 ),
            ReadUInt( 8 )
        }
    end

    return strokes
end

function GPaint.WriteWhitelist( whitelist )
    -- `whitelist` is a key-value table, convert to a array
    local data = {}

    for id, _ in pairs( whitelist ) do
        data[#data + 1] = id
    end

    data = util.Compress( util.TableToJSON( data ) )

    WriteUInt( #data, 16 )
    net.WriteData( data, #data )
end

function GPaint.ReadWhitelist( output )
    local len = ReadUInt( 16 )
    local data = net.ReadData( len )

    data = util.JSONToTable( util.Decompress( data ) )
    if not data then return end

    table.Empty( output )

    -- `data` is a array, convert to a key-value table
    for _, id in ipairs( data ) do
        output[id] = true
    end
end

if SERVER then
    -- Shared files
    include( "gpaint/sh_stream.lua" )
    AddCSLuaFile( "gpaint/sh_stream.lua" )

    -- Server files
    include( "gpaint/sv_main.lua" )
    include( "gpaint/sv_network.lua" )

    -- Client files
    AddCSLuaFile( "gpaint/cl_main.lua" )
    AddCSLuaFile( "gpaint/cl_network.lua" )
    AddCSLuaFile( "gpaint/cl_screen.lua" )
    AddCSLuaFile( "gpaint/cl_menu.lua" )
end

if CLIENT then
    -- Shared files
    include( "gpaint/sh_stream.lua" )

    -- Client files
    include( "gpaint/cl_main.lua" )
    include( "gpaint/cl_network.lua" )
    include( "gpaint/cl_screen.lua" )
    include( "gpaint/cl_menu.lua" )
end
