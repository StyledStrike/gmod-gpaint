AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ent_gpaint_base"

ENT.PrintName = "GPaint (0.75x0.75)"
ENT.Category = "GPaint"
ENT.Spawnable = true

ENT.ScreenModel = "models/hunter/plates/plate075x075.mdl"

if SERVER then
    duplicator.RegisterEntityClass( "ent_gpaint_075x075", GPaint.MakeScreenSpawner, "Data" )
end

if CLIENT then
    ENT.IconOverride = "materials/entities/ent_gpaint_base.png"

    list.Set(
        "GPaintScreenOffsets",
        ENT.ScreenModel,
        {
            pos = Vector( -23.73, 11.6, -1.6 ),
            ang = Angle( 0, 270, 0 ),
            scale = Vector( 0.0344, 0.0615, 1 )
        }
    )
end