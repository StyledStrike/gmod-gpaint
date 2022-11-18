GPaint = {
    rtResolution = 512
}

function GPaint.LogF( str, ... )
    MsgC( Color( 182,0,206 ), '[GPaint] ', color_white, string.format( str, ... ), '\n' )
end

if SERVER then
    include( 'gpaint/sh_net.lua' )
    include( 'gpaint/sv_init.lua' )

    AddCSLuaFile( 'gpaint/sh_net.lua' )
    AddCSLuaFile( 'gpaint/cl_init.lua' )
    AddCSLuaFile( 'gpaint/cl_screen.lua' )
    AddCSLuaFile( 'gpaint/cl_menu.lua' )
end

if CLIENT then
    include( 'gpaint/sh_net.lua' )
    include( 'gpaint/cl_init.lua' )
    include( 'gpaint/cl_screen.lua' )
    include( 'gpaint/cl_menu.lua' )
end