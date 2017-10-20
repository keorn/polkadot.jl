include("message.jl")

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
function proposal(config::Config, table::Table, height::UInt, time::Timestamp)
  if primary(config.spec, time) == config.engine_signer
    Nullable(RelayBlock(config, time, height, proposal(table, height)))
  else
    Nullable()
  end
end
isvalid(table::Table, header::Header) = !in(header, table.invalid) && get(table.validity, header, 0) >= table.threshold
isvalid(table::Table, relay::RelayBlock) = all(b -> isnull(b) || isvalid(table, get(b)), relay.parablocks)
