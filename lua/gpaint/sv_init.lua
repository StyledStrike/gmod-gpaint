util.AddNetworkString( 'gpaint.command' )

CreateConVar(
    'sbox_maxgpaint_boards',
    '3',
    bit.bor( FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED ),
    'Maximum GPaint screens a player can create',
    0
)

local IsValid = IsValid
local gnet = GPaint.network

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

    GPaint.LogF( '%s requested screen data', ply:Name() )
end

local function CancelRequests( ply, ent )
    if not ent.requests then return end

    for id, p in pairs( ent.requests ) do
        if p == ply then
            ent.requests[id] = nil

            gnet.StartCommand( gnet.AWAIT_DATA, ent )
            net.WriteBool( false )
            net.Send( ply )

            GPaint.LogF( '%s cancelled their screen data request', ply:Name() )
        end
    end
end

local function IsGPaintScreen( ent )
    return IsValid( ent ) and (
        ent:GetClass() == 'ent_gpaint_base' or
        ent.Base == 'ent_gpaint_base'
    )
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
        if not ent:CanPlayerDraw( ply ) then return end

        local steamId = ply:SteamID()
        if streams[steamId] then return end

        streams[steamId] = gnet.ReadImage( ply, function( data )
            streams[steamId] = nil

            if not IsValid( ent ) then return end

            if #data > gnet.MAX_DATA_SIZE then
                GPaint.LogF( 'Ignoring data from %s (too big)', steamId )

                return
            end

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

        ent.requests[id] = nil

        if IsValid( target ) then
            if not hasData then
                gnet.StartCommand( gnet.AWAIT_DATA, ent )
                net.WriteBool( false )
                net.Send( target )

                return
            end

            gnet.ReadImage( ply, function( data )
                if not IsValid( ent ) then return end

                if not data then
                    GPaint.LogF( 'Missing data from %s', steamId )

                    return
                end

                if #data > gnet.MAX_DATA_SIZE then
                    GPaint.LogF( 'Ignoring data from %s (too big)', steamId )

                    return
                end

                -- send the image data to only one target
                gnet.StartCommand( gnet.BROADCAST_DATA, ent )
                gnet.WriteImage( data )
                net.Send( target )
            end )
        end
    end
}

net.Receive( 'gpaint.command', function( _, ply )
    local ent = net.ReadEntity()
    if not IsGPaintScreen( ent ) then return end

    local cmd = net.ReadUInt( gnet.COMMAND_SIZE )

    if netCommands[cmd] then
        netCommands[cmd]( ply, ent )
    end
end )