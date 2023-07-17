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

    if ply:SteamID() == self:GetGPaintOwnerSteamID() then
        return true
    end

    if self.GPaintWhitelist[ply:SteamID()] then
        return true
    end

    return false
end

function ENT:SetupDataTables()
    self:NetworkVar( "String", 0, "GPaintOwnerSteamID" )
    self.GPaintWhitelist = {}
end

properties.Add( "gpaint.turnoff", {
    MenuLabel = "#gpaint.turnoff",
    Order = 999,
    MenuIcon = "icon16/bullet_red.png",

    Filter = function( _, ent, ply )
        if
            GPaint.IsGPaintScreen( ent ) and
            gamemode.Call( "CanProperty", ply, "gpaint.turnoff", ent ) and
            ply:SteamID() ~= ent:GetGPaintOwnerSteamID()
        then
            return true
        end

        return false
    end,

    Action = function( _, ent )
        for _, scr in pairs( GPaint.screens ) do
            if scr.entity == ent then
                scr.wantsToSubscribe = false
                scr:Clear()
                scr:OnHide()
            end
        end
    end
} )