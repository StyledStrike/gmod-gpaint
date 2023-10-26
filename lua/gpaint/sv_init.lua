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
local IsGPaintScreen = GPaint.IsGPaintScreen
local network = GPaint.network

local function IsValidData( data, fromSteamId )
    if not data then
        GPaint.LogF( "Missing data from %s", fromSteamId )

        return false
    end

    if #data > network.MAX_DATA_SIZE then
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

    network.StartCommand( network.REQUEST_DATA, ent )
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

            network.StartCommand( network.AWAIT_DATA, ent )
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
        network.StartCommand( network.AWAIT_DATA, ent )
        net.WriteBool( false )
        net.Send( targetPly )

        return
    end

    if not IsValidData( data, fromPly:SteamID() ) then return end

    if network.USE_EXPRESS then
        network.StartCommand( network.AWAIT_DATA, ent )
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
    network.StartCommand( network.BROADCAST_DATA, ent )
    network.WriteImage( data )
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
    [network.UPDATE_WHITELIST] = function( ply, ent )
        if ply:SteamID() ~= ent:GetGPaintOwnerSteamID() then return end

        network.ReadWhitelist( ent.GPaintWhitelist )

        network.StartCommand( network.UPDATE_WHITELIST, ent )
        network.WriteWhitelist( ent.GPaintWhitelist )
        net.Broadcast()
    end,

    [network.SUBSCRIBE] = function( ply, ent )
        if not CanPlayerSubscribe( ply, ent ) then return end

        AddSubscriber( ply, ent )
        print( ply, ent )
        print( ply:SteamID(), ent:GetGPaintOwnerSteamID() )

        if ply:SteamID() == ent:GetGPaintOwnerSteamID() then
            -- ready to go
            network.StartCommand( network.AWAIT_DATA, ent )
            net.WriteBool( false )
            net.Send( ply )

        else
            -- ask the entity owner to send what the
            -- screen looks like just to this new subscriber
            AddRequest( ply, ent )
        end
    end,

    [network.UNSUBSCRIBE] = function( ply, ent )
        -- dont allow the screen owner to unsubscribe
        -- (cause others rely on the owner being
        -- up-to-date on what the screen looks like)
        if ply == ent:GetCreator() then return end

        RemoveSubscriber( ply, ent )

        -- make sure no screen data requests are still active
        CancelRequests( ply, ent )
    end,

    [network.CLEAR] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        network.StartCommand( network.CLEAR, ent )
        net.Send( subs )
    end,

    [network.PEN_STROKES] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        local strokes = network.ReadStrokes()
        if #strokes == 0 then return end

        network.StartCommand( network.PEN_STROKES, ent )
        network.WriteStrokes( strokes )
        net.Send( subs )
    end,

    [network.BROADCAST_DATA] = function( ply, ent )
        if network.USE_EXPRESS then return end
        if not ent:CanPlayerDraw( ply ) then return end

        local steamId = ply:SteamID()
        if streams[steamId] then return end

        streams[steamId] = network.ReadImage( ply, function( data )
            streams[steamId] = nil

            if not IsValid( ent ) then return end
            if not IsValidData( data, steamId ) then return end

            local subs = GetSubscribers( ent, ply )
            if #subs == 0 then return end

            network.StartCommand( network.BROADCAST_DATA, ent )
            network.WriteImage( data )
            net.Send( subs )
        end )
    end,

    [network.SEND_DATA] = function( ply, ent )
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

        network.ReadImage( ply, function( data )
            if not IsValid( ent ) then return end
            if not IsValidData( data, steamId ) then return end

            FulfillRequest( id, ent, ply, target, data )
        end )
    end
}

hook.Add( "PlayerDisconnected", "GPaint.CleanupSubscribers", function( ply )
    local id = ply:SteamID()

    for _, ent in ipairs( ents.FindByClass( "ent_gpaint_*" ) ) do
        if ent.subscribers then
            ent.subscribers[id] = nil
        end
    end
end )

net.Receive( "gpaint.command", function( _, ply )
    local ent = net.ReadEntity()
    if not IsGPaintScreen( ent ) then return end

    local cmd = net.ReadUInt( network.COMMAND_SIZE )

    if netCommands[cmd] then
        netCommands[cmd]( ply, ent )
    end
end )

network.OnExpressLoad = function()
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

            network.StartCommand( network.AWAIT_DATA, ent )
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
