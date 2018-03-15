module BaseTypes

export Hash, Timestamp, NodeId, Address, Message

const Hash = UInt
const Timestamp = UInt
Timestamp(time::Float64) = round(UInt, time)
const NodeId = UInt
const Address = UInt
"Anything that can be passed through the network."
abstract type Message end

end
