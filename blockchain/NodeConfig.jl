module NodeConfig

export EngineSpec, Malicious, Config, primary, paragroup

using BaseTypes, ValidatorSet

"Specification of the consensus engine."
struct EngineSpec
  view_duration::UInt
  "Number of parachains."
  para_n::UInt
  validator_set::Validators
end

"Relay chain view."
view(time::Number, view_duration::UInt) = div(Timestamp(time), view_duration)
view(time::UInt, view_duration::UInt) = div(time, view_duration)

function primary(spec::EngineSpec, time::Timestamp)::Address
  ValidatorSet.validator(spec.validator_set, view(time, spec.view_duration))
end
function paragroup(spec::EngineSpec, time::Number, para::UInt)
  ValidatorSet.group(spec.validator_set, view(time, spec.view_duration), para)
end

struct Malicious
  invalid_blocks::Bool
  double_proposal::Bool
end

"Node specific config."
struct Config
  spec::EngineSpec
  engine_signer::Address
  chain_id::UInt
  malicious::Malicious
  Config(spec, engine_signer, chain=0, malicious=Malicious(false, false)) = new(spec, engine_signer, chain, malicious)
end

end
