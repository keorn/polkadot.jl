include("basic_types.jl")

struct ValidatorSet
  validators::Vector{Address}
  validator_n::UInt
  group_size::UInt
  ValidatorSet(validator_n::UInt, group_n::UInt) = new(rand(Address, validator_n), validator_n, div(validator_n, group_n))
end

validator(set::ValidatorSet, nonce::UInt) = set.validators[nonce % set.validator_n + 1]
function group(set::ValidatorSet, nonce::UInt, nth::UInt)
  [validator(set, i) for i in nonce + (nth - 1) * set.group_size:nonce + nth * set.group_size - 1]
end
