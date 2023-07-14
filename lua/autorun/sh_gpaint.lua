GPaint = {
    rtResolution = 512
}

CreateConVar(
    "gpaint_max_render_distance",
    "3000",
    bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED ),
    "[GPaint] How close players need to be before syncing and rendering screens. Higher values can affect network performance",
    300, 9999
)

function GPaint.LogF( str, ... )
    MsgC( Color( 182, 0, 206 ), "[GPaint] ", color_white, string.format( str, ... ), "\n" )
end

function GPaint.IsGPaintScreen( ent )
    return IsValid( ent ) and (
        ent:GetClass() == "ent_gpaint_base" or
        ent.Base == "ent_gpaint_base"
    )
end

if SERVER then
    include( "gpaint/sh_net.lua" )
    include( "gpaint/sv_init.lua" )

    AddCSLuaFile( "gpaint/sh_net.lua" )
    AddCSLuaFile( "gpaint/cl_init.lua" )
    AddCSLuaFile( "gpaint/cl_screen.lua" )
    AddCSLuaFile( "gpaint/cl_menu.lua" )

    function GPaint.MakeScreenSpawner( ply, data )
        if not IsValid( ply ) then return end
        if not ply:CheckLimit( "gpaint_boards" ) then return end

        local ent = ents.Create( data.Class )
        if not IsValid( ent ) then return end

        ent:SetPos( data.Pos )
        ent:SetAngles( data.Angle )
        ent:Spawn()
        ent:Activate()

        ply:AddCount( "gpaint_boards", ent )

        -- set the screen owner
        ent:SetGPaintOwner( ply )

        -- tell the screen owner to subscribe
        timer.Simple( 1, function()
            if IsValid( ply ) and IsValid( ent ) then
                GPaint.network.StartCommand( GPaint.network.SUBSCRIBE, ent )
                net.Send( ply )
            end
        end )

        return ent
    end
end

if CLIENT then
    include( "gpaint/sh_net.lua" )
    include( "gpaint/cl_init.lua" )
    include( "gpaint/cl_screen.lua" )
    include( "gpaint/cl_menu.lua" )
end