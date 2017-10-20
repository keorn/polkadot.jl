include("config.jl")

abstract type Block <: Message end

struct Header
  author::Address
  timestamp::Timestamp
  height::UInt
  hash::UInt
  chain::UInt
  is_valid::Bool
  function Header(config::Config, time::Timestamp, height::UInt)
    new(config.engine_signer, time, height + 1, rand(UInt), config.chain_id, !config.malicious)
  end
end

"Relay chain block."
struct RelayBlock <: Block
  header::Header
  parablocks::Vector{Nullable{Header}}
  function RelayBlock(config::Config, time::Timestamp, height::UInt, parablocks::Vector{Nullable{Header}})
    new(Header(config, time, height), parablocks)
  end
end
"Parachain block."
struct ParaBlock <: Block
  header::Header
  function ParaBlock(config::Config, time::Float64, height::UInt)
    new(Header(config, Timestamp(time), height))
  end
end

"Claim made by a validator."
abstract type Statement <: Message end

"Claim that given block is available."
struct Available <: Statement
  from::Address
  block::Header
end

"Claim that given block is valid or invalid."
struct Valid <: Statement
  from::Address
  block::Header
  is_valid::Bool
end

function reaction(config::Config, para::ParaBlock)
  if config.engine_signer in paragroup(config.spec, para.header.timestamp, para.header.chain)
    Valid(config.engine_signer, para.header, para.header.is_valid)
  else
    Available(config.engine_signer, para.header)
  end
end
