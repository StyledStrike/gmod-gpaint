AddCSLuaFile()

ENT.Type = 'anim'
ENT.Base = 'ent_gpaint_base'

ENT.PrintName = 'GPaint (0.75x1)'
ENT.Category = 'GPaint'
ENT.Spawnable = true

ENT.model = 'models/hunter/plates/plate075x1.mdl'

if CLIENT then
    ENT.IconOverride = 'materials/entities/ent_gpaint_base.png'

    list.Set(
        'GPaintScreenOffsets',
        ENT.model,
        {
            pos = Vector( -23.73, 23.7, -1.6 ),
            ang = Angle( 0, 270, 0 ),
            scale = Vector( 0.0463, 0.0617, 1 )
        }
    )
end