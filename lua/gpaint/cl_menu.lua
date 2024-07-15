local colors = {
    text = Color( 255, 255, 255 ),
    highlight = Color( 94, 0, 196 ),
    bgButton = Color( 0, 0, 0, 255 )
}

local materials = {
    hue = Material( "gui/colors.png" ),
    saturation = Material( "vgui/gradient-r" ),
    value = Material( "vgui/gradient-d" )
}

local L = language.GetPhrase

local SetMaterial = surface.SetMaterial
local SetDrawColor = surface.SetDrawColor
local DrawRect = surface.DrawRect
local DrawSimpleText = draw.SimpleText
local DrawTexturedRect = surface.DrawTexturedRect

local function DrawButton( self, _, x, y, isSelected )
    draw.RoundedBox( 6, x, y, self.w, self.h, isSelected and colors.highlight or colors.bgButton )
    DrawSimpleText( self.label, "Trebuchet24", x + self.w * 0.5, y + self.h * 0.5, colors.text, 1, 1 )
end

local panels = {
    {
        label = "#gpaint.new",
        clickEvent = "OnClickNew",

        w = 220, h = 30,
        Draw = DrawButton
    },
    {
        label = "#gpaint.save",
        clickEvent = "OnClickSave",

        w = 220, h = 30,
        Draw = DrawButton
    },
    {
        label = "#gpaint.saveas",
        clickEvent = "OnClickSaveAs",

        w = 220, h = 30,
        Draw = DrawButton
    },
    {
        label = "#gpaint.open",
        clickEvent = "OnClickOpen",

        w = 220, h = 30,
        Draw = DrawButton
    },
    {
        label = "#gpaint.screenshot",
        clickEvent = "OnClickScreenshot",

        w = 220, h = 30,
        Draw = DrawButton
    },
    {
        label = "#gpaint.thickness",
        w = 220, h = 60,
        max = 200,

        Draw = function( self, m, x, y )
            local h = self.h - 30
            y = y + 30

            SetDrawColor( colors.bgButton:Unpack() )
            DrawRect( x, y, self.w, h )

            SetDrawColor( colors.highlight:Unpack() )
            DrawRect( x, y, self.w * ( m.screen.penThickness / self.max ), h )

            DrawSimpleText( self.label, "Trebuchet24", x + 2, y, colors.text, 0, 4 )
            DrawSimpleText( m.screen.penThickness .. "px", "Trebuchet24", x + self.w - 2, y, colors.text, 2, 4 )
        end,

        OnCursor = function( self, m, x, y )
            if y < 30 then return end

            local value = math.Round( ( x / self.w ) * self.max )
            m.screen.penThickness = math.Clamp( value, 1, self.max )
        end
    },
    {
        id = "color",
        label = "#gpaint.color",
        w = 220, h = 200,

        hue = 0,
        value = 0,
        saturation = 1,
        base = Color( 0, 0, 0 ),

        Draw = function( self, m, x, y )
            DrawSimpleText( self.label, "Trebuchet24", x, y, colors.text, 0, 0 )

            local penColor = m.screen.penColor

            SetDrawColor( penColor.r, penColor.g, penColor.b, 255 )
            DrawRect( x + self.w - 20, y + 4, 20, 20 )

            SetDrawColor( 255, 255, 255, 255 )
            surface.DrawOutlinedRect( x + self.w - 20, y + 4, 20, 20, 1 )

            y = y + 32

            local hueW = 40
            local pickerH = self.h - 32
            local saturationX = x + hueW + 8
            local saturationW = self.w - 48

            -- Hue
            SetDrawColor( 255, 255, 255, 255 )
            SetMaterial( materials.hue )
            DrawTexturedRect( x, y, hueW, pickerH )

            -- Saturation
            SetDrawColor( self.base.r, self.base.g, self.base.b, 255 )
            DrawRect( saturationX, y, saturationW, pickerH )

            SetDrawColor( 255, 255, 255, 255 )
            SetMaterial( materials.saturation )
            DrawTexturedRect( saturationX, y, saturationW, pickerH )

            -- Value
            SetDrawColor( 0, 0, 0, 255 )
            SetMaterial( materials.value )
            DrawTexturedRect( saturationX, y, saturationW, pickerH )
            draw.NoTexture()

            -- Selected hue
            SetDrawColor( 255, 255, 255, 255 )
            surface.DrawOutlinedRect( x - 1, y + self.hue * pickerH - 2, hueW + 2, 3, 1 )

            -- Selected saturation / value
            local selectionX = saturationX + ( 1 - self.saturation ) * saturationW
            local selectionY = y + ( 1 - self.value ) * pickerH

            surface.DrawCircle( selectionX, selectionY, 2, 0, 0, 0, 255 )
            surface.DrawCircle( selectionX, selectionY, 3, 255, 255, 255, 255 )
        end,

        OnCursor = function( self, m, x, y )
            local pickerH = self.h - 32

            if x < 40 then
                -- Hue picker
                self.hue = math.Clamp( ( y - 31 ) / pickerH, 0, 1 )

                local colorX = materials.hue:Width() * 0.5
                local colorY = math.Clamp( self.hue * materials.hue:Height(), 0, materials.hue:Height() - 1 )
                local clr = materials.hue:GetColor( colorX, colorY )

                local h = ColorToHSV( clr )
                self.base = HSVToColor( h, 1, 1 )

                m.screen.penColor = HSVToColor( h, self.saturation, self.value )
            else
                -- Saturation picker
                local saturationW = self.w - 48
                local relativeX = ( x - 48 ) / saturationW
                local relativeY = ( y - 32 ) / pickerH

                self.value = 1 - math.Clamp( relativeY, 0, 1 )
                self.saturation = 1 - math.Clamp( relativeX, 0, 1 )

                local h = ColorToHSV( self.base )
                local clr = HSVToColor( h, self.saturation, self.value )

                m.screen.penColor = Color( clr.r, clr.g, clr.b )
            end
        end
    }
}

if not game.SinglePlayer() then
    table.insert( panels, 6, {
        label = "#gpaint.share_screen",
        clickEvent = "OnClickShare",

        w = 220, h = 30,
        Draw = DrawButton
    } )
end

local function GetPanelByID( id )
    for _, item in ipairs( panels ) do
        if item.id == id then return item end
    end
end

local function IsInsideBox( x, y, bx, by, bw, bh )
    return x > bx and y > by and x < bx + bw and y < by + bh
end

--[[
    This is a sort-of class to handle the "menu"
    you see in-game for each GPaint screen.
]]
local Menu = GPaint.Menu or {}

GPaint.Menu = Menu
Menu.__index = Menu

function GPaint.CreateMenu( screen )
    return setmetatable( {
        screen = screen,
        isOpen = false,
        isUnsaved = false,
        title = "",
        animation = 0
    }, Menu )
end

function Menu:Remove()
    if IsValid( self.frameFileBrowser ) then
        self.frameFileBrowser:Close()
    end

    if IsValid( self.frameWhitelist ) then
        self.frameWhitelist:Close()
    end
end

function Menu:Open()
    self.isOpen = true
    self:SetPenColor( self.screen.penColor )
end

function Menu:Close()
    self.isOpen = false
end

function Menu:IsDraggingItem()
    return self.selection and self.selection.beingDragged
end

function Menu:SetTitle( title )
    self.title = title or L"gpaint.new"

    if string.len( self.title ) > 35 then
        self.title = "..." .. string.Right( self.title, 32 )
    end
end

function Menu:SetPenColor( color )
    local h, s, v = ColorToHSV( color )
    local item = GetPanelByID( "color" )

    item.base = HSVToColor( h, 1, 1 )
    item.hue = 1 - ( h / 360 )
    item.saturation = s
    item.value = v
end

function Menu:Render( h )
    self.animation = Lerp( FrameTime() * 15, self.animation, self.isOpen and 1 or 0 )
    if self.animation < 0.01 then return end

    surface.SetAlphaMultiplier( self.animation )

    local w = 240
    local x = - w + ( self.animation * ( w + 8 ) )
    local y = 8

    -- Background
    SetDrawColor( 80, 80, 80, 150 )
    DrawRect( x, y, w, h - 16 )

    -- Title
    SetDrawColor( colors.highlight:Unpack() )
    DrawRect( x, y, w, 30 )

    DrawSimpleText( self.title, "Trebuchet18", x + ( w * 0.5 ), y + 15, colors.text, 1, 1 )

    -- Menu items
    x = x + 8
    y = y + 42

    local cX, cY = self.screen.cursorX, self.screen.cursorY
    local selection, isSelected

    for i, panel in ipairs( panels ) do
        isSelected = cX and IsInsideBox( cX, cY, x, y, panel.w, panel.h )

        if isSelected then
            selection = { index = i, x = x, y = y }
        end

        panel:Draw( self, x, y, isSelected )
        y = y + panel.h + 4
    end

    -- Only change the current selected panel when the cursor is not being pressed
    if self.screen.cursorState == 0 then
        self.selection = selection
    end

    surface.SetAlphaMultiplier( 1 )
end

function Menu:OnCursor( x, y, pressed, justPressed )
    local selection = self.selection
    if not selection then return end

    local item = panels[selection.index]

    if justPressed and item.clickEvent then
        self[item.clickEvent]( self )
        self:Close()
    end

    if pressed and item.OnCursor then
        selection.beingDragged = true
        item:OnCursor( self, x - selection.x, y - selection.y )
    else
        selection.beingDragged = false
    end
end

--- If we have unsaved stuff, display a dialog to confirm the user's intent.
function Menu:UnsavedCheck( title, callback )
    if self.isUnsaved then
        Derma_Query(
            "#gpaint.unsaved_changes", title, "#gpaint.yes",
            function()
                self.isUnsaved = false
                callback( self )
            end,
            "#gpaint.no"
        )

        return true
    end

    return false
end

function Menu:OnClickNew()
    if self:UnsavedCheck( "#gpaint.new", self.OnClickNew ) then return end

    self.screen.path = nil
    self.screen:Clear( true )
    self:SetTitle()
end

function Menu:OnClickSave( forceNew )
    local data = self.screen:CaptureRT()

    local function WriteFile( path )
        GPaint.EnsureDataDir()

        local dir = string.GetPathFromFilename( path )

        if not file.Exists( dir, "DATA" ) then
            file.CreateDir( dir )
        end

        file.Write( path, data )

        if file.Exists( path, "DATA" ) then
            if self then
                self.screen.path = path
                self.isUnsaved = false
                self:SetTitle( self.screen.path )
            end

            notification.AddLegacy( string.format( L"gpaint.saved_to", path ), NOTIFY_GENERIC, 5 )
        else
            notification.AddLegacy( L"gpaint.save_failed", NOTIFY_ERROR, 5 )
        end
    end

    local path = self.screen.path

    if not path or forceNew then
        local now = os.date( "*t" )
        path = string.format( "gpaint/%04i_%02i_%02i %02i-%02i-%02i", now.year, now.month, now.day, now.hour, now.min, now.sec )
    end

    if file.Exists( path, "DATA" ) then
        WriteFile( path )
        return
    end

    Derma_StringRequest(
        "#gpaint.save",
        "#gpaint.enter_name",
        path,
        function( result )
            path = string.Trim( result )

            if string.len( path ) == 0 then
                Derma_Message( "#gpaint.enter_name", "#gpaint.error", "#gpaint.ok" )
                return
            end

            local ext = string.Right( path, 4 )

            if ext ~= ".png" and ext ~= ".jpg" then
                path = path .. ".png"
            end

            WriteFile( path )
        end
    )
end

function Menu:OnClickSaveAs()
    self:OnClickSave( true )
end

function Menu:OnClickOpen()
    if self:UnsavedCheck( "#gpaint.open", self.OnClickOpen ) then return end

    GPaint.EnsureDataDir()

    if IsValid( self.frameFileBrowser ) then
        self.frameFileBrowser:Close()
    end

    local frame = vgui.Create( "DFrame" )
    frame:SetSize( math.max( 800, ScrW() * 0.6 ), math.max( 500, ScrH() * 0.6 ) )
    frame:SetSizable( true )
    frame:SetDraggable( true )
    frame:Center()
    frame:MakePopup()
    frame:SetTitle( "#gpaint.open" )
    frame:SetIcon( "materials/icon16/image.png" )
    frame:SetDeleteOnClose( true )

    self.frameFileBrowser = frame

    local panelPath = vgui.Create( "DPanel", frame )
    panelPath:Dock( TOP )
    panelPath:DockPadding( 8, 4, 8, 4 )

    panelPath.Paint = function( _, w, h )
        surface.SetDrawColor( 20, 20, 20 )
        surface.DrawRect( 0, 0, w, h )
    end

    local labelPath = vgui.Create( "DLabel", panelPath )
    labelPath:SetText( "data/" )
    labelPath:SetTextColor( color_white )
    labelPath:SizeToContents()
    labelPath:Dock( FILL )

    panelPath:SizeToChildren( false, true )
    panelPath:SetTall( panelPath:GetTall() + 8 )

    local browser = vgui.Create( "DFileBrowser", frame )
    browser:Dock( FILL )
    browser:SetModels( true )
    browser:SetPath( "GAME" )
    browser:SetBaseFolder( "data" )
    browser:SetOpen( true )
    browser:SetCurrentFolder( "gpaint" )

    browser.thumbnailQueue = {}

    function browser.OnSelect( _, path )
        frame:Close()

        path = string.sub( path, 6 ) -- remove "data/"
        self.screen:OnOpenImage( path )
    end

    function browser.OnRightClick( s, path )
        local menu = DermaMenu()

        menu:AddOption(
            "#gpaint.delete",
            function()
                Derma_Query(
                    L( "gpaint.delete_query" ) .. "\n" .. path,
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

    local filters = {
        "*.png",
        "*.jpg"
    }

    local function PaintOverIcon( s, w )
        SetDrawColor( 0, 0, 0, 200 )
        DrawRect( 0, 0, w, 20 )

        surface.SetFont( "Trebuchet18" )
        surface.SetTextPos( 4, 2 )
        surface.SetTextColor( 255, 255, 255, 255 )
        surface.DrawText( s._label )
    end

    --- Custom version of ShowFolder from DFileBrowser,
    --- modified to show icons instead of a list of names.
    function browser.ShowFolder( s, path )
        if path then
            labelPath:SetText( path )
        end

        if not IsValid( s.Files ) then return end

        s.Files:Clear()
        s.Files:DockPadding( 4, 4, 4, 4 )

        if not path then return end

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

                icon._label = v
                icon.PaintOver = PaintOverIcon

                icon.DoClick = function()
                    s.OnSelect( s, path .. "/" .. v )
                end

                icon.DoRightClick = function()
                    s.OnRightClick( s, path .. "/" .. v )
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

function Menu:OnClickScreenshot()
    if self:UnsavedCheck( "#gpaint.screenshot", self.OnClickScreenshot ) then return end

    GPaint.TakeScreenshot( function( path )
        if not IsValid( self.screen.entity ) then return end
        if not self.screen.entity:CanPlayerDraw( LocalPlayer() ) then return end

        self.screen.path = nil
        self.isUnsaved = true
        self:SetTitle()
        self.screen:RenderImageFile( path, true )
    end )
end

function Menu:OnClickShare()
    if self.screen.entity:GetGPaintOwnerSteamID() ~= LocalPlayer():SteamID() then
        Derma_Message( "#gpaint.feature_blocked", "#gpaint.share_screen", "#gpaint.ok" )
        return
    end

    if IsValid( self.frameWhitelist ) then
        self.frameWhitelist:Close()
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

    self.frameWhitelist = frame

    local whitelist = table.Copy( self.screen.entity.GPaintWhitelist )
    local UpdateLists

    -- Available players list
    local playersList = vgui.Create( "DListView", frame )
    playersList:SetMultiSelect( false )
    playersList:AddColumn( "#gpaint.all_players" )

    playersList.OnRowSelected = function( _, _, pnl )
        whitelist[pnl._playerId] = true
        UpdateLists()
    end

    -- Whitelisted players
    local sharedList = vgui.Create( "DListView", frame )
    sharedList:SetMultiSelect( false )
    sharedList:AddColumn( "#gpaint.shared_with" )

    sharedList.OnRowSelected = function( _, _, pnl )
        whitelist[pnl._playerId] = nil
        UpdateLists()
    end

    local div = vgui.Create( "DHorizontalDivider", frame )
    div:Dock( FILL )
    div:SetLeft( playersList )
    div:SetRight( sharedList )
    div:SetDividerWidth( 4 )
    div:SetLeftMin( 100 )
    div:SetRightMin( 100 )
    div:SetLeftWidth( 200 )

    UpdateLists = function()
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
                    pnl._playerId = id
                else
                    local pnl = playersList:AddLine( nick )
                    pnl._playerId = id
                end
            end
        end
    end

    UpdateLists()

    local buttonApply = vgui.Create( "DButton", frame )
    buttonApply:SetText( "#gpaint.apply" )
    buttonApply:Dock( BOTTOM )
    buttonApply:DockMargin( 0, 4, 0, 0 )

    buttonApply.DoClick = function()
        GPaint.StartCommand( GPaint.UPDATE_WHITELIST, self.screen.entity )
        GPaint.WriteWhitelist( whitelist )
        net.SendToServer()

        frame:Close()
    end
end
