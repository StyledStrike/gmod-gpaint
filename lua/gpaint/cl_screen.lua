local SCREEN_W = 1024
local SCREEN_H = 576
local RT_SIZE = GPaint.RT_SIZE

local Floor = math.floor

-- Get a position on the render target relative to a position on the screen
local function ScreenToRT( x, y )
    return
        Floor( ( x / SCREEN_W ) * RT_SIZE ),
        Floor( ( y / SCREEN_H ) * RT_SIZE )
end

-- Get a position on the screen relative to a position on the render target
local function RTToScreen( x, y )
    return
        Floor( ( x / RT_SIZE ) * SCREEN_W ),
        Floor( ( y / RT_SIZE ) * SCREEN_H )
end

local DrawFilledCircle = GPaint.DrawFilledCircle
local DrawFilledLine = GPaint.DrawFilledLine

local L = language.GetPhrase
local RealTime = RealTime

--[[
    This is a sort-of class to handle the screen
    you see in-game for each GPaint entity.
]]
local Screen = GPaint.Screen or {}

GPaint.Screen = Screen
Screen.__index = Screen

function GPaint.CreateScreen( ent )
    local id = ent:EntIndex()
    if GPaint.screens[id] then return end

    local index, rt = GPaint.AllocateRT()

    local s = setmetatable( {
        id = id,
        rt = rt,
        rtIndex = index,
        entity = ent,

        isFocused = false,
        cursorState = 0,
        cursorX = nil,
        cursorY = nil,

        penColor = Color( 255, 0, 0 ),
        penThickness = 4,

        lastPenX = 0,
        lastPenY = 0,
        eraserMode = false,

        strokeDelay = 0,
        strokeQueue = {},

        transmitDelay = 0,
        transmitQueue = {},

        isLoading = false,
        isSubscribed = false
    }, Screen )

    s:Clear()
    s.menu = GPaint.CreateMenu( s )
    s.menu:SetTitle()

    GPaint.screens[id] = s
    GPaint.UpdateScreenCount()

    if game.SinglePlayer() then
        s.isSubscribed = true
        s.isLoading = false
    end
end

function Screen:Remove()
    self.menu:Remove()

    GPaint.FreeRT( self.rtIndex )
    GPaint.UpdateScreenCount()
end

function Screen:Subscribe()
    if self.isSubscribed then return end

    self.isSubscribed = true
    self.isLoading = true

    GPaint.StartCommand( GPaint.SUBSCRIBE, self.entity )
    net.SendToServer()
end

function Screen:Unsubscribe()
    if not self.isSubscribed then return end

    self.isSubscribed = false
    self.isLoading = false

    GPaint.StartCommand( GPaint.UNSUBSCRIBE, self.entity )
    net.SendToServer()
end

function Screen:Clear( transmit )
    render.ClearRenderTarget( self.rt, Color( 0, 0, 0, 255 ) )

    self.strokeQueue = {}
    self.transmitQueue = {}

    if transmit and not game.SinglePlayer() then
        GPaint.StartCommand( GPaint.CLEAR, self.entity )
        net.SendToServer()
    end
end

function Screen:SetPenColor( r, g, b )
    self.penColor = Color( r, g, b )
    self.menu:SetPenColor( self.penColor )
end

function Screen:IsInside( x, y )
    if not x then return false end
    if x < 0 or x > SCREEN_W then return false end
    if y < 0 or y > SCREEN_H then return false end

    return true
end

--- Called from the menu when the user opened a file.
--- `path` is relative to the `garrysmod\data` directory.
function Screen:OnOpenImage( path )
    if not self.entity:CanPlayerDraw( LocalPlayer() ) then return end

    self.path = path
    self.menu.isUnsaved = false
    self.menu:SetTitle( path )
    self:RenderImageFile( path, true )
end

function Screen:OnPenDrag( x, y, reset, color )
    if self.isLoading then return end

    if reset then
        self.lastPenX = x
        self.lastPenY = y
    end

    if RealTime() < self.strokeDelay then return end

    self.menu.isUnsaved = true
    self.strokeDelay = RealTime() + 0.03

    local stroke = {
        self.lastPenX,
        self.lastPenY,
        x, y,
        self.penThickness,
        color.r, color.g, color.b
    }

    self.lastPenX = x
    self.lastPenY = y

    -- Render this stoke next frame
    self.strokeQueue[#self.strokeQueue + 1] = stroke

    if game.SinglePlayer() then return end

    -- Transmit the stroke soon
    self.transmitQueue[#self.transmitQueue + 1] = stroke
end

function Screen:OnCursor( x, y )
    if not self.isSubscribed and not self.isLoading and input.IsKeyDown( KEY_E ) then
        self:Subscribe()
    end

    if self.isLoading then return end
    if not self.entity:CanPlayerDraw( LocalPlayer() ) then return end

    if not self.hint then
        self.hint = true
        notification.AddLegacy( L"gpaint.usage_hint", NOTIFY_HINT, 4 )
    end

    local cursorLeft = input.IsMouseDown( MOUSE_LEFT )
    local cursorRight = input.IsMouseDown( MOUSE_RIGHT )

    self.eraserMode = input.IsKeyDown( KEY_LALT )

    local newState = 0
    local resetPen = false

    if cursorLeft then newState = 1 end
    if cursorRight then newState = 2 end

    if newState ~= self.cursorState then
        self.cursorState = newState
        resetPen = newState == 1
    end

    local penX, penY = ScreenToRT( x, y )

    if newState == 0 then
        self.isCursorOnMenu = self.menu.isOpen and x < 250
    end

    if self.isCursorOnMenu then
        self.cursorX, self.cursorY = x, y

        if self.menu.isOpen then
            self.menu:OnCursor( x, y, cursorLeft, resetPen )
        end
    else
        penX = math.Round( penX )
        penY = math.Round( penY )

        if newState > 0 then
            self:OnPenDrag( penX, penY, resetPen, self.eraserMode and color_black or self.penColor )
        end

        self.cursorX, self.cursorY = RTToScreen( penX, penY )
    end

    -- Color picker
    self.usingColorPicker = input.IsKeyDown( KEY_R )

    if self.usingColorPicker then
        self:RenderToRT( function()
            render.CapturePixels()
            local r, g, b = render.ReadPixel( penX, penY )
            self:SetPenColor( r, g, b )
        end )
    end

    -- Menu toggle
    if LocalPlayer():KeyDown( IN_USE ) then
        if not self.holdingMenuKey then
            self.holdingMenuKey = true

            if self.menu.isOpen then
                self.menu:Close()
            else
                self.menu:Open()
            end
        end
    else
        self.holdingMenuKey = nil
    end
end

function Screen:OnUnfocus()
    self.menu:Close()

    self.cursorState = 0
    self.cursorX = nil
    self.cursorY = nil

    self.eraserMode = false
end

local SetDrawColor = surface.SetDrawColor

function Screen:Think()
    -- Draws all strokes from the queue into the render target
    if not self.isLoading and self.strokeQueue[1] then
        self:RenderToRT( function()
            render.SetColorMaterial()
            draw.NoTexture()

            for _, st in ipairs( self.strokeQueue ) do
                SetDrawColor( st[6], st[7], st[8], 255 )
                DrawFilledLine( st[1], st[2], st[3], st[4], st[5] )
            end
        end )

        table.Empty( self.strokeQueue )
    end

    -- Send pen strokes over the network 
    if self.transmitQueue[1] and RealTime() > self.transmitDelay then
        GPaint.StartCommand( GPaint.PEN_STROKES, self.entity )
        GPaint.WriteStrokes( self.transmitQueue )
        net.SendToServer()

        table.Empty( self.transmitQueue )
        self.transmitDelay = RealTime() + 0.3
    end

    if self.isLoading and self.menu.isOpen then
        self.menu:Close()
    end
end

local screenQuad = {
    Vector( 0, 0, 0 ),
    Vector( SCREEN_W, 0, 0 ),
    Vector( SCREEN_W, SCREEN_H, 0 ),
    Vector( 0, SCREEN_H, 0 )
}

local screenMat = CreateMaterial(
    "mat_gpaint_rt",
    "UnlitGeneric",
    {
        ["$nolod"] = 1,
        ["$ignorez"] = 1,
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1
    }
)

local DrawRect = surface.DrawRect

function Screen:Render()
    screenMat:SetTexture( "$basetexture", self.rt )

    render.SetMaterial( screenMat )
    render.DrawQuad( screenQuad[1], screenQuad[2], screenQuad[3], screenQuad[4] )

    render.SetColorMaterial()
    draw.NoTexture()

    self.menu:Render( SCREEN_H )

    if self.busyOverlay then
        SetDrawColor( 0, 0, 0, self.busyOverlay * 255 )
        DrawRect( 0, 0, SCREEN_W, SCREEN_H )

        if not self.isLoading then
            self.busyOverlay = self.busyOverlay - FrameTime() * 3

            if self.busyOverlay < 0 then
                self.busyOverlay = nil
            end
        end
    end

    if self.isLoading then
        surface.SetFont( "CloseCaption_Bold" )

        local text = L"gpaint.loading"
        local tw, th = surface.GetTextSize( text )

        local x = ( SCREEN_W * 0.5 ) - ( tw * 0.5 )
        local y = ( SCREEN_H * 0.5 ) - ( th * 0.5 )

        SetDrawColor( 77, 49, 128, 200 )
        DrawRect( x - 8, y - 8, tw + 16, th + 16 )

        surface.SetTextColor( 255, 255, 255, math.abs( math.sin( RealTime() * 8 ) ) * 255 )
        surface.SetTextPos( x, y )
        surface.DrawText( text )

        self.busyOverlay = 1
    end

    if not self.isSubscribed and not self.isLoading then
        surface.SetFont( "CloseCaption_Bold" )

        local text = L"gpaint.enable_request"
        local tw, th = surface.GetTextSize( text )

        local x = ( SCREEN_W * 0.5 ) - ( tw * 0.5 )
        local y = ( SCREEN_H * 0.5 ) - ( th * 0.5 )

        SetDrawColor( 40, 40, 40, 255 )
        DrawRect( x - 8, y - 8, tw + 16, th + 16 )

        surface.SetTextColor( 255, 255, 255, 255 )
        surface.SetTextPos( x, y )
        surface.DrawText( text )
    end

    if not self.cursorX then return end

    if self.isCursorOnMenu and not self.menu:IsDraggingItem() then
        -- Draw a green dot
        SetDrawColor( 50, 50, 50, 220 )
        DrawFilledCircle( self.cursorX, self.cursorY, 5 )

        SetDrawColor( 0, 255, 0, 255 )
        DrawFilledCircle( self.cursorX, self.cursorY, 4 )
    else
        -- Draw a "+" sign
        local color = self.eraserMode and color_black or self.penColor

        local w = ( self.penThickness / RT_SIZE ) * SCREEN_W * 0.5
        local h = ( self.penThickness / RT_SIZE ) * SCREEN_H * 0.5
        local x = self.cursorX
        local y = self.cursorY

        SetDrawColor( color.r, color.g, color.b, 255 )
        surface.DrawLine( x - w, y, x + w, y )
        surface.DrawLine( x, y - h, x, y + h )
    end

    -- Draw a circle with the current color from the color picker
    if self.usingColorPicker then
        local color = self.penColor
        local x = self.cursorX
        local y = self.cursorY

        SetDrawColor( 50, 50, 50, 220 )
        DrawFilledCircle( x, y, 22 )

        SetDrawColor( color.r, color.g, color.b, 255 )
        DrawFilledCircle( x, y, 20 )
    end
end

--- Captures the render target's contents and returns the image data.
function Screen:CaptureRT( format )
    render.SetRenderTarget( self.rt )

    local data = render.Capture( {
        format = format or "png",
        x = 0, y = 0,
        w = RT_SIZE,
        h = RT_SIZE,
        alpha = false
    } )

    render.SetRenderTarget()

    return data
end

--- Render stuff into the render target using `func`.
function Screen:RenderToRT( func )
    render.PushRenderTarget( self.rt )
    cam.Start2D()

    local ok, err = xpcall( func, debug.traceback )
    if not ok then print( err ) end

    cam.End2D()
    render.PopRenderTarget()
end

--- Loads and renders a image file on the render target.
--- `path` is relative to the `garrysmod\data` directory.
function Screen:RenderImageFile( path, transmit )
    local entId = self.entity:EntIndex()

    self:RenderToRT( function()
        local imageMaterial = Material( "../data/" .. path )
        imageMaterial:GetTexture( "$basetexture" ):Download()

        render.SetMaterial( imageMaterial )
        render.DrawQuad(
            Vector( 0, 0, 0 ),
            Vector( RT_SIZE, 0, 0 ),
            Vector( RT_SIZE, RT_SIZE, 0 ),
            Vector( 0, RT_SIZE, 0 )
        )

        if game.SinglePlayer() then
            self.busyOverlay = 1
            self.isLoading = false

            return
        end

        if transmit then
            self.isLoading = true

            local data = self:CaptureRT( "jpg" )

            GPaint.Transfer( data, { gpaint_entId = entId }, function( err )
                self.isLoading = false

                if err then
                    GPaint.PrintF( "Failed to stream image file: %s (%s)", path, err )
                else
                    GPaint.PrintF( "Streamed image file to the server." )
                end
            end )
        end
    end )
end

--[[
    You might ask why am I using a `PreDrawHUD` hook here
    instead of using `ENT:Draw` from the screen entity itself.

    It's (mostly) because HDR does not affect stuff drawn on this hook.
    In some occasions it was very hard to see the screen on dark/bright rooms...
]]

local focusedId, localPly

local function ProcessScreen( s, isAiming )
    cam.PushModelMatrix( s.entity.screenMatrix )
    render.OverrideDepthEnable( true, false )
    render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )

    render.PushFilterMag( TEXFILTER.LINEAR )
    render.PushFilterMin( TEXFILTER.LINEAR )

    s:Render()

    render.PopFilterMin()
    render.PopFilterMag()

    render.OverrideBlend( false )
    render.OverrideDepthEnable( false )
    cam.PopModelMatrix()

    local x, y

    if isAiming then
        x, y = s.entity:GetCursorPos( localPly )

        if not s:IsInside( x, y ) then
            x = nil
        end
    end

    if x then
        s.isFocused = true
        s:OnCursor( x, y )
        focusedId = s.id

    elseif s.isFocused then
        s.isFocused = false
        s:OnUnfocus()
    end
end

local function GetMaxRenderDistance()
    local cvar = GetConVar( "gpaint_max_render_distance" )
    local value = cvar and cvar:GetInt() or 3000
    return value * value
end

local IsValid = IsValid
local LocalPlayer = LocalPlayer

local screens = GPaint.screens
local focusCooldown = 0

function GPaint.DrawScreens()
    focusedId = nil
    localPly = LocalPlayer()

    local eyePos = localPly:GetShootPos()
    local maxDistance = GetMaxRenderDistance()

    -- Use the trace system to detect
    -- which screen should receive input
    local aimEntity

    if RealTime() > focusCooldown and not vgui.CursorVisible() then
        local tr = util.TraceLine{
            start = eyePos,
            endpos = eyePos + localPly:GetAimVector() * 200,
            ignoreworld = true,
            filter = localPly
        }

        aimEntity = tr.Entity
    end

    -- Draw the screens
    cam.Start3D()

    for id, s in pairs( screens ) do
        local ent = s.entity

        if IsValid( ent ) then
            s:Think()

            if not ent:IsDormant() and eyePos:DistToSqr( ent:GetPos() ) < maxDistance then
                ProcessScreen( s, ent == aimEntity )
            end
        else
            s:Remove()
            screens[id] = nil
        end
    end

    cam.End3D()
end

function GPaint.UpdateScreenCount()
    local count = table.Count( screens )

    if count == 0 then
        hook.Remove( "PreDrawHUD", "GPaint.DrawScreens" )
    else
        hook.Add( "PreDrawHUD", "GPaint.DrawScreens", GPaint.DrawScreens )
    end
end

GPaint.UpdateScreenCount()

-- Block interaction with the screens if we hold stuff with the physgun
hook.Add( "PhysgunPickup", "GPaint.PreventFocusing", function( ply )
    if ply == LocalPlayer() then focusCooldown = RealTime() + 999 end
end )

hook.Add( "PhysgunDrop", "GPaint.AllowFocusing", function( ply )
    if ply == LocalPlayer() then focusCooldown = RealTime() + 0.7 end
end )

-- Blocks some binds when focusing on any screen
local blockBinds = {
    ["+attack"] = true,
    ["+attack2"] = true,
    ["+reload"] = true
}

hook.Add( "PlayerBindPress", "GPaint.BlockBindsWhenFocused", function( _, bind )
    if blockBinds[bind] and focusedId then return true end
end )
