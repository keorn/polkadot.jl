include("message.jl")

mutable struct Blockchain
  height::UInt
  # TODO Keep track of forks.
  blocks::Vector{Block}
  Blockchain() = new(0, [])
end

function insert!(chain::Blockchain, block::Block)
  if block.header.height == chain.height + 1
    chain.height = block.header.height
    push!(chain.blocks, block)
    true
  else
    false
  end
end

