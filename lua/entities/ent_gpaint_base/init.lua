AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

ENT.spawnAngleOffset = Angle( 0, 0, 0 )

function ENT:SpawnFunction( ply, tr )
    if not tr.Hit then return end
    if not ply:CheckLimit( "gpaint_boards" ) then return end

    local ent = ents.Create( self.ClassName )
    ent:SetPos( tr.HitPos )
    ent:SetAngles( Angle( 90, ply:EyeAngles().y, 0 ) + ent.spawnAngleOffset )
    ent:Spawn()
    ent:Activate()

    ply:AddCount( "gpaint_boards", ent )

    return ent
end

function ENT:Initialize()
    self:SetModel( self.model )
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
    return TRANSMIT_ALWAYS
end