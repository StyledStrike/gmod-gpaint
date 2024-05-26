AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ent_gpaint_base"

ENT.PrintName = "GPaint (3x5)"
ENT.Category = "GPaint"
ENT.Spawnable = true

ENT.ScreenModel = "models/hunter/plates/plate3x5.mdl"

if SERVER then
    duplicator.RegisterEntityClass( "ent_gpaint_3x5", GPaint.MakeScreenSpawner, "Data" )
end

if CLIENT then
    ENT.IconOverride = "materials/entities/ent_gpaint_base.png"

    list.Set(
        "GPaintScreenOffsets",
        ENT.ScreenModel,
        {
            pos = Vector( -71, 118.5, -1.6 ),
            ang = Angle( 0, 270, 0 ),
            scale = Vector( 0.2316, 0.2467, 1 )
        }
    )
end