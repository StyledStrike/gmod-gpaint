resource.AddWorkshop( "2697023796" )
util.AddNetworkString( "gpaint.command" )

CreateConVar(
    "sbox_maxgpaint_boards",
    "3",
    bit.bor( FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED ),
    "Maximum GPaint screens a player can create",
    0
)

local IsValid = IsValid
local gnet = GPaint.network
local IsGPaintScreen = GPaint.IsGPaintScreen

local function IsValidData( data, fromSteamId )
    if not data then
        GPaint.LogF( "Missing data from %s", fromSteamId )

        return false
    end

    if #data > gnet.MAX_DATA_SIZE then
        GPaint.LogF( "Ignoring data from %s (too big)", fromSteamId )

        return false
    end

    return true
end

-- little utility functions that handles screen data requests
local requestId = 0

local function AddRequest( ply, ent )
    local owner = ent:GetCreator()
    if not IsValid( owner ) then return end

    if not ent.requests then
        ent.requests = {}
    end

    -- only one request at a time
    for _, p in pairs( ent.requests ) do
        if p == ply then return end
    end

    -- asks the owner for the screen data
    requestId = requestId + 1
    if requestId > 1000 then requestId = 0 end

    gnet.StartCommand( gnet.REQUEST_DATA, ent )
    net.WriteUInt( requestId, 10 )
    net.Send( owner )

    ent.requests[requestId] = ply

    GPaint.LogF( "%s requested screen data", ply:Name() )
end

local function CancelRequests( ply, ent )
    if not ent.requests then return end

    for id, p in pairs( ent.requests ) do
        if p == ply then
            ent.requests[id] = nil

            gnet.StartCommand( gnet.AWAIT_DATA, ent )
            net.WriteBool( false )
            net.Send( ply )

            GPaint.LogF( "%s cancelled their screen data request #%d", ply:Name(), id )
        end
    end
end

local function FulfillRequest( id, ent, fromPly, targetPly, data )
    ent.requests[id] = nil

    if not IsValid( targetPly ) then return end

    if not data then
        gnet.StartCommand( gnet.AWAIT_DATA, ent )
        net.WriteBool( false )
        net.Send( targetPly )

        return
    end

    if not IsValidData( data, fromPly:SteamID() ) then return end

    if gnet.USE_EXPRESS then
        gnet.StartCommand( gnet.AWAIT_DATA, ent )
        net.WriteBool( true )
        net.Send( targetPly )

        express.Send(
            "gpaint.transfer",
            {
                ent = ent,
                image = data
            },
            { targetPly }
        )

        return
    end

    -- send the image data to only one target
    gnet.StartCommand( gnet.BROADCAST_DATA, ent )
    gnet.WriteImage( data )
    net.Send( targetPly )
end

--[[
    To prevent being "too hard" on the net system, we have a "subscription"
    kind-of thing, where only clients who are subscribed to a GPaint entity
    will receive network events from it.
]]

local function AddSubscriber( ply, ent )
    if not ent.subscribers then
        ent.subscribers = {}
    end

    ent.subscribers[ply:SteamID()] = ply
end

local function RemoveSubscriber( ply, ent )
    if ent.subscribers then
        ent.subscribers[ply:SteamID()] = nil
    end
end

local function CanPlayerSubscribe( ply, ent )
    if ent.subscribers and ent.subscribers[ply:SteamID()] then
        return false
    end

    return true
end

local function GetSubscribers( ent, ignore )
    local subs = ent.subscribers or {}
    local targets = {}

    for steamId, ply in pairs( subs ) do
        if not IsValid( ply ) then
            subs[steamId] = nil

        elseif ply ~= ignore then
            targets[#targets + 1] = ply
        end
    end

    return targets
end

local streams = {}

local netCommands = {
    [gnet.UPDATE_WHITELIST] = function( ply, ent )
        if ply ~= ent:GetGPaintOwner() then return end

        gnet.ReadWhitelist( ent.GPaintWhitelist )

        gnet.StartCommand( gnet.UPDATE_WHITELIST, ent )
        gnet.WriteWhitelist( ent.GPaintWhitelist )
        net.Broadcast()
    end,

    [gnet.SUBSCRIBE] = function( ply, ent )
        if not CanPlayerSubscribe( ply, ent ) then return end

        AddSubscriber( ply, ent )

        if ply == ent:GetCreator() then
            -- ready to go
            gnet.StartCommand( gnet.AWAIT_DATA, ent )
            net.WriteBool( false )
            net.Send( ply )

        else
            -- ask the entity owner to send what the
            -- screen looks like just to this new subscriber
            AddRequest( ply, ent )
        end
    end,

    [gnet.UNSUBSCRIBE] = function( ply, ent )
        -- dont allow the screen owner to unsubscribe
        -- (cause others rely on the owner being
        -- up-to-date on what the screen looks like)
        if ply == ent:GetCreator() then return end

        RemoveSubscriber( ply, ent )

        -- make sure no screen data requests are still active
        CancelRequests( ply, ent )
    end,

    [gnet.CLEAR] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        gnet.StartCommand( gnet.CLEAR, ent )
        net.Send( subs )
    end,

    [gnet.PEN_STROKES] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        local strokes = gnet.ReadStrokes()
        if #strokes == 0 then return end

        gnet.StartCommand( gnet.PEN_STROKES, ent )
        gnet.WriteStrokes( strokes )
        net.Send( subs )
    end,

    [gnet.BROADCAST_DATA] = function( ply, ent )
        if gnet.USE_EXPRESS then return end
        if not ent:CanPlayerDraw( ply ) then return end

        local steamId = ply:SteamID()
        if streams[steamId] then return end

        streams[steamId] = gnet.ReadImage( ply, function( data )
            streams[steamId] = nil

            if not IsValid( ent ) then return end
            if not IsValidData( data, steamId ) then return end

            local subs = GetSubscribers( ent, ply )
            if #subs == 0 then return end

            gnet.StartCommand( gnet.BROADCAST_DATA, ent )
            gnet.WriteImage( data )
            net.Send( subs )
        end )
    end,

    [gnet.SEND_DATA] = function( ply, ent )
        if not ent.requests then return end

        local id = net.ReadUInt( 10 )
        local target = ent.requests[id]

        if not target then return end

        local hasData = net.ReadBool()
        local steamId = ply:SteamID()

        if not hasData then
            FulfillRequest( id, ent, ply, target, nil )

            return
        end

        gnet.ReadImage( ply, function( data )
            if not IsValid( ent ) then return end
            if not IsValidData( data, steamId ) then return end

            FulfillRequest( id, ent, ply, target, data )
        end )
    end
}

net.Receive( "gpaint.command", function( _, ply )
    local ent = net.ReadEntity()
    if not IsGPaintScreen( ent ) then return end

    local cmd = net.ReadUInt( gnet.COMMAND_SIZE )

    if netCommands[cmd] then
        netCommands[cmd]( ply, ent )
    end
end )

hook.Add( "PlayerSpawnedSENT", "GPaint_SetScreenCreator", function( ply, ent )
    if IsGPaintScreen( ent ) then
        -- set the screen owner
        ent:SetGPaintOwner( ply )

        -- tell the screen owner to subscribe
        timer.Simple( 1, function()
            if IsValid( ent ) then
                gnet.StartCommand( gnet.SUBSCRIBE, ent )
                net.Send( ply )
            end
        end )
    end
end )

gnet.OnExpressLoad = function()
    GPaint.LogF( "Now we\"re using gm_express!" )

    express.Receive( "gpaint.transfer", function( ply, data )
        if not IsValid( ply ) then
            GPaint.LogF( "Ignoring gm_express data coming from a invalid player" )

            return
        end

        if type( data ) ~= "table" then return end

        local steamId = ply:SteamID()
        local id = data.requestId
        local ent = data.ent

        if not IsGPaintScreen( ent ) then return end
        if not ent:CanPlayerDraw( ply ) then return end

        if id then
            local target = ent.requests[id]
            if not target then return end

            FulfillRequest( id, ent, ply, target, data.image )

        else
            if not IsValidData( data.image, steamId ) then return end

            local subs = GetSubscribers( ent, ply )
            if #subs == 0 then return end

            gnet.StartCommand( gnet.AWAIT_DATA, ent )
            net.WriteBool( true )
            net.Send( subs )

            express.Send(
                "gpaint.transfer",
                {
                    ent = ent,
                    image = data.image
                },
                subs
            )
        end
    end )
end
