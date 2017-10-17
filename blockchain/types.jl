using MicroLogging

include("../types.jl");

const Address = UInt
const Timestamp = UInt
Timestamp(time::Float64) = round(UInt, time)

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

"Relay chain view."
view(time::Number, view_duration::UInt) = div(Timestamp(time), view_duration)
view(time::UInt, view_duration::UInt) = div(time, view_duration)

"Specification of the consensus engine."
struct EngineSpec
  view_duration::UInt
  para_n::UInt
  validator_set::ValidatorSet
end

function primary(spec::EngineSpec, time::Float64)::Address
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
  function RelayBlock(config::Config, time::Float64, height::UInt, parablocks::Vector{Nullable{Header}})
    new(Header(config, Timestamp(time), height), parablocks)
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

mutable struct Statements
  invalid::Bool
  valid::UInt
  available::UInt
  Statements() = new(false, 0, 0)
end

insert!(statements::Statements, statement::Available) = statements.available += 1
function insert!(statements::Statements, statement::Valid)
  statements.available += 1
  if statement.is_valid
    statements.valid += 1
  else
    statements.invalid = true
  end
end

"Validity and availability table used to make decisions about block proposals."
mutable struct Table
  chains::UInt
  threshold::UInt
  validity::Dict{Header, UInt}
  availability::Dict{Header, UInt}
  seen::Set{Statement}
  invalid::Set{Header}
  Table(chains::UInt, threshold::UInt) = new(chains, threshold, Dict(), Dict(), Set(), Set())
end

function clean!(table::Table)
  table.validity = Dict()
  table.availability = Dict()
end
function insert_new!(table::Table, available::Available)
  current = get!(table.availability, available.block, UInt(1))
  table.availability[available.block] = current + 1
end
"Add vailidity claim or instantly mark as invalid."
function insert_new!(table::Table, valid::Valid)
  if valid.is_valid
    insert!(table, Available(valid.from, valid.block))
    current = get!(table.validity, valid.block, UInt(1))
    table.validity[valid.block] = current + 1
  else
    push!(table.invalid, valid.block)
  end
end
"Handle only statements that have not been seen and do not pertain to a known invalid header."
function insert!(table::Table, statement::Statement)
  if !in(statement, table.seen) && !in(statement.block, table.invalid)
    insert_new!(table, statement)
    push!(table.seen, statement)
  end
end

"""
Relay block proposal formed of paraheaders.
Each header has at least 2/3 validity from a group
and has the most availability statements.
Parachain for which there is no valid block present gets a Null header.
"""
function proposal(table::Table, height::UInt)
  criterium = h -> h.height == height + 1 && !in(h, table.invalid) && get(table.validity, h, 0) >= table.threshold
  good = Iterators.filter(criterium, keys(table.availability))
  proposal = fill(Nullable{Header}(), table.chains)
  for h in good
    current = proposal[h.chain]
    if isnull(current) || table.availability[get(current)] < table.availability[h]
      proposal[h.chain] = Nullable(h)
    end
  end
  proposal
end
isvalid(table::Table, header::Header) = !in(header, table.invalid) && get(table.validity, header, 0) >= table.threshold
