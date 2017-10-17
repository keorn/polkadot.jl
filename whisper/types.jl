using MicroLogging, Distributions

include("../types.jl")

const Topic = UInt

"Node specific config."
struct Config
  enode::NodeId
  broadcast::Categorical
  listen::Set{Topic}
end

struct Packet <: Message
  topic::Topic
  content::UInt
  Packet(config::Config) = new(rand(config.broadcast), rand(UInt))
end

is_interesting(config::Config, packet::Packet) = packet.topic in config.listen
