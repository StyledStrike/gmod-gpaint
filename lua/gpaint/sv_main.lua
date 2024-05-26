resource.AddWorkshop( "2697023796" )

CreateConVar(
    "sbox_maxgpaint_boards",
    "3",
    bit.bor( FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED ),
    "Maximum GPaint screens a player can create",
    0
)

function GPaint.MakeScreenSpawner( ply, data )
    if not IsValid( ply ) then return end
    if not ply:CheckLimit( "gpaint_boards" ) then return end

    local ent = ents.Create( data.Class )
    if not IsValid( ent ) then return end

    ent:SetPos( data.Pos )
    ent:SetAngles( data.Angle )
    ent:Spawn()
    ent:Activate()
    ent:SetGPaintOwner( ply )

    ply:AddCount( "gpaint_boards", ent )

    timer.Simple( 1, function()
        if IsValid( ply ) and IsValid( ent ) then
            GPaint.StartCommand( GPaint.SUBSCRIBE, ent )
            net.Send( ply )
        end
    end )

    return ent
end
