module ValidatorSet

export Validators

using BaseTypes

struct Validators
  validators::Vector{Address}
  validator_n::UInt
  group_size::UInt
  Validators(validator_n::UInt, group_n::UInt) = new(collect(1:validator_n), validator_n, div(validator_n, group_n))
end

validator(set::Validators, nonce::UInt) = set.validators[nonce % set.validator_n + 1]
function group(set::Validators, nonce::UInt, nth::UInt)
  [validator(set, i) for i in nonce + (nth - 1) * set.group_size:nonce + nth * set.group_size - 1]
end

end
