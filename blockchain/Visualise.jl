module Visualise

export v_c_relay_block, v_r_relay_block, v_c_para_block, v_r_para_block

using NodeConfig.Config

MAX_WIDTH = 10

display(s) = println(s)

whitestrwith(symbol::String, position::UInt) = string(repeat(" ", position), symbol, repeat(" ", MAX_WIDTH - position))
function offsets(v::Vector{UInt})
  v - vcat([0], v[1:end-1])
end
function whitestrwith(symbols::Dict{UInt, String})
  sorted = sort(collect(symbols), by=x->x[1])
  positions = [x[1] for x in sorted]
  content = [string(repeat(" ", p - 1), s) for (p, s) in zip(offsets(positions), [x[2] for x in symbols])]
  filler = repeat(" ", MAX_WIDTH - positions[end])
  string(content..., filler)
end
#=
function whitesectionsstrwith(sections::Dict{UInt, UInt}, section::UInt, symbol::String, position::UInt)
  whitestrwith(symbol)
end
=#
#v_validator_activity(config::Config, address::Address, height::UInt, activity::String) = 

v_c_relay_block(config::Config, height::UInt) = display(string(whitestrwith("!", config.chain_id), height))
v_r_relay_block(config::Config, height::UInt) = display(string(whitestrwith("0", config.chain_id), height))

v_c_para_block(config::Config, height::UInt) = display(string(whitestrwith(".", config.chain_id), height))
v_r_para_block(config::Config, chain_id::UInt, height::UInt) = display(string(whitestrwith(string(chain_id), config.chain_id), height))

end
