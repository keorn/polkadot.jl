module Blockchain

export Chain, height, insert!

import Messages.height
import Base.insert!

using MicroLogging, BaseTypes, Messages

mutable struct Chain
  blocks::Dict{Hash, Header}
  head::Header
  Chain(config) = new(Dict(), Header(config, UInt(0), Timestamp(0), UInt(0)))
end

height(chain::Chain) = chain.head.height

function insert!(chain::Chain, block::Block)
  if block.header.height == height(chain) + 1
    chain.head = block.header
    chain.blocks[block.header.hash] = block.header
    true
  else
    @info "Failed to insert block $(block.header)"
    false
  end
end

end
