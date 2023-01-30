include( "shared.lua" )

ENT.IconOverride = "materials/entities/ent_gpaint_base.png"
ENT.RenderGroup = RENDERGROUP_OPAQUE

list.Set(
    "GPaintScreenOffsets",
    ENT.model,
    {
        pos = Vector( -47.4, 71.1, -1.65 ),
        ang = Angle( 0, 270, 0 ),
        scale = Vector( 0.1388, 0.1645, 1 )
    }
)

function ENT:Initialize()
    self:DrawShadow( false )

    local offsets = list.Get( "GPaintScreenOffsets" )

    self.screenOffset = offsets[self:GetModel()] or {
        pos = Vector( 0, 0, 0 ),
        ang = Angle( 0, 0, 0 ),
        scale = Vector( 1, 1, 1 )
    }

    self.offsetMatrix = Matrix()
    self.offsetMatrix:Translate( self.screenOffset.pos )
    self.offsetMatrix:Rotate( self.screenOffset.ang )
    self.offsetMatrix:Scale( self.screenOffset.scale )

    self.finalMatrix = Matrix()

    GPaint.CreateScreen( self )
end

function ENT:Think()
    self.finalMatrix = self:GetWorldTransformMatrix() * self.offsetMatrix
end

function ENT:GetCursorPos( ply )
    local offset = self.screenOffset

    local pos = self:LocalToWorld( offset.pos )
    local normal = -self.finalMatrix:GetUp()

    local start = ply:GetShootPos()
    local dir = ply:GetAimVector()

    local a = normal:Dot( dir )
    if a == 0 or a > 0 then return end

    local b = normal:Dot( pos - start ) / a
    if b < 0 then return end

    local hitPos = self.finalMatrix:GetInverseTR() * ( start + dir * b )
    return hitPos.x / offset.scale.x ^ 2, hitPos.y / offset.scale.y ^ 2
end