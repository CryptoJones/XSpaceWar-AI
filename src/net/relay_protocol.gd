class_name RelayProtocol
extends RefCounted
## Message types for the relay/master service (server/relay_server.gd).
##
## The relay is a plain ENet server. Game hosts REGISTER and get a 4-letter
## room code; clients LIST rooms (master/browser role) or JOIN a code, after
## which both sides exchange opaque game packets wrapped in FWD envelopes
## (relay role). Encoded with NetProtocol.pack/unpack; type ids live in a
## disjoint range from the game messages so a confused endpoint can never
## misparse one layer as the other.

const REGISTER := 101   ## host -> relay: {name, max, mode}
const ROOM := 102       ## relay -> host: {code}
const UPDATE := 103     ## host -> relay: {players} (heartbeat)
const LIST := 104       ## browser -> relay: {}
const SERVERS := 105    ## relay -> browser: {list: [{code,name,players,max,mode}]}
const JOIN := 106       ## client -> relay: {code}
const JOINED := 107     ## relay -> client: {ok, why?, code?}
const PEER := 108       ## relay -> host: {pid} (a client joined your room)
const LEAVE := 109      ## relay -> host: {pid} (client left/disconnected)
const FWD := 110        ## game data envelope: host {pid,ch,d} / client {ch,d}
const CLOSED := 111     ## relay -> client: {why} (room gone / kicked)
const KICK := 112       ## host -> relay: {pid}

const DEFAULT_PORT := 24645
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 4
