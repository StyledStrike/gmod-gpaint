AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ent_gpaint_base"

ENT.PrintName = "GPaint (1x1)"
ENT.Category = "GPaint"
ENT.Spawnable = true

ENT.ScreenModel = "models/hunter/plates/plate1x1.mdl"

if SERVER then
    duplicator.RegisterEntityClass( "ent_gpaint_1x1", GPaint.MakeScreenSpawner, "Data" )
end

if CLIENT then
    ENT.IconOverride = "materials/entities/ent_gpaint_base.png"

    list.Set(
        "GPaintScreenOffsets",
        ENT.ScreenModel,
        {
            pos = Vector( -23.73, 23.6, -1.6 ),
            ang = Angle( 0, 270, 0 ),
            scale = Vector( 0.046, 0.082, 1 )
        }
    )
end