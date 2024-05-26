util.AddNetworkString( "gpaint.command" )

local IsValid = IsValid
local IsGPaintScreen = GPaint.IsGPaintScreen

-- Utility functions to handle screen data requests
local lastRequestId = 0

local function AddRequest( ply, ent )
    local owner = ent:GetCreator()
    if not IsValid( owner ) then return end

    if not ent.requests then
        ent.requests = {}
    end

    -- Only one request at a time
    for _, p in pairs( ent.requests ) do
        if p == ply then return end
    end

    -- Request screen data from the owner
    lastRequestId = lastRequestId + 1
    if lastRequestId > 1000 then lastRequestId = 0 end

    GPaint.StartCommand( GPaint.REQUEST_DATA, ent )
    net.WriteUInt( lastRequestId, 10 )
    net.Send( owner )

    ent.requests[lastRequestId] = ply

    GPaint.PrintF( "%s requested screen data from %s", ply:SteamID(), owner:SteamID() )
end

local function CancelRequests( ply, ent )
    if not ent.requests then return end

    for id, p in pairs( ent.requests ) do
        if p == ply then
            ent.requests[id] = nil

            GPaint.StartCommand( GPaint.SET_LOADING, ent )
            net.WriteBool( false )
            net.Send( ply )

            GPaint.PrintF( "%s cancelled their screen data request #%d", ply:SteamID(), id )
            break
        end
    end
end

local function FulfillRequest( id, ent, data )
    local targetPly = ent.requests[id]

    ent.requests[id] = nil

    if not IsValid( targetPly ) then return end

    if not data then
        GPaint.StartCommand( GPaint.SET_LOADING, ent )
        net.WriteBool( false )
        net.Send( targetPly )

        return
    end

    -- Send the image data to only one target
    GPaint.Transfer( data, { gpaint_entId = ent:EntIndex() }, function( err )
        if err then GPaint.PrintF( "Failed to stream request data: %s", err ) end
    end, targetPly )
end

--[[
    To prevent being "too hard" on the network system, we have a "subscription"
    system, where only clients who are subscribed to a GPaint entity
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

    for playerId, ply in pairs( subs ) do
        if not IsValid( ply ) then
            subs[playerId] = nil

        elseif ply ~= ignore then
            targets[#targets + 1] = ply
        end
    end

    return targets
end

local commands = {
    [GPaint.UPDATE_WHITELIST] = function( ply, ent )
        if ply:SteamID() ~= ent:GetGPaintOwnerSteamID() then return end

        GPaint.ReadWhitelist( ent.GPaintWhitelist )

        GPaint.StartCommand( GPaint.UPDATE_WHITELIST, ent )
        GPaint.WriteWhitelist( ent.GPaintWhitelist )
        net.Broadcast()
    end,

    [GPaint.SUBSCRIBE] = function( ply, ent )
        if not CanPlayerSubscribe( ply, ent ) then return end

        AddSubscriber( ply, ent )

        if ply:SteamID() == ent:GetGPaintOwnerSteamID() then
            -- Ready to draw
            GPaint.StartCommand( GPaint.SET_LOADING, ent )
            net.WriteBool( false )
            net.Send( ply )

        else
            -- Ask the entity owner to send what the
            -- screen looks like just to this new subscriber
            AddRequest( ply, ent )
        end
    end,

    [GPaint.UNSUBSCRIBE] = function( ply, ent )
        -- Don't allow the screen owner to unsubscribe
        -- (Because others rely on the owner being up-to-date on what the screen looks like)
        if ply == ent:GetCreator() then return end

        RemoveSubscriber( ply, ent )

        -- Make sure no screen data requests are still active
        CancelRequests( ply, ent )
    end,

    [GPaint.CLEAR] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        GPaint.StartCommand( GPaint.CLEAR, ent )
        net.Send( subs )
    end,

    [GPaint.PEN_STROKES] = function( ply, ent )
        if not ent:CanPlayerDraw( ply ) then return end

        local subs = GetSubscribers( ent, ply )
        if #subs == 0 then return end

        local strokes = GPaint.ReadStrokes()
        if #strokes == 0 then return end

        GPaint.StartCommand( GPaint.PEN_STROKES, ent )
        GPaint.WriteStrokes( strokes )
        net.Send( subs )
    end
}

-- Safeguard against spam. Commands not listed here already have
-- their own mechanics that block unsolicited net events.
local cooldowns = {
    [GPaint.UPDATE_WHITELIST] = { interval = 1, players = {} },
    [GPaint.PEN_STROKES] = { interval = 0.1, players = {} },
    [GPaint.CLEAR] = { interval = 0.5, players = {} }
}

net.Receive( "gpaint.command", function( _, ply )
    local ent = net.ReadEntity()
    if not IsGPaintScreen( ent ) then return end

    local cmd = net.ReadUInt( GPaint.COMMAND_SIZE )

    if cooldowns[cmd] then
        local t = RealTime()
        local id = ply:SteamID()
        local players = cooldowns[cmd].players

        if players[id] and players[id] > t then
            GPaint.PrintF( "%s <%s> sent a network command too fast!", ply:Nick(), id )

            return
        end

        players[id] = t + cooldowns[cmd].interval
    end

    if commands[cmd] then
        commands[cmd]( ply, ent )
    end
end )

hook.Add( "PlayerDisconnected", "GPaint.CleanupSubscribers", function( ply )
    local id = ply:SteamID()

    for _, ent in ipairs( ents.FindByClass( "ent_gpaint_*" ) ) do
        if ent.subscribers then
            ent.subscribers[id] = nil
        end
    end

    for _, c in pairs( cooldowns ) do
        c.players[id] = nil
    end
end )

local function ValidateMetadata( metadata, ply )
    -- Make sure the entity is a valid GPaint screen
    local ent = Entity( metadata.gpaint_entId )
    if not IsGPaintScreen( ent ) then return false end
    if not ent:CanPlayerDraw( ply ) then return false end

    -- Only allow whitelisted players to send screen data
    if not ent:CanPlayerDraw( ply ) then return false end

    -- If there's no requestId then just accept it
    local requestId = metadata.gpaint_requestId

    if type( requestId ) ~= "number" then
        return true, ent
    end

    -- Otherwide make sure the requestId is valid
    if not ent.requests then return false end

    local target = ent.requests[requestId]
    if not target then return false end

    return true, ent, requestId
end

hook.Add( "GPaint_AllowStream", "GPaint.FilterStreams", function( metadata, ply )
    if not metadata.gpaint_entId then return end

    local valid = ValidateMetadata( metadata, ply )
    return valid
end )

hook.Add( "GPaint_StreamCompleted", "GPaint.ScreenData", function( metadata, data, ply )
    if not metadata.gpaint_entId then return end

    local valid, ent, requestId = ValidateMetadata( metadata, ply )
    if not valid then return end

    if requestId then
        FulfillRequest( requestId, ent, data )

        return
    end

    local subs = GetSubscribers( ent, ply )
    if #subs == 0 then return end

    -- Send the image data to all subscribers
    local entId = ent:EntIndex()

    for _, p in ipairs( subs ) do
        local playerId = p:SteamID()

        GPaint.Transfer( data, { gpaint_entId = entId }, function( err )
            if err then GPaint.PrintF( "Failed to stream image data to %s: %s", playerId, err ) end
        end, p )
    end
end )
