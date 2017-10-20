include("basic_types.jl")
include("validator_set.jl")

"Specification of the consensus engine."
struct EngineSpec
  view_duration::UInt
  para_n::UInt
  validator_set::ValidatorSet
end

function primary(spec::EngineSpec, time::Timestamp)::Address
  validator(spec.validator_set, view(time, spec.view_duration))
end
function paragroup(spec::EngineSpec, time::Number, para::UInt)
  group(spec.validator_set, view(time, spec.view_duration), para)
end

"Node specific config."
struct Config
  spec::EngineSpec
  engine_signer::Address
  chain_id::UInt
  malicious::Bool
  Config(spec, engine_signer, chain=0, malicious=false) = new(spec, engine_signer, chain, malicious)
end
