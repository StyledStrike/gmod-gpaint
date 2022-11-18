local surface = surface
local langGet = language.GetPhrase

local materials = {
    picker = Material( 'gui/colors.png' ),
    saturation = Material( 'vgui/gradient-r' ),
    value = Material( 'vgui/gradient-d' )
}

local colors = {
    highlight = Color( 94, 0, 196 ),
    background = Color( 0, 0, 0, 255 )
}

local function isWithinBox( x, y, bx, by, bw, bh )
    if not x then return false end
    if x < bx or x > bx + bw then return false end
    if y < by or y > by + bh then return false end

    return true
end

local function drawButton( self, _, x, y, hover )
    draw.RoundedBox( 8, x, y, self.w, self.h, hover and colors.highlight or colors.background )
    surface.SetTextPos( x + 10, y + 3 )
    surface.DrawText( self.label )
end

local menuItems = {
    {
        label = langGet( 'gpaint.new' ),
        w = 220, h = 30,
        clickFuncName = 'OnClickNew',
        paint = drawButton
    },
    {
        label = langGet( 'gpaint.save' ),
        w = 220, h = 30,
        clickFuncName = 'OnClickSave',
        paint = drawButton
    },
    {
        label = langGet( 'gpaint.open' ),
        w = 220, h = 30,
        clickFuncName = 'OnClickOpen',
        paint = drawButton
    },
    {
        label = langGet( 'gpaint.screenshot' ),
        w = 220, h = 30,
        clickFuncName = 'OnClickScreenshot',
        paint = drawButton
    },
    {
        label = langGet( 'gpaint.thickness' ),
        w = 220, h = 60,
        max = 200,

        paint = function( self, mn, x, y )
            surface.SetDrawColor( colors.background:Unpack() )
            surface.DrawRect( x, y + 30, self.w, self.h - 30 )

            surface.SetDrawColor( colors.highlight:Unpack() )
            surface.DrawRect( x, y + 30, self.w * ( mn.parent.penThickness / self.max ), self.h - 30 )

            surface.SetTextPos( x, y )
            surface.DrawText( self.label )

            surface.SetTextPos( x + self.w - 55, y )
            surface.DrawText( mn.parent.penThickness .. 'px' )
        end,

        drag = function( self, mn, x, y )
            if y < 30 then return end

            local value = math.Round( ( x / self.w ) * self.max )
            mn.parent.penThickness = math.Clamp( value, 1, self.max )
        end
    },
    {
        label = langGet( 'gpaint.color' ),
        w = 220, h = 200,

        hue = 0,
        value = 0,
        saturation = 1,
        base = Color( 0, 0, 0 ),

        paint = function( self, mn, x, y )
            surface.SetTextPos( x, y )
            surface.DrawText( self.label )

            local penColor = mn.parent.penColor

            surface.SetDrawColor( penColor.r, penColor.g, penColor.b, 255 )
            surface.DrawRect( x + self.w - 20, y + 4, 20, 20 )

            surface.SetDrawColor( 255, 255, 255, 255 )
            surface.DrawOutlinedRect( x + self.w - 20, y + 4, 20, 20, 1 )

            y = y + 32

            local hueWidth = 40
            local pickerHeight = self.h - 32
            local saturationX = x + hueWidth + 8
            local saturationW = self.w - 48

            -- hue
            surface.SetDrawColor( 255, 255, 255, 255 )
            surface.SetMaterial( materials.picker )
            surface.DrawTexturedRect( x, y, hueWidth, pickerHeight )

            -- saturation
            surface.SetDrawColor( self.base.r, self.base.g, self.base.b, 255 )
            surface.DrawRect( saturationX, y, saturationW, pickerHeight )

            surface.SetDrawColor( 255, 255, 255, 255 )
            surface.SetMaterial( materials.saturation )
            surface.DrawTexturedRect( saturationX, y, saturationW, pickerHeight )

            -- value
            surface.SetDrawColor( 0, 0, 0, 255 )
            surface.SetMaterial( materials.value )
            surface.DrawTexturedRect( saturationX, y, saturationW, pickerHeight )
            draw.NoTexture()

            -- selected hue
            surface.SetDrawColor( 255, 255, 255, 255 )
            surface.DrawOutlinedRect( x - 1, y + self.hue * pickerHeight - 2, hueWidth + 2, 3, 1 )

            -- selected saturation / value
            local selectionX = saturationX + ( 1 - self.saturation ) * saturationW
            local selectionY = y + ( 1 - self.value ) * pickerHeight

            surface.DrawCircle( selectionX, selectionY, 2, 0, 0, 0, 255 )
            surface.DrawCircle( selectionX, selectionY, 3, 255, 255, 255, 255 )
        end,

        drag = function( self, mn, x, y )
            local pickerHeight = self.h - 32

            if x < 40 then
                -- hue picker
                self.hue = math.Clamp( ( y - 31 ) / pickerHeight, 0, 1 )

                local colorX = materials.picker:Width() * 0.5
                local colorY = math.Clamp( self.hue * materials.picker:Height(), 0, materials.picker:Height() - 1 )
                local clr = materials.picker:GetColor(colorX, colorY)

                local h = ColorToHSV(clr)
                self.base = HSVToColor(h, 1, 1)

                mn.parent.penColor = HSVToColor( h, self.saturation, self.value )
            else
                -- saturation picker
                local saturationW = self.w - 48
                local relativeX = ( x - 48 ) / saturationW
                local relativeY = ( y - 32 ) / pickerHeight

                self.value = 1 - math.Clamp( relativeY, 0, 1 )
                self.saturation = 1 - math.Clamp( relativeX, 0, 1 )

                local h = ColorToHSV( self.base )
                local clr = HSVToColor( h, self.saturation, self.value )

                mn.parent.penColor = Color( clr.r, clr.g, clr.b )
            end
        end
    }
}

--[[
    This is a sort-of class to handle the "menu"
    you see in-game for each GPaint screen.
]]
local GPaintMenu = {}

GPaintMenu.__index = GPaintMenu

function GPaint.CreateMenu( parent )
    local mn = {
        parent = parent
    }

    setmetatable( mn, GPaintMenu )

    mn.title = ''
    mn.animation = 0

    return mn
end

--[[
    GPaintMenu "class"
]]

function GPaintMenu:Cleanup()
    if IsValid( self.browserFrame ) then
        self.browserFrame:Close()
    end
end

function GPaintMenu:Open()
    self.isOpen = true
    self:SetColor( self.parent.penColor )
end

function GPaintMenu:Close()
    self.isOpen = false
end

function GPaintMenu:SetTitle( title )
    self.title = title or '<unsaved image>'

    if string.len( self.title ) > 35 then
        self.title = '...' .. string.Right( self.title, 32 )
    end
end

function GPaintMenu:IsDraggingItem()
    return self.selection and self.selection.beingDragged
end

function GPaintMenu:SetColor( color )
    local h, s, v = ColorToHSV( color )

    -- update the color picker
    local item = menuItems[6]

    item.base = HSVToColor( h, 1, 1 )
    item.hue = 1 - ( h / 360 )
    item.saturation = s
    item.value = v
end

function GPaintMenu:OnCursor( x, y, pressed, justPressed )
    local selection = self.selection
    if not selection then return end

    local item = menuItems[selection.index]

    if justPressed and item.clickFuncName then
        self[item.clickFuncName]( self )
        self:Close()
    end

    if pressed and item.drag then
        selection.beingDragged = true
        item:drag( self, x - selection.x, y - selection.y )
    else
        selection.beingDragged = false
    end
end

function GPaintMenu:Render( screenHeight )
    self.animation = Lerp( FrameTime() * 15, self.animation, self.isOpen and 1 or 0 )
    if self.animation < 0.01 then return end

    surface.SetAlphaMultiplier( self.animation )

    local w = 240
    local halfWidth = w * 0.5
    local x = - w + ( self.animation * ( w + 8 ) )
    local y = 8

    ---- background
    surface.SetDrawColor( 80, 80, 80, 150 )
    surface.DrawRect( x, y, w, screenHeight - 16 )

    surface.SetTextColor( 255, 255, 255, 255 )
    surface.SetFont( 'Trebuchet18' )

    ---- title
    local textWidth = surface.GetTextSize( self.title )

    surface.SetDrawColor( colors.highlight:Unpack() )
    surface.DrawRect( x, y, w, 30 )

    surface.SetTextPos( x + halfWidth - (textWidth * 0.5), y + 5 )
    surface.DrawText( self.title )

    ---- menu items
    surface.SetFont( 'Trebuchet24' )

    x = x + 8
    y = y + 42

    local c_x, c_y = self.parent.cursorX, self.parent.cursorY
    local selection

    for index, item in ipairs( menuItems ) do
        local hover = isWithinBox( c_x, c_y, x, y, item.w, item.h )
        if hover then
            selection = {
                index = index,
                x = x,
                y = y
            }
        end

        item:paint( self, x, y, hover )
        y = y + item.h + 4
    end

    -- only change what the current selected
    -- item is when the cursor is not being pressed
    if self.parent.cursorState == 0 then
        self.selection = selection
    end

    surface.SetAlphaMultiplier( 1 )
end

function GPaintMenu:OnClickNew()
    if self:UnsavedCheck( 'gpaint.new', self.OnClickNew ) then return end

    self.parent.filePath = nil
    self.parent:Clear( true )
end

function GPaintMenu:OnClickSave()
    local data = self.parent:CaptureRT()

    local function writeFile( path )
        GPaint.EnsureDataDir()

        local dir = string.GetPathFromFilename( path )

        if not file.Exists( dir, 'DATA' ) then
            file.CreateDir( dir )
        end

        file.Write( path, data )

        if file.Exists( path, 'DATA' ) then
            if self then
                self.parent.filePath = path
                self.parent.isDirty = false
            end

            notification.AddLegacy( string.format( langGet( 'gpaint.saved_to' ), path ), NOTIFY_GENERIC, 5 )
        else
            notification.AddLegacy( langGet( 'gpaint.save_failed' ), NOTIFY_ERROR, 5 )
        end
    end

    local path = self.parent.filePath

    if not path then
        local now = os.date( '*t' )
        path = string.format( 'gpaint/%04i_%02i_%02i %02i-%02i-%02i', now.year, now.month, now.day, now.hour, now.min, now.sec )
    end

    if file.Exists( path, 'DATA' ) then
        writeFile( path )
    else
        Derma_StringRequest(
            langGet( 'gpaint.save' ),
            langGet( 'gpaint.enter_name' ),
            path,
            function( newPath )
                newPath = string.Trim( newPath )

                if string.len( newPath ) == 0 then
                    Derma_Message(
                        langGet( 'gpaint.enter_name' ),
                        langGet( 'gpaint.error' ),
                        langGet( 'gpaint.ok' )
                    )

                    return
                end

                if string.Right( newPath, 4 ) ~= '.png' then
                    newPath = newPath .. '.png'
                end

                writeFile( newPath )
            end
        )
    end
end

function GPaintMenu:OnClickOpen()
    if self:UnsavedCheck( 'gpaint.open', self.OnClickOpen ) then return end

    GPaint.EnsureDataDir()

    if IsValid( self.browserFrame ) then
        self.browserFrame:Close()
    end

    local frame = vgui.Create( 'DFrame' )
    frame:SetSize( ScrW() * 0.8, ScrH() * 0.8 )
    frame:SetSizable( true )
    frame:SetDraggable( true )
    frame:Center()
    frame:MakePopup()
    frame:SetTitle( langGet( 'gpaint.open' ) )
    frame:SetIcon( 'materials/icon16/image.png' )
    frame:SetDeleteOnClose( true )

    self.browserFrame = frame

    local browser = vgui.Create( 'DFileBrowser', frame )
    browser:Dock( FILL )
    browser:SetModels( true)
    browser:SetPath( 'GAME' )
    browser:SetBaseFolder( 'data' )
    browser:SetCurrentFolder( 'gpaint' )
    browser:SetOpen( true )
    browser.thumbnailQueue = {}

    function browser.OnSelect( _, path )
        frame:Close()
        self.parent:OnOpenImage( path )
    end

    function browser.OnRightClick( s, path )
        local menu = DermaMenu()

        menu:AddOption(
            langGet( 'gpaint.delete' ),
            function()
                Derma_Query(
                    langGet( 'gpaint.delete_query' ) .. '\n' .. path,
                    langGet( 'gpaint.delete' ),
                    langGet( 'gpaint.yes' ),
                    function()
                        file.Delete( string.sub( path, 6 ) )
                        s:SetCurrentFolder( string.GetPathFromFilename( path ) )
                    end,
                    langGet( 'gpaint.no' )
                )
            end
        )

        menu:Open()
    end

    -- copy/pasted ShowFolder from DFileBrowser,
    -- but modified to show icons instead of a list of names
    function browser.ShowFolder( s, path )
        if not IsValid( s.Files ) then return end

        s.Files:Clear()

        if not path then return end

        local filters = {
            '*.png',
            '*.jpg'
        }

        for _, filter in pairs( filters ) do
            local files = file.Find( string.Trim( path .. '/' .. filter, '/' ), s.m_strPath )
            if not istable( files ) then continue end

            for _, v in pairs( files ) do
                local icon = s.Files:Add( 'DImageButton' )
                icon:SetSize( 180, 180 )
                icon:SetKeepAspect( true )

                -- add this icon panel and path to the thumbnail queue
                s.thumbnailQueue[#s.thumbnailQueue + 1] = {
                    icon, string.format( '../%s/%s', path, v )
                }

                icon.PaintOver = function(_, selfW)
                    surface.SetDrawColor( 0, 0, 0, 200 )
                    surface.DrawRect( 0, 0, selfW, 20 )

                    surface.SetFont( 'Trebuchet18' )
                    surface.SetTextPos( 4, 2 )
                    surface.SetTextColor( 255, 255, 255, 255 )
                    surface.DrawText( v )
                end

                icon.DoClick = function()
                    s.OnSelect( s, path .. '/' .. v, icon )
                end

                icon.DoRightClick = function()
                    s.OnRightClick( s, path .. '/' .. v, icon )
                end
            end
        end
    end

    function browser.Think( s )
        if not s.thumbnailQueue or not s.thumbnailQueue[1] then return end

        local item = table.remove( s.thumbnailQueue, 1 )
        local panel, path = item[1], item[2]

        if not IsValid( panel ) then return end

        panel:SetImage( path )

        local tex = panel.m_Image.m_Material:GetTexture( '$basetexture' )
        if IsValid( tex ) then tex:Download() end
    end
end

function GPaintMenu:OnClickScreenshot()
    if self:UnsavedCheck( 'gpaint.screenshot', self.OnClickScreenshot ) then return end

    GPaint.TakeScreenshot( function( path )
        self.parent.filePath = nil
        self.parent.isDirty = true
        self.parent:RenderImageFile( 'data/' .. path, true )
    end )
end

-- if we have unsaved stuff, display a dialog to confirm the user's intent
function GPaintMenu:UnsavedCheck( title, callback )
    if self.parent.isDirty then
        Derma_Query(
            langGet( 'gpaint.unsaved_changes' ),
            langGet( title ),
            langGet( 'gpaint.yes' ),
            function()
                self.parent.isDirty = false
                callback( self )
            end,
            langGet( 'gpaint.no' )
        )

        return true
    end

    return false
end