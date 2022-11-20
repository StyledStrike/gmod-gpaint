local dimensions = {
    w = 1024, h = 576
}

local screenQuad = {
    Vector( 0, 0, 0 ),
    Vector( dimensions.w, 0, 0 ),
    Vector( dimensions.w, dimensions.h, 0 ),
    Vector( 0, dimensions.h, 0 )
}

local rtMaterial = CreateMaterial(
    'mat_gpaint_rt',
    'UnlitGeneric',
    {
        ['$nolod'] = 1,
        ['$ignorez'] = 1,
        ['$vertexcolor'] = 1,
        ['$vertexalpha'] = 1
    }
)

local rtResolution = GPaint.rtResolution

-- Get a position on the render target relative to a position on the screen
local function screenPosToRT( x, y )
    return
        math.floor( ( x / dimensions.w ) * rtResolution ),
        math.floor( ( y / dimensions.h ) * rtResolution )
end

-- Get a position on the screen relative to a position on the render target
local function rtPosToScreen( x, y )
    return
        math.floor( ( x / rtResolution ) * dimensions.w ),
        math.floor( ( y / rtResolution ) * dimensions.h )
end

-- based on a example from https://wiki.facepunch.com/gmod/surface.DrawPoly
local function drawFilledCircle( x, y, radius )
    local cir = { { x = x, y = y } }
    local idx = 1

    -- find the best "quality" for this circle
    local seg = math.Clamp( math.floor( radius / 2 ) * 4, 16, 64 )

    for i = 0, seg do
        local a = math.rad( ( i / seg ) * -360 )

        idx = idx + 1
        cir[idx] = {
            x = x + math.sin( a ) * radius,
            y = y + math.cos( a ) * radius
        }
    end

    cir[idx + 1] = {
        x = x + math.sin( 0 ) * radius,
        y = y + math.cos( 0 ) * radius
    }

    surface.DrawPoly( cir )
end

-- Draws a filled line with the specified thickness. (thanks to Wiremod's EGP code)
-- https://github.com/wiremod/wire/blob/master/lua/entities/gmod_wire_egp/lib/egplib/usefulfunctions.lua#L253
local function drawFilledLine( x1, y1, x2, y2, thickness )
    if thickness <= 1 then
        surface.DrawLine( x1, y1, x2, y2 )
        return
    end

    local radius = thickness * 0.5

    if x1 == x2 and y1 == y2 then
        drawFilledCircle( x1, y1, radius )

        return
    end

    -- start & end points
    drawFilledCircle( x1, y1, radius )
    drawFilledCircle( x2, y2, radius )

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

--[[
    This is a sort-of class to handle the screen
    you see in-game for each GPaint entity.
]]
local Screen = {}

Screen.__index = Screen

GPaint.screens = GPaint.screens or {}

-- Update existing screens on autorefresh
if GPaint.screens then
    for idx, scr in pairs( GPaint.screens ) do
        setmetatable( scr, Screen )
        GPaint.screens[idx] = scr
    end
end

function GPaint.CreateScreen( entity )
    for _, scr in pairs( GPaint.screens ) do
        if scr.entity == entity then return end
    end

    local index, rt = GPaint.AllocateRT()

    local scr = {
        rt = rt,
        rt_index = index,
        entity = entity
    }

    GPaint.screens[index] = scr
    setmetatable( scr, Screen )

    scr:Clear()
    scr.menu = GPaint.CreateMenu( scr )
    scr.menu:SetTitle()

    scr.cursorState = 0
    scr.cursorX = nil
    scr.cursorY = nil

    scr.penColor = Color( 255, 0, 0 )
    scr.penThickness = 4

    scr.lastPenX = 0
    scr.lastPenY = 0
    scr.eraserMode = false

    scr.strokeDelay = 0
    scr.strokeQueue = {}

    scr.transmitDelay = 0
    scr.transmitQueue = {}

    scr.isBusy = true
end

--[[
    Screen "class"
]]

local RealTime = RealTime
local renderCapture = render.Capture
local langGet = language.GetPhrase
local gnet = GPaint.network

function Screen:Cleanup()
    GPaint.FreeRT( self.rt_index )

    self.menu:Cleanup()
end

function Screen:Clear( transmit )
    render.ClearRenderTarget( self.rt, Color( 0, 0, 0, 255 ) )

    self.strokeQueue = {}
    self.transmitQueue = {}

    if transmit and not game.SinglePlayer() then
        gnet.StartCommand( gnet.CLEAR, self.entity )
        net.SendToServer()
    end
end

function Screen:SetPenColor( r, g, b )
    self.penColor = Color( r, g, b )
    self.menu:SetColor( self.penColor )
end

function Screen:OnShow()
    gnet.StartCommand( gnet.SUBSCRIBE, self.entity )
    net.SendToServer()
end

function Screen:OnHide()
    gnet.StartCommand( gnet.UNSUBSCRIBE, self.entity )
    net.SendToServer()

    self.hint = nil
end

-- called from the menu when the user opened a file
function Screen:OnOpenImage( relativePath )
    self.relativeFilePath = relativePath
    self.isDirty = false

    self.menu:SetTitle( self.relativeFilePath )
    self:RenderImageFile( 'data/gpaint/' .. relativePath, true )
end

function Screen:OnPenDrag( x, y, reset, color )
    if self.isBusy then return end

    if reset then
        self.lastPenX = x
        self.lastPenY = y
    end

    if RealTime() > self.strokeDelay then
        local stroke = {
            self.lastPenX,
            self.lastPenY,
            x, y,
            self.penThickness,
            color.r, color.g, color.b
        }

        self.strokeQueue[#self.strokeQueue + 1] = stroke
        self.transmitQueue[#self.transmitQueue + 1] = stroke

        self.lastPenX = x
        self.lastPenY = y
        self.strokeDelay = RealTime() + 0.03
        self.isDirty = true
    end
end

function Screen:OnCursor( x, y )
    if not self.hint then
        self.hint = true
        notification.AddLegacy( langGet( 'gpaint.usage_hint' ), NOTIFY_HINT, 4 )
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

    local penX, penY = screenPosToRT( x, y )

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

        self.cursorX, self.cursorY = rtPosToScreen( penX, penY )
    end

    -- color picker
    self.pickerMode = input.IsKeyDown( KEY_R )

    if self.pickerMode then
        self:RenderToRT( function()
            render.CapturePixels()
            local r, g, b = render.ReadPixel( penX, penY )
            self:SetPenColor( r, g, b )
        end )
    end

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

function Screen:Think()
    -- draws all strokes from the queue into the render target
    if not self.isBusy and self.strokeQueue[1] then
        self:RenderToRT( function()
            render.SetColorMaterial()
            draw.NoTexture()

            for _, st in ipairs( self.strokeQueue ) do
                surface.SetDrawColor( st[6], st[7], st[8], 255 )
                drawFilledLine( st[1], st[2], st[3], st[4], st[5] )
            end
        end )

        table.Empty( self.strokeQueue )
    end

    -- send pen strokes over the network 
    if self.transmitQueue[1] and RealTime() > self.transmitDelay then
        gnet.StartCommand( gnet.PEN_STROKES, self.entity )
        gnet.WriteStrokes( self.transmitQueue )
        net.SendToServer()

        table.Empty( self.transmitQueue )
        self.transmitDelay = RealTime() + 0.3
    end

    if self.isBusy and self.menu.isOpen then
        self.menu:Close()
    end
end

function Screen:Render()
    rtMaterial:SetTexture( '$basetexture', self.rt )

    render.SetMaterial( rtMaterial )
    render.DrawQuad( screenQuad[1], screenQuad[2], screenQuad[3], screenQuad[4] )

    render.SetColorMaterial()
    draw.NoTexture()

    self.menu:Render( dimensions.h )

    if self.busyOverlay then
        surface.SetDrawColor( 0, 0, 0, self.busyOverlay * 255 )
        surface.DrawRect( 0, 0, dimensions.w, dimensions.h )

        if not self.isBusy then
            self.busyOverlay = self.busyOverlay - FrameTime() * 3

            if self.busyOverlay < 0 then
                self.busyOverlay = nil
            end
        end
    end

    if self.isBusy then
        surface.SetFont( 'CloseCaption_Bold' )

        local msg = langGet( 'gpaint.loading' )
        local tw, th = surface.GetTextSize( msg )

        local x = ( dimensions.w * 0.5 ) - ( tw * 0.5 )
        local y = ( dimensions.h * 0.5 ) - ( th * 0.5 )

        surface.SetDrawColor( 77, 49, 128, 200 )
        surface.DrawRect( x - 8, y - 8, tw + 16, th + 16 )

        surface.SetTextColor( 255, 255, 255, math.abs( math.sin( RealTime() * 8 ) ) * 255 )
        surface.SetTextPos( x, y )
        surface.DrawText( msg )

        self.busyOverlay = 1
    end

    if not self.cursorX then return end

    if self.isCursorOnMenu and not self.menu:IsDraggingItem() then
        -- draw a green dot
        surface.SetDrawColor( 50, 50, 50, 220 )
        drawFilledCircle( self.cursorX, self.cursorY, 5 )

        surface.SetDrawColor( 0, 255, 0, 255 )
        drawFilledCircle( self.cursorX, self.cursorY, 4 )
    else
        -- draw the + cursor
        local color = self.eraserMode and color_black or self.penColor

        local w = ( self.penThickness / rtResolution ) * dimensions.w * 0.5
        local h = ( self.penThickness / rtResolution ) * dimensions.h * 0.5
        local x = self.cursorX
        local y = self.cursorY

        surface.SetDrawColor( color.r, color.g, color.b, 255 )
        surface.DrawLine( x - w, y, x + w, y )
        surface.DrawLine( x, y - h, x, y + h )
    end

    if self.pickerMode then
        local color = self.penColor
        local x = self.cursorX
        local y = self.cursorY

        surface.SetDrawColor( 50, 50, 50, 220 )
        drawFilledCircle( x, y, 22 )

        surface.SetDrawColor( color.r, color.g, color.b, 255 )
        drawFilledCircle( x, y, 20 )
    end
end

-- render stuff into the render target using the callback function
function Screen:RenderToRT( func )
    render.PushRenderTarget( self.rt )
    cam.Start2D()

    local ok, err = xpcall( func, debug.traceback )
    if not ok then print( err ) end

    cam.End2D()
    render.PopRenderTarget()
end

-- loads and renders a image file to the render target
function Screen:RenderImageFile( path, transmit )
    self:RenderToRT( function()
        local imageMaterial = Material( '../' .. path )
        imageMaterial:GetTexture( '$basetexture' ):Download()

        render.SetMaterial( imageMaterial )
        render.DrawQuad(
            Vector( 0, 0, 0 ),
            Vector( rtResolution, 0, 0 ),
            Vector( rtResolution, rtResolution, 0 ),
            Vector( 0, rtResolution, 0 )
        )

        if game.SinglePlayer() then
            self.busyOverlay = 1
            self.isBusy = false

            return
        end

        if transmit then
            self.isBusy = true
            local data = self:CaptureRT( 'jpg' )

            gnet.StartCommand( gnet.BROADCAST_DATA, self.entity )
            gnet.WriteImage( data, function() self.isBusy = false end )
            net.SendToServer()
        end
    end )
end

-- captures the render target, and returns the image data
function Screen:CaptureRT( format )
    render.SetRenderTarget( self.rt )

    local data = renderCapture{
        format = format or 'png',
        x = 0, y = 0,
        w = rtResolution,
        h = rtResolution,
        alpha = false
    }

    render.SetRenderTarget()

    return data
end

function Screen:IsInside( x, y )
    if not x then return false end
    if x < 0 or x > dimensions.w then return false end
    if y < 0 or y > dimensions.h then return false end

    return true
end