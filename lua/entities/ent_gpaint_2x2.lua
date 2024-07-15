AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ent_gpaint_base"

ENT.PrintName = "GPaint (2x2)"
ENT.Category = "GPaint"
ENT.Spawnable = true

ENT.ScreenModel = "models/hunter/plates/plate2x2.mdl"

if SERVER then
    duplicator.RegisterEntityClass( "ent_gpaint_2x2", GPaint.MakeScreenSpawner, "Data" )
end

if CLIENT then
    ENT.IconOverride = "materials/entities/ent_gpaint_base.png"

    list.Set(
        "GPaintScreenOffsets",
        ENT.ScreenModel,
        {
            pos = Vector( -47.3, 47.3, -1.6 ),
            ang = Angle( 0, 270, 0 ),
            scale = Vector( 0.0923, 0.164, 1 )
        }
    )
end