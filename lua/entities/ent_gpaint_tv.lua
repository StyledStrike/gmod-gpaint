AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ent_gpaint_base"

ENT.PrintName = "GPaint (TV)"
ENT.Category = "GPaint"
ENT.Spawnable = true

ENT.model = "models/props_phx/rt_screen.mdl"
ENT.spawnAngleOffset = Angle( -90, 180, 0 )

if CLIENT then
    ENT.IconOverride = "materials/entities/ent_gpaint_tv.png"

    list.Set(
        "GPaintScreenOffsets",
        ENT.model,
        {
            pos = Vector( 6.1, -28.1, 35.45 ),
            ang = Angle( 180, 270, 90 ),
            scale = Vector( 0.055, 0.0575, 1 )
        }
    )
end