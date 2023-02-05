function GPaint.EnsureDataDir()
    if not file.Exists( "gpaint/", "DATA" ) then
        file.CreateDir( "gpaint/" )
    end

    if not file.Exists( "gpaint/.temp/", "DATA" ) then
        file.CreateDir( "gpaint/.temp/" )
    end
end

-- Render targets cannot be destroyed,
-- therefore we should recycle them.
local rtCache = {}

function GPaint.AllocateRT()
    -- look for free render targets
    for idx, rt in ipairs( rtCache ) do
        if rt.isFree then
            rt.isFree = false

            GPaint.LogF( "RT #%d was recycled", idx )
            return idx, rt.texture
        end
    end

    --[[
        flags I used here, in order:
        - trilinear texture filtering
        - clamp S coordinates
        - clamp T coordinates
        - no mipmaps
        - is a render target (duh)
    ]]
    local flags = bit.bor( 2, 4, 8, 256, 32768 )
    local size = GPaint.rtResolution

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

    GPaint.LogF( "RT #%d was created.", idx )

    return idx, rt.texture
end

function GPaint.FreeRT( idx )
    local rt = rtCache[idx]

    if not rt then
        GPaint.LogF( "Tried to free inexistent render target #%d", idx )

        return
    end

    rt.isFree = true
    GPaint.LogF( "RT #%d is ready for reuse.", idx )
end

local renderCapture = render.Capture

function GPaint.TakeScreenshot( callback )
    local msg = language.GetPhrase( "gpaint.screenshot_hint" )

    hook.Add( "PostRender", "GPaint_TakeScreenshot", function()
        if gui.IsGameUIVisible() then
            hook.Remove( "PostRender", "GPaint_TakeScreenshot" )

        elseif input.IsKeyDown( KEY_E ) then
            hook.Remove( "PostRender", "GPaint_TakeScreenshot" )

            local data = renderCapture{
                format = "png",
                alpha = false,
                x = 0, y = 0,
                w = ScrW(),
                h = ScrH()
            }

            GPaint.EnsureDataDir()

            local path = "gpaint/.temp/screenshot.png"
            file.Write( path, data )
            callback( path )
        end

        cam.Start2D()
        surface.SetFont( "CloseCaption_Bold" )

        surface.SetDrawColor( 255, 0, 0, 200 )
        surface.DrawOutlinedRect( 0, 0, ScrW(), ScrH(), 8 )

        local textW, textH = surface.GetTextSize( msg )
        local x = ( ScrW() * 0.5 ) - ( textW * 0.5 )
        local y = 20

        surface.SetDrawColor( 0, 0, 0, 220 )
        surface.DrawRect( x - 8, y - 8, textW + 16, textH + 16 )

        surface.SetTextColor( 255, 255, 255, 55 + math.abs( math.sin( RealTime() * 4 ) ) * 200 )
        surface.SetTextPos( x, y )
        surface.DrawText( msg )
        cam.End2D()
    end )
end

--[[
    You might ask why am I using a "draw HUD" hook here
    instead of using ENT:Draw from the screen entity itself.

    Its (mostly) because HDR does not affect stuff drawn on this hook.
    In some occasions it was very hard to see the screen on dark/bright rooms...

    Of course, this means I had to manually do rendering
    and tracking of all screens, but hey, it works.
]]

local function getMaxRenderDistanceSqr()
    local cvarRenderDistance = GetConVar( "gpaint_max_render_distance" )
    local value = cvarRenderDistance and cvarRenderDistance:GetFloat() or 3000

    return value * value
end

local IsValid = IsValid
local focusPreventionDelay = 0
local focusedIndex

hook.Add( "PreDrawHUD", "GPaint_DrawScreens", function()
    focusedIndex = nil

    local screens = GPaint.screens
    if #screens == 0 then return end

    local ply = LocalPlayer()
    local eyePos = ply:GetShootPos()
    local renderDistanceSqr = getMaxRenderDistanceSqr()

    -- lets use the trace system to detect
    -- which screen should receive input
    local aimEntity

    if RealTime() > focusPreventionDelay and not vgui.CursorVisible() then
        local tr = util.TraceLine{
            start = eyePos,
            endpos = eyePos + ply:GetAimVector() * 200,
            ignoreworld = true,
            filter = ply
        }

        aimEntity = tr.Entity
    end

    -- lets draw the screens
    cam.Start3D()

    for idx, scr in pairs( screens ) do
        local ent = scr.entity

        if IsValid( ent ) then
            local isVisible = eyePos:DistToSqr( ent:GetPos() ) < renderDistanceSqr

            if isVisible ~= scr.isVisible then
                scr.isVisible = isVisible

                if isVisible then
                    scr:OnShow()
                else
                    scr:OnHide()
                end
            end

            scr:Think()

            if isVisible then
                cam.PushModelMatrix( ent.finalMatrix )
                render.OverrideDepthEnable( true, false )
                render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )

                render.PushFilterMag( TEXFILTER.LINEAR )
                render.PushFilterMin( TEXFILTER.LINEAR )

                --local ok, err = xpcall(scr.Render, debug.traceback, scr)
                --if not ok then print(err) end
                scr:Render()

                render.PopFilterMin()
                render.PopFilterMag()

                render.OverrideBlend( false )
                render.OverrideDepthEnable( false )
                cam.PopModelMatrix()
            end

            local x, y

            if ent == aimEntity then
                x, y = ent:GetCursorPos( ply )

                -- prevent going off screen
                if not scr:IsInside( x, y ) then
                    x = nil
                end
            end

            if x then
                scr.isFocused = true
                scr:OnCursor( x, y )
                focusedIndex = idx

            elseif scr.isFocused then
                scr.isFocused = false
                scr:OnUnfocus()
            end
        else
            scr:Cleanup()
            screens[idx] = nil
        end
    end

    cam.End3D()
end )

-- block interaction with the screens if we hold stuff with the physgun
hook.Add( "PhysgunPickup", "GPaint_PreventFocusing", function( ply )
    if ply == LocalPlayer() then focusPreventionDelay = RealTime() + 999 end
end )

hook.Add( "PhysgunDrop", "GPaint_AllowFocusing", function( ply )
    if ply == LocalPlayer() then focusPreventionDelay = RealTime() + 0.7 end
end )

-- blocks some binds when focusing on any screen
local block_binds = {
    ["+attack"] = true,
    ["+attack2"] = true,
    ["+reload"] = true
}

hook.Add( "PlayerBindPress", "GPaint_BlockBindsWhenFocused", function( _, bind )
    if block_binds[bind] and focusedIndex then return true end
end )

local function GetScreenByEntity( ent )
    for _, scr in pairs( GPaint.screens ) do
        if scr.entity == ent then return scr end
    end
end

local function RenderImageData( scr, data )
    GPaint.EnsureDataDir()

    local path = "gpaint/.temp/net.png"
    file.Write( path, data )

    scr:RenderImageFile( "data/" .. path )
    scr.menu:SetTitle()
    scr.relativeFilePath = nil
    scr.isDirty = false
    scr.isBusy = false
end

local gnet = GPaint.network

net.Receive( "gpaint.command", function()
    local ent = net.ReadEntity()
    if not IsValid( ent ) then return end

    local scr = GetScreenByEntity( ent )
    if not scr then return end

    local cmd = net.ReadUInt( gnet.COMMAND_SIZE )

    if cmd == gnet.CLEAR then
        scr:Clear()

    elseif cmd == gnet.PEN_STROKES then
        local strokes = gnet.ReadStrokes()
        local len = #scr.strokeQueue

        for i, st in ipairs( strokes ) do
            scr.strokeQueue[len + i] = st
        end

    elseif cmd == gnet.BROADCAST_DATA then
        scr.isBusy = true
        scr:Clear()

        gnet.ReadImage( ply, function( data )
            RenderImageData( scr, data )
        end )

    elseif cmd == gnet.AWAIT_DATA then
        scr.isBusy = net.ReadBool()

    elseif cmd == gnet.REQUEST_DATA then
        -- server wants us to send what the screen looks like
        local requestId = net.ReadUInt( 10 )

        if not scr.relativeFilePath and not scr.isDirty then
            -- if we have no image data to send...
            gnet.StartCommand( gnet.SEND_DATA, scr.entity )
            net.WriteUInt( requestId, 10 )
            net.WriteBool( false )
            net.SendToServer()

            return
        end

        local data = scr:CaptureRT( "jpg" )

        if gnet.USE_EXPRESS then
            express.Send(
                "gpaint.transfer",
                {
                    requestId = requestId,
                    ent = scr.entity,
                    image = data
                }
            )

            return
        end

        gnet.StartCommand( gnet.SEND_DATA, scr.entity )
        net.WriteUInt( requestId, 10 )
        net.WriteBool( true )
        gnet.WriteImage( data )
        net.SendToServer()

    elseif cmd == gnet.SUBSCRIBE then
        -- server wants us to subscribe right away
        scr.wantsToSubscribe = true

    end
end )

gnet.OnExpressLoad = function()
    GPaint.LogF( "Now we\"re using gm_express!" )

    express.Receive( "gpaint.transfer", function( data )
        local ent = data.ent
        if not IsValid( ent ) then return end

        local scr = GetScreenByEntity( ent )
        if scr then
            RenderImageData( scr, data.image )
        end
    end )
end

if game.SinglePlayer() then return end

hook.Add( "OnEntityCreated", "GPaint_NotifyServer", function( ent )
    -- give some time for this entity to completely initialize
    timer.Simple( 0, function()
        if GPaint.IsGPaintScreen( ent ) then
            gnet.StartCommand( gnet.ON_INIT, ent )
            net.SendToServer()
        end
    end )
end )