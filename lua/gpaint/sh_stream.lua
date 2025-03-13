--[[
    Network data stream utility.

    - Works in both server-client/client-server directions.
    - Both directions can be sending streams at once, but only one stream at a time.
    - The server handle sending/receiving one stream per player at the same time.
    - When a stream is completed, the receiving side runs the `GPaint_StreamCompleted` hook.
    - The receiving side gets custom metadata alongside the first chunk.
      That metadata can be used to deny streams, by returning `false` on the `GPaint_AllowStream` hook.
]]

-- Size limit for metadata sent alongside the first chunk
GPaint.MAX_METADATA_SIZE = 4096 -- 4 kibibytes

-- Size limit for a whole stream (excluding metadata)
GPaint.MAX_STREAM_SIZE = 262144 -- 256 kibibytes

-- Size limit for each stream chunk
GPaint.CHUNK_SIZE = 49152 -- 48 kibibytes

-- Limit the max. number of chunks
GPaint.MAX_CHUNKS = 16

-- If a chunk takes too long to transfer, it will cancel the stream
GPaint.CHUNK_TIMEOUT = 10 -- seconds

-- Chunk transfer responses
GPaint.RESPONSE_DENIED = 0
GPaint.RESPONSE_NEXT_CHUNK = 1
GPaint.RESPONSE_BAD_REQUEST = 2

-- Key-value table, where values are arrays of streams that will be sent per player, one at a time.
-- On CLIENT: Only the key "server" will exist, if there are streams to be sent
GPaint.writeQueue = GPaint.writeQueue or {}

-- Key-value table, where values are per-player streams.
-- On CLIENT: Only the key "server" will exist, if a stream is being received
GPaint.readQueue = GPaint.readQueue or {}

local writeQueue = GPaint.writeQueue
local readQueue = GPaint.readQueue

if SERVER then
    util.AddNetworkString( "gpaint.stream_chunk" )
    util.AddNetworkString( "gpaint.stream_response" )

    function GPaint.IsSendingStream( ply )
        return writeQueue[ply:SteamID()] ~= nil
    end

    function GPaint.IsReceivingStream( ply )
        return readQueue[ply:SteamID()] ~= nil
    end
end

if CLIENT then
    function GPaint.IsSendingStream()
        return writeQueue["server"] ~= nil
    end

    function GPaint.IsReceivingStream()
        return readQueue["server"] ~= nil
    end
end

local Compress = util.Compress
local ToJSON = util.TableToJSON

--- Begins a network data stream.
---
--- `data` is a string representing the stream data.
--- `metadata` is a table that will sent along with the first chunk.
---
--- `callback` is a function that gets called once a stream is completed/aborted.
--- If anything goes wrong, it's first argument will be one of these:
--- "data_too_big", "metadata_too_big", "bad_request", "denied", "timeout" or "aborted"
---
--- `target` (server only) is the player to send the data.
function GPaint.Transfer( data, metadata, callback, target )
    assert( type( data ) == "string", "Stream data must be a string!" )
    assert( type( metadata ) == "table", "Stream metadata must be a table!" )
    assert( type( callback ) == "function", "Stream callback must be a function!" )

    if SERVER then
        assert( IsValid( target ) and not target:IsBot(), "Stream target must be a valid human player!" )
    end

    local ws = {
        callback = callback,
        target = target,
        lastChunk = 0
    }

    -- Validate metadata
    ws.metadata = Compress( ToJSON( metadata, false ) )
    ws.metadataBytes = #ws.metadata

    if ws.metadataBytes > GPaint.MAX_METADATA_SIZE then
        callback( "metadata_too_big" )
        return
    end

    -- Validate data
    ws.data = Compress( data )

    if #ws.data > GPaint.MAX_STREAM_SIZE then
        callback( "data_too_big" )
        return
    end

    -- Add this WriteStream to the target's queue
    local playerId = SERVER and target:SteamID() or "server"
    local queue = writeQueue[playerId]

    if not queue then
        -- This player doesn't have a queue yet, so create one
        writeQueue[playerId] = {}
        queue = writeQueue[playerId]
    end

    queue[#queue + 1] = ws

    if not timer.Exists( "GPaint.ProcessQueue" ) then
        timer.Create( "GPaint.ProcessQueue", 0.05, 0, GPaint._ProcessQueue )
    end
end

local RealTime = RealTime

--- Process a WriteStream.
--- Returns `true` when finished.
local function ProcessWriteStream( ws )
    if ws.aborted then return true end

    -- Are we waiting for a response from the other side?
    if ws.chunkTimeout then
        -- Abort if it takes too long
        if RealTime() > ws.chunkTimeout then
            ws.callback( "timeout" )
            return true
        end

        return false
    end

    -- Abort if the target left the server
    if SERVER and not IsValid( ws.target ) then
        ws.callback( "aborted" )
        return true
    end

    local chunk = ws.lastChunk + 1

    if chunk > ws.chunkCount then
        ws.callback()
        return true -- this WriteStream has finished
    end

    ws.lastChunk = chunk
    ws.chunkTimeout = RealTime() + GPaint.CHUNK_TIMEOUT

    net.Start( "gpaint.stream_chunk", false )

    -- Send chunk data
    net.WriteUInt( chunk, 6 )
    net.WriteUInt( ws.chunkSizes[chunk], 16 )
    net.WriteData( ws.chunks[chunk] )

    -- Send metadata alongside the first chunk
    if chunk == 1 then
        net.WriteUInt( ws.chunkCount, 6 )
        net.WriteUInt( ws.metadataBytes, 16 )
        net.WriteData( ws.metadata )
    end

    if SERVER then
        net.Send( ws.target )
    else
        net.SendToServer()
    end

    return false
end

--- Process one stream at a time from this `queue`.
--- Returns `false` if there are no streams left to process.
local function ProcessWriteQueue( queue )
    if #queue == 0 then return false end

    local ws = queue[1]

    if ws.ready then
        if ProcessWriteStream( ws ) then
            -- This stream has finished
            table.remove( queue, 1 )
        end

        return #queue > 0
    end

    local CHUNK_SIZE = GPaint.CHUNK_SIZE

    -- Split the data into chunks
    ws.chunks = {}
    ws.chunkSizes = {}
    ws.chunkCount = math.ceil( string.len( ws.data ) / CHUNK_SIZE )

    for i = 1, ws.chunkCount do
        ws.chunks[i] = string.sub( ws.data, ( i - 1 ) * CHUNK_SIZE + 1, i * CHUNK_SIZE )
        ws.chunkSizes[i] = string.len( ws.chunks[i] )
    end

    ws.data = nil -- we don't need the original data anymore
    ws.ready = true -- ready to process next time this function is called

    return true
end

GPaint._ProcessQueue = function()
    local allDone = true

    for playerId, queue in pairs( writeQueue ) do
        if ProcessWriteQueue( queue ) then
            allDone = false -- don't stop processing just yet
        else
            writeQueue[playerId] = nil -- finished all WriteStreams for this player
        end
    end

    if allDone then
        timer.Remove( "GPaint.ProcessQueue" )
    end
end

net.Receive( "gpaint.stream_response", function( _, ply )
    local response = net.ReadUInt( 3 )
    local playerId = SERVER and ply:SteamID() or "server"
    local queue = writeQueue[playerId]

    if not queue then
        GPaint.PrintF( "Received stream response while no streams was active for %s", playerId )
        return
    end

    local ws = queue[1]

    if not ws or not ws.ready or not ws.chunkTimeout then
        GPaint.PrintF( "Received stream response while we were not waiting one from %s", playerId )
        return
    end

    if response == GPaint.RESPONSE_DENIED then
        ws.callback( "denied" )
        ws.aborted = true

    elseif response == GPaint.RESPONSE_NEXT_CHUNK then
        ws.chunkTimeout = nil

    elseif response == GPaint.RESPONSE_BAD_REQUEST then
        ws.callback( "bad_request" )
        ws.aborted = true
    end
end )

local function SendResponse( response, ply )
    net.Start( "gpaint.stream_response", false )
    net.WriteUInt( response, 3 )

    if SERVER then
        net.Send( ply )
    else
        net.SendToServer()
    end
end

local Decompress = util.Decompress
local ToTable = util.JSONToTable

net.Receive( "gpaint.stream_chunk", function( _, ply )
    -- Read and validate chunk data
    local chunkIndex = net.ReadUInt( 6 )
    local chunkBytes = net.ReadUInt( 16 )

    if chunkBytes > GPaint.CHUNK_SIZE then
        GPaint.PrintF( "Tried to read stream chunk that was too big! (%d/%d)", chunkBytes, GPaint.CHUNK_SIZE )
        return
    end

    local chunkData = net.ReadData( chunkBytes )
    local playerId = SERVER and ply:SteamID() or "server"
    local rs = readQueue[playerId]

    if not rs then
        -- This stream is new, are we receiving the first chunk?
        if chunkIndex ~= 1 then
            GPaint.PrintF( "Received stream chunk #%d without the previous chunk(s) from %s", chunkIndex, playerId )
            SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

            return
        end

        -- Make sure the chunk count is within a limit
        local chunkCount = net.ReadUInt( 6 )

        if chunkCount > GPaint.MAX_CHUNKS then
            GPaint.PrintF( "Tried to read stream that had too many chunks! (%d/%d)", chunkCount, GPaint.MAX_CHUNKS )
            SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

            return
        end

        -- Make sure the metadata size is within a limit
        local metadataBytes = net.ReadUInt( 16 )

        if metadataBytes > GPaint.MAX_METADATA_SIZE then
            GPaint.PrintF( "Tried to read stream metadata that was too big! (%d/%d)", metadataBytes, GPaint.MAX_METADATA_SIZE )
            SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

            return
        end

        local metadata = net.ReadData( metadataBytes )

        metadata = Decompress( metadata )

        if not metadata then
            GPaint.PrintF( "Unable to decompress stream metadata!" )
            SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

            return
        end

        metadata = ToTable( metadata )

        if not metadata then
            GPaint.PrintF( "Unable to parse stream metadata!" )
            SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

            return
        end

        -- Should we accept this stream?
        local accept = hook.Run( "GPaint_AllowStream", metadata, ply )

        if accept ~= true then
            SendResponse( GPaint.RESPONSE_DENIED, ply )

            return
        end

        -- Prepare a new ReadStream
        rs = {
            metadata = metadata,
            chunkCount = chunkCount,
            lastChunk = 0,
            chunks = {}
        }

        readQueue[playerId] = rs
    end

    -- Continue receiving chunks
    local expectedChunk = rs.lastChunk + 1

    if expectedChunk ~= chunkIndex then
        readQueue[playerId] = nil

        GPaint.PrintF( "Received out-of-order chunk (expected #%d, got #%d)", expectedChunk, chunkIndex )
        SendResponse( GPaint.RESPONSE_BAD_REQUEST, ply )

        return
    end

    rs.lastChunk = chunkIndex
    rs.chunks[chunkIndex] = chunkData

    if chunkIndex == rs.chunkCount then
        -- We received it all!
        local data = Decompress( table.concat( rs.chunks ) )
        hook.Run( "GPaint_StreamCompleted", rs.metadata, data, ply )

        readQueue[playerId] = nil
    end

    SendResponse( GPaint.RESPONSE_NEXT_CHUNK, ply )
end )
