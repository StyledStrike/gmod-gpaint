local function RenderImageData( screen, data )
    GPaint.EnsureDataDir()

    local path = "gpaint/.temp/net.png"
    file.Write( path, data )

    screen:Clear()
    screen:RenderImageFile( path )
    screen.path = nil
    screen.isLoading = false
    screen.menu.isUnsaved = false
    screen.menu:SetTitle()
end

hook.Add( "GPaint_AllowStream", "GPaint.FilterStreams", function( metadata )
    if not metadata.gpaint_entId then return end

    local ent = Entity( metadata.gpaint_entId )
    if not IsValid( ent ) then return false end

    local screen = GPaint.GetScreenByEntity( ent )
    if not screen then return false end

    screen.isLoading = true
    return true
end )

hook.Add( "GPaint_StreamCompleted", "GPaint.ScreenData", function( metadata, data )
    if not metadata.gpaint_entId then return end

    local ent = Entity( metadata.gpaint_entId )
    if not IsValid( ent ) then return end

    local screen = GPaint.GetScreenByEntity( ent )
    if not screen then return end

    RenderImageData( screen, data )
end )

local commands = {
    [GPaint.CLEAR] = function( screen )
        screen:Clear()
    end,

    [GPaint.SUBSCRIBE] = function( screen )
        -- Server wants us to subscribe right away
        screen:Subscribe()
    end,

    [GPaint.SET_LOADING] = function( screen )
        screen.isLoading = net.ReadBool()
        screen.isSubscribed = true
    end,

    [GPaint.PEN_STROKES] = function( screen )
        local strokes = GPaint.ReadStrokes()
        local len = #screen.strokeQueue

        for i, st in ipairs( strokes ) do
            screen.strokeQueue[len + i] = st
        end
    end,

    [GPaint.UPDATE_WHITELIST] = function( _, ent )
        GPaint.ReadWhitelist( ent.GPaintWhitelist )
    end,

    [GPaint.REQUEST_DATA] = function( screen, ent )
        -- Server wants us to send what the screen looks like
        local requestId = net.ReadUInt( 10 )
        local data = screen:CaptureRT( "jpg" )

        GPaint.Transfer( data, { gpaint_entId = ent:EntIndex(), gpaint_requestId = requestId }, function( err )
            if not err then return end

            screen.isLoading = false
            GPaint.PrintF( "Failed to stream image file: %s", err )
        end )
    end
}

net.Receive( "gpaint.command", function()
    local ent = net.ReadEntity()
    if not IsValid( ent ) then return end

    local screen = GPaint.GetScreenByEntity( ent )
    if not screen then return end

    local cmd = net.ReadUInt( GPaint.COMMAND_SIZE )

    if commands[cmd] then
        commands[cmd]( screen, ent )
    end
end )
