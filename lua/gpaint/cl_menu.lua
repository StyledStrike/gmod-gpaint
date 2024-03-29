local surface = surface
local langGet = language.GetPhrase

local materials = {
    picker = Material( "gui/colors.png" ),
    saturation = Material( "vgui/gradient-r" ),
    value = Material( "vgui/gradient-d" )
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
        id = "new",
        label = langGet( "gpaint.new" ),
        w = 220, h = 30,
        clickFuncName = "OnClickNew",
        paint = drawButton
    },
    {
        id = "save",
        label = langGet( "gpaint.save" ),
        w = 220, h = 30,
        clickFuncName = "OnClickSave",
        paint = drawButton
    },
    {
        id = "saveas",
        label = langGet( "gpaint.saveas" ),
        w = 220, h = 30,
        clickFuncName = "OnClickSaveAs",
        paint = drawButton
    },
    {
        id = "open",
        label = langGet( "gpaint.open" ),
        w = 220, h = 30,
        clickFuncName = "OnClickOpen",
        paint = drawButton
    },
    {
        id = "screenshot",
        label = langGet( "gpaint.screenshot" ),
        w = 220, h = 30,
        clickFuncName = "OnClickScreenshot",
        paint = drawButton
    },
    {
        id = "share",
        label = langGet( "gpaint.share_screen" ),
        w = 220, h = 30,
        clickFuncName = "OnClickShare",
        paint = drawButton
    },
    {
        id = "thickness",
        label = langGet( "gpaint.thickness" ),
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
            surface.DrawText( mn.parent.penThickness .. "px" )
        end,

        drag = function( self, mn, x, y )
            if y < 30 then return end

            local value = math.Round( ( x / self.w ) * self.max )
            mn.parent.penThickness = math.Clamp( value, 1, self.max )
        end
    },
    {
        id = "color",
        label = langGet( "gpaint.color" ),
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
                local clr = materials.picker:GetColor( colorX, colorY )

                local h = ColorToHSV( clr )
                self.base = HSVToColor( h, 1, 1 )

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

local function GetItemByID( id )
    for _, item in ipairs( menuItems ) do
        if item.id == id then return item end
    end
end

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

    mn.title = ""
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

    if IsValid( self.shareFrame ) then
        self.shareFrame:Close()
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
    self.title = title or "<unsaved image>"

    if string.len( self.title ) > 35 then
        self.title = "..." .. string.Right( self.title, 32 )
    end
end

function GPaintMenu:IsDraggingItem()
    return self.selection and self.selection.beingDragged
end

function GPaintMenu:SetColor( color )
    local h, s, v = ColorToHSV( color )

    -- update the color picker
    local item = GetItemByID( "color" )

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
    surface.SetFont( "Trebuchet18" )

    ---- title
    local textWidth = surface.GetTextSize( self.title )

    surface.SetDrawColor( colors.highlight:Unpack() )
    surface.DrawRect( x, y, w, 30 )

    surface.SetTextPos( x + halfWidth - ( textWidth * 0.5 ), y + 5 )
    surface.DrawText( self.title )

    ---- menu items
    surface.SetFont( "Trebuchet24" )

    x = x + 8
    y = y + 42

    local cX, cY = self.parent.cursorX, self.parent.cursorY
    local selection

    for index, item in ipairs( menuItems ) do
        local hover = isWithinBox( cX, cY, x, y, item.w, item.h )
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
    if self:UnsavedCheck( "#gpaint.new", self.OnClickNew ) then return end

    self.parent.relativeFilePath = nil
    self.parent:Clear( true )
end

function GPaintMenu:OnClickSave( forceNew )
    local data = self.parent:CaptureRT()

    local function writeFile( path )
        GPaint.EnsureDataDir()

        local dir = string.GetPathFromFilename( path )

        if not file.Exists( dir, "DATA" ) then
            file.CreateDir( dir )
        end

        file.Write( path, data )

        if file.Exists( path, "DATA" ) then
            if self then
                self.parent.relativeFilePath = string.sub( path, 8 ) -- remove "gpaint/"
                self.parent.isDirty = false

                self:SetTitle( self.parent.relativeFilePath )
            end

            notification.AddLegacy( string.format( langGet( "gpaint.saved_to" ), path ), NOTIFY_GENERIC, 5 )
        else
            notification.AddLegacy( langGet( "gpaint.save_failed" ), NOTIFY_ERROR, 5 )
        end
    end

    local relativePath = self.parent.relativeFilePath

    if not relativePath or forceNew then
        local now = os.date( "*t" )
        relativePath = string.format( "%04i_%02i_%02i %02i-%02i-%02i", now.year, now.month, now.day, now.hour, now.min, now.sec )
    end

    local fullPath = "gpaint/" .. relativePath

    if file.Exists( fullPath, "DATA" ) then
        writeFile( fullPath )
    else
        Derma_StringRequest(
            "#gpaint.save",
            "#gpaint.enter_name",
            relativePath,
            function( result )
                relativePath = string.Trim( result )

                if string.len( relativePath ) == 0 then
                    Derma_Message( "#gpaint.enter_name", "#gpaint.error", "#gpaint.ok" )

                    return
                end

                local ext = string.Right( relativePath, 4 )

                if ext ~= ".png" and ext ~= ".jpg" then
                    relativePath = relativePath .. ".png"
                end

                fullPath = "gpaint/" .. relativePath

                writeFile( fullPath )
            end
        )
    end
end

function GPaintMenu:OnClickSaveAs()
    self:OnClickSave( true )
end

function GPaintMenu:OnClickOpen()
    if self:UnsavedCheck( "#gpaint.open", self.OnClickOpen ) then return end

    GPaint.EnsureDataDir()

    if IsValid( self.browserFrame ) then
        self.browserFrame:Close()
    end

    local frame = vgui.Create( "DFrame" )
    frame:SetSize( ScrW() * 0.8, ScrH() * 0.8 )
    frame:SetSizable( true )
    frame:SetDraggable( true )
    frame:Center()
    frame:MakePopup()
    frame:SetTitle( "#gpaint.open" )
    frame:SetIcon( "materials/icon16/image.png" )
    frame:SetDeleteOnClose( true )

    self.browserFrame = frame

    local browser = vgui.Create( "DFileBrowser", frame )
    browser:Dock( FILL )
    browser:SetModels( true )
    browser:SetPath( "GAME" )
    browser:SetBaseFolder( "data/gpaint" )
    browser:SetCurrentFolder( "" )
    browser:SetOpen( true )
    browser.thumbnailQueue = {}

    function browser.OnSelect( _, path )
        frame:Close()

        -- tell the screen we want to open a image file
        -- (path is relative to gpaint folder, so we remove "data/gpaint/")
        self.parent:OnOpenImage( string.sub( path, 13 ) )
    end

    function browser.OnRightClick( s, path )
        local menu = DermaMenu()

        menu:AddOption(
            "#gpaint.delete",
            function()
                Derma_Query(
                    langGet( "gpaint.delete_query" ) .. "\n" .. path,
                    "#gpaint.delete", "#gpaint.yes",
                    function()
                        file.Delete( string.sub( path, 6 ) )
                        s:SetCurrentFolder( string.GetPathFromFilename( path ) )
                    end,
                    "#gpaint.no"
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
            "*.png",
            "*.jpg"
        }

        for _, filter in pairs( filters ) do
            local files = file.Find( string.Trim( path .. "/" .. filter, "/" ), s.m_strPath )
            if not istable( files ) then continue end

            for _, v in pairs( files ) do
                local icon = s.Files:Add( "DImageButton" )
                icon:SetSize( 180, 180 )
                icon:SetKeepAspect( true )

                -- add this icon panel and path to the thumbnail queue
                s.thumbnailQueue[#s.thumbnailQueue + 1] = {
                    icon, string.format( "../%s/%s", path, v )
                }

                icon.PaintOver = function( _, selfW )
                    surface.SetDrawColor( 0, 0, 0, 200 )
                    surface.DrawRect( 0, 0, selfW, 20 )

                    surface.SetFont( "Trebuchet18" )
                    surface.SetTextPos( 4, 2 )
                    surface.SetTextColor( 255, 255, 255, 255 )
                    surface.DrawText( v )
                end

                icon.DoClick = function()
                    s.OnSelect( s, path .. "/" .. v, icon )
                end

                icon.DoRightClick = function()
                    s.OnRightClick( s, path .. "/" .. v, icon )
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

        local tex = panel.m_Image.m_Material:GetTexture( "$basetexture" )
        if IsValid( tex ) then tex:Download() end
    end
end

function GPaintMenu:OnClickScreenshot()
    if self:UnsavedCheck( "#gpaint.screenshot", self.OnClickScreenshot ) then return end

    GPaint.TakeScreenshot( function( path )
        if not IsValid( self.parent.entity ) then return end
        if not self.parent.entity:CanPlayerDraw( LocalPlayer() ) then return end

        self.parent.relativeFilePath = nil
        self.parent.isDirty = true
        self.parent:RenderImageFile( "data/" .. path, true )
    end )
end

function GPaintMenu:OnClickShare()
    if self.parent.entity:GetGPaintOwnerSteamID() ~= LocalPlayer():SteamID() then
        Derma_Message( "#gpaint.feature_blocked", "#gpaint.share_screen", "#gpaint.ok" )

        return
    end

    if IsValid( self.shareFrame ) then
        self.shareFrame:Close()
    end

    local frame = vgui.Create( "DFrame" )
    frame:SetSize( 400, 300 )
    frame:SetSizable( true )
    frame:SetDraggable( true )
    frame:Center()
    frame:MakePopup()
    frame:SetTitle( "#gpaint.share_hint" )
    frame:SetIcon( "materials/icon16/group.png" )
    frame:SetDeleteOnClose( true )

    self.shareFrame = frame

    local whitelist = table.Copy( self.parent.entity.GPaintWhitelist )
    local updateLists

    ------ players list ------

    local playersList = vgui.Create( "DListView", frame )
    playersList:SetMultiSelect( false )
    playersList:AddColumn( "#gpaint.all_players" )

    playersList.OnRowSelected = function( _, _, pnl )
        whitelist[pnl._playerID] = true
        updateLists()
    end

    ------ whitelisted players ------

    local sharedList = vgui.Create( "DListView", frame )
    sharedList:SetMultiSelect( false )
    sharedList:AddColumn( "#gpaint.shared_with" )

    sharedList.OnRowSelected = function( _, _, pnl )
        whitelist[pnl._playerID] = nil
        updateLists()
    end

    ------ divider & function to update lists ------

    local div = vgui.Create( "DHorizontalDivider", frame )
    div:Dock( FILL )
    div:SetLeft( playersList )
    div:SetRight( sharedList )
    div:SetDividerWidth( 4 )
    div:SetLeftMin( 100 )
    div:SetRightMin( 100 )
    div:SetLeftWidth( 200 )

    updateLists = function()
        playersList:Clear()
        sharedList:Clear()

        local players = player.GetHumans()
        local localId = LocalPlayer():SteamID()

        table.sort( players, function( a, b )
            return a:Nick() > b:Nick()
        end )

        for _, ply in ipairs( players ) do
            local nick, id = ply:Nick(), ply:SteamID()

            if id ~= localId then
                if whitelist[id] then
                    local pnl = sharedList:AddLine( nick )
                    pnl._playerID = id
                else
                    local pnl = playersList:AddLine( nick )
                    pnl._playerID = id
                end
            end
        end
    end

    updateLists()

    ------ "apply" button ------

    local buttonApply = vgui.Create( "DButton", frame )
    buttonApply:SetText( "#gpaint.apply" )
    buttonApply:Dock( BOTTOM )
    buttonApply:DockMargin( 0, 4, 0, 0 )

    buttonApply.DoClick = function()
        local network = GPaint.network

        network.StartCommand( network.UPDATE_WHITELIST, self.parent.entity )
        network.WriteWhitelist( whitelist )
        net.SendToServer()

        frame:Close()
    end
end

-- if we have unsaved stuff, display a dialog to confirm the user"s intent
function GPaintMenu:UnsavedCheck( title, callback )
    if self.parent.isDirty then
        Derma_Query(
            "#gpaint.unsaved_changes", title, "#gpaint.yes",
            function()
                self.parent.isDirty = false
                callback( self )
            end,
            "#gpaint.no"
        )

        return true
    end

    return false
end