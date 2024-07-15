GPaint.screens = GPaint.screens or {}

function GPaint.EnsureDataDir()
    if not file.Exists( "gpaint/", "DATA" ) then
        file.CreateDir( "gpaint/" )
    end

    if not file.Exists( "gpaint/.temp/", "DATA" ) then
        file.CreateDir( "gpaint/.temp/" )
    end
end

function GPaint.GetScreenByEntity( ent )
    return GPaint.screens[ent:EntIndex()]
end

-- Render targets cannot be destroyed,
-- therefore we should recycle them.
local rtCache = GPaint.rtCache or {}

GPaint.rtCache = rtCache

function GPaint.AllocateRT()
    -- Look for free render targets
    for idx, rt in ipairs( rtCache ) do
        if rt.isFree then
            rt.isFree = false

            GPaint.PrintF( "RT #%d was recycled", idx )
            return idx, rt.texture
        end
    end

    --[[
        Flags used here, in order:
        - Trilinear texture filtering
        - Clamp S coordinates
        - Clamp T coordinates
        - No mipmaps
        - No LODs (not affected by texture quality settings)
        - Is a render target (duh)
    ]]
    local flags = bit.bor( 2, 4, 8, 256, 512, 32768 )
    local size = GPaint.RT_SIZE

    local rt = { isFree = false }
    local idx = #rtCache + 1

    rtCache[idx] = rt

    rt.texture = GetRenderTargetEx(
        "gpaint_rt_" .. idx,
        size, size,
        RT_SIZE_OFFSCREEN,
        MATERIAL_RT_DEPTH_NONE,
        flags, 0,
        IMAGE_FORMAT_BGRA8888
    )

    GPaint.PrintF( "RT #%d was created.", idx )

    return idx, rt.texture
end

function GPaint.FreeRT( idx )
    local rt = rtCache[idx]

    if not rt then
        GPaint.PrintF( "Tried to free inexistent render target #%d", idx )

        return
    end

    rt.isFree = true
    GPaint.PrintF( "RT #%d is ready for reuse.", idx )
end

function GPaint.TakeScreenshot( callback, format )
    local text = language.GetPhrase( "gpaint.screenshot_hint" )

    hook.Add( "OnPauseMenuShow", "GPaint.TakeScreenshot", function()
        hook.Remove( "OnPauseMenuShow", "GPaint.TakeScreenshot" )
        hook.Remove( "PostRender", "GPaint.TakeScreenshot" )
        return false
    end )

    hook.Add( "PostRender", "GPaint.TakeScreenshot", function()
        if input.IsKeyDown( KEY_E ) then
            hook.Remove( "OnPauseMenuShow", "GPaint.TakeScreenshot" )
            hook.Remove( "PostRender", "GPaint.TakeScreenshot" )

            local data = render.Capture( {
                format = format or "png",
                alpha = false,
                x = 0, y = 0,
                w = ScrW(),
                h = ScrH()
            } )

            GPaint.EnsureDataDir()

            local path = "gpaint/.temp/screenshot.png"
            file.Write( path, data )
            callback( path )
        end

        cam.Start2D()
        surface.SetFont( "CloseCaption_Bold" )

        surface.SetDrawColor( 255, 0, 0, 200 )
        surface.DrawOutlinedRect( 0, 0, ScrW(), ScrH(), 8 )

        local textW, textH = surface.GetTextSize( text )
        local x = ( ScrW() * 0.5 ) - ( textW * 0.5 )
        local y = 20

        surface.SetDrawColor( 0, 0, 0, 220 )
        surface.DrawRect( x - 8, y - 8, textW + 16, textH + 16 )

        surface.SetTextColor( 255, 255, 255, 55 + math.abs( math.sin( RealTime() * 4 ) ) * 200 )
        surface.SetTextPos( x, y )
        surface.DrawText( text )
        cam.End2D()
    end )
end

local Rad = math.rad
local Sin = math.sin
local Cos = math.cos
local Floor = math.floor
local Clamp = math.Clamp

-- Based on a example from https://wiki.facepunch.com/gmod/surface.DrawPoly
function GPaint.DrawFilledCircle( x, y, radius )
    local cir = { { x = x, y = y } }
    local idx = 1

    -- find the best "quality" for this circle
    local seg = Clamp( Floor( radius / 2 ) * 4, 16, 64 )

    for i = 0, seg do
        local a = Rad( ( i / seg ) * -360 )

        idx = idx + 1
        cir[idx] = {
            x = x + Sin( a ) * radius,
            y = y + Cos( a ) * radius
        }
    end

    cir[idx + 1] = {
        x = x + Sin( 0 ) * radius,
        y = y + Cos( 0 ) * radius
    }

    surface.DrawPoly( cir )
end

local DrawFilledCircle = GPaint.DrawFilledCircle

-- Draws a filled line with the specified thickness. (thanks to Wiremod"s EGP code)
-- https://github.com/wiremod/wire/blob/master/lua/entities/gmod_wire_egp/lib/egplib/usefulfunctions.lua#L253
function GPaint.DrawFilledLine( x1, y1, x2, y2, thickness )
    if thickness <= 1 then
        surface.DrawLine( x1, y1, x2, y2 )
        return
    end

    local radius = thickness * 0.5

    if x1 == x2 and y1 == y2 then
        DrawFilledCircle( x1, y1, radius )

        return
    end

    -- start & end points
    DrawFilledCircle( x1, y1, radius )
    DrawFilledCircle( x2, y2, radius )

    -- fake a line by drawing a rotated rectange

    -- calculate position
    local x3 = ( x1 + x2 ) * 0.5
    local y3 = ( y1 + y2 ) * 0.5

    -- calculate width & angle
    local w = math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 )
    local angle = math.deg( math.atan2( y1 - y2, x2 - x1 ) )
    if w < 1 then w = 1 end

    draw.NoTexture()
    surface.DrawTexturedRectRotated( x3, y3, w, thickness, angle )
end
