AddCSLuaFile()

ENT.Type = 'anim'
ENT.Base = 'ent_gpaint_base'

ENT.PrintName = 'GPaint (Painting)'
ENT.Category = 'GPaint'
ENT.Spawnable = true

ENT.model = 'models/maxofs2d/gm_painting.mdl'
ENT.spawnAngleOffset = Angle( -90, 180, 0 )

if CLIENT then
    ENT.IconOverride = 'materials/entities/ent_gpaint_painting.png'

    list.Set(
        'GPaintScreenOffsets',
        ENT.model,
        {
            pos = Vector( 1, -30.1, 16.3 ),
            ang = Angle( 180, 270, 90 ),
            scale = Vector( 0.059, 0.056, 1 )
        }
    )
end