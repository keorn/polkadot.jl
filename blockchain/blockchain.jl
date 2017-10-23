include("message.jl")

mutable struct Blockchain
  blocks::Dict{Hash, Header}
  head::Header
  Blockchain(config) = new(Dict(), Header(config, UInt(0), Timestamp(0), UInt(0)))
end

height(chain::Blockchain) = chain.head.height

function insert!(chain::Blockchain, block::Block)
  if block.header.height == height(chain) + 1
    chain.head = block.header
    chain.blocks[block.header.hash] = block.header
    true
  else
    @info "Failed to insert block $(block.header)"
    false
  end
end
