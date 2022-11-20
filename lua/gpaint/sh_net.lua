local network = {
    -- size limit when streaming images over the network
    MAX_DATA_SIZE = 262144, -- 256 kibibytes

    -- max. number of strokes on a net message
    MAX_STROKES = 15,

    -- used in net.WriteUInt when sending commands
    COMMAND_SIZE = 3,

    -- command IDs
    SUBSCRIBE = 0,
    UNSUBSCRIBE = 1,
    CLEAR = 2,
    PEN_STROKES = 3,
    SEND_DATA = 4,
    BROADCAST_DATA = 5,
    REQUEST_DATA = 6,
    AWAIT_DATA = 7 -- max. value when COMMAND_SIZE == 3
}

function network.StartCommand( id, entity )
    net.Start( 'gpaint.command', false )
    net.WriteEntity( entity )
    net.WriteUInt( id, network.COMMAND_SIZE )
end

function network.WriteStrokes( strokes )
    local count = math.min( #strokes, network.MAX_STROKES )

    net.WriteUInt( count, 5 )

    for i = 1, count do
        local st = strokes[i]

        -- start pos
        net.WriteUInt( st[1], 10 )
        net.WriteUInt( st[2], 10 )

        -- end pos
        net.WriteUInt( st[3], 10 )
        net.WriteUInt( st[4], 10 )

        -- thickness
        net.WriteUInt( st[5], 8 )

        -- r, g, b
        net.WriteUInt( st[6], 8 )
        net.WriteUInt( st[7], 8 )
        net.WriteUInt( st[8], 8 )
    end
end

function network.ReadStrokes()
    local count = math.min( net.ReadUInt( 5 ), network.MAX_STROKES )
    if count < 1 then return {} end

    local strokes = {}

    for i = 1, count do
        strokes[i] = {
            -- start pos
            net.ReadUInt( 10 ),
            net.ReadUInt( 10 ),

            -- end pos
            net.ReadUInt( 10 ),
            net.ReadUInt( 10 ),

            -- thickness
            net.ReadUInt( 8 ),

            -- r, g, b
            net.ReadUInt( 8 ),
            net.ReadUInt( 8 ),
            net.ReadUInt( 8 )
        }
    end

    return strokes
end

-- TODO: detect if gm_express is available & use it

function network.WriteImage( data, callback )
    return net.WriteStream( data, callback )
end

function network.ReadImage( ply, callback )
    return net.ReadStream( ply, callback )
end

GPaint.network = network