AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

ENT.spawnAngleOffset = Angle()

duplicator.RegisterEntityClass( "ent_gpaint_base", GPaint.MakeScreenSpawner, "Data" )

function ENT:SpawnFunction( ply, tr )
    if not tr.Hit then return end

    local angleOffset = self.spawnAngleOffset or Angle()

    return GPaint.MakeScreenSpawner( ply, {
        Pos = tr.HitPos,
        Angle = Angle( 90, ply:EyeAngles().y, 0 ) + angleOffset,
        Class = self.ClassName
    } )
end

function ENT:Initialize()
    self:SetModel( self.ScreenModel )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_NONE )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetUseType( SIMPLE_USE )
    self:DrawShadow( false )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:EnableMotion( false )
    end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_PVS
end

function ENT:SetGPaintOwner( ply )
    self:SetGPaintOwnerSteamID( ply:SteamID() )
end
