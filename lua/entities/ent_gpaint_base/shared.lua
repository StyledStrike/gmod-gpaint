ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "GPaint (2x3)"
ENT.Category = "GPaint"

ENT.Author = "StyledStrike"
ENT.Contact = "StyledStrike#8032"
ENT.Purpose = "Draw stuff into it, I guess"
ENT.Instructions = "Aim at it, then press ATTACK to paint"

ENT.Spawnable = true
ENT.AdminOnly = false

ENT.model = "models/hunter/plates/plate2x3.mdl"

function ENT:CanPlayerDraw( ply )
    if game.SinglePlayer() then return true end

    if CPPI then
        if ply == self:CPPIGetOwner() then return true end
    else
        return true
    end

    return false
end