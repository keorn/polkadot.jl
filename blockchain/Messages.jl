module Messages

export Header, Block, RelayBlock, ParaBlock, height, Statement, Valid, Available, reaction

using BaseTypes, ValidatorSet, NodeConfig, Visualise

abstract type Block <: Message end

struct Header
  author::Address
  timestamp::Timestamp
  height::UInt
  hash::Hash
  parent_hash::Hash
  chain::UInt
  is_valid::Bool
  function Header(config::Config, parent_hash::Hash, time::Timestamp, height::UInt)
    new(config.engine_signer, time, height + 1, rand(UInt), parent_hash, config.chain_id, !config.malicious.invalid_blocks)
  end
end

"Relay chain block."
struct RelayBlock <: Block
  header::Header
  validators::Validators
  parablocks::Vector{Nullable{Header}}
  function RelayBlock(config::Config, parent::Header, time::Timestamp, height::UInt, parablocks::Vector{Nullable{Header}})
    new(Header(config, parent.hash, time, height), config.spec.validator_set, parablocks)
  end
end
"Parachain block."
struct ParaBlock <: Block
  header::Header
  function ParaBlock(config::Config, parent_hash::Hash, time::Float64, height::UInt)
    new(Header(config, parent_hash, Timestamp(time), if config.malicious.double_proposal height - 1 else height end))
  end
end

height(block::Block) = block.header.height

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
  v_r_para_block(config, para.header.chain, height(para))
  if config.engine_signer in paragroup(config.spec, para.header.timestamp, para.header.chain)
    Valid(config.engine_signer, para.header, para.header.is_valid)
  else
    Available(config.engine_signer, para.header)
  end
end

end
