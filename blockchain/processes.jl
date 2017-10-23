include("../network.jl")
include("blockchain.jl")
include("table.jl")

using Distributions

"Validator handling of a relay chain block."
function handle!(endpoint::NetworkEndpoint, config::Config, chain::Blockchain, table::Table, relay::RelayBlock)
  if isvalid(table, relay)
    insert!(chain, relay)
    @info "$(config.engine_signer) at block $(height(chain))"
    clean!(table)
  end
end
"Validator handling of a parachain block."
function handle!(endpoint::NetworkEndpoint, config::Config, chain::Blockchain, table::Table, para::ParaBlock)
  Process(broadcast, sim, endpoint, reaction(config, para))
end
"Validator handling of a statement."
handle!(endpoint::NetworkEndpoint, config::Config, chain::Blockchain, table::Table, statement::Statement) = insert!(table, statement)

function validating!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Blockchain, table::Table)
  while true
    message = yield(receive(endpoint))
    handle!(endpoint, config, chain, table, message)
  end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Blockchain, table::Table)
  while true
    yield(Timeout(sim, Float64(config.spec.view_duration)))
    block = proposal(config, chain.head.hash, table, height(chain), Timestamp(now(sim)))
    if !isnull(block)
      Process(broadcast, sim, endpoint, get(block))
      @info "$(now(sim)): $(config.engine_signer) broadcasted $(get(block).parablocks)"
    end
  end
end

function collating!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Blockchain)
  block = ParaBlock(config, chain.head.hash, now(sim), height(chain))
  Process(send, sim, endpoint, paragroup(config.spec, now(sim), config.chain_id), block)
  while true
    new_block = yield(receive(endpoint))
    if isa(new_block, RelayBlock)
      insert!(chain, new_block)
      block = ParaBlock(config, chain.head.hash, now(sim), height(chain))
      Process(send, sim, endpoint, paragroup(config.spec, now(sim), config.chain_id), block)
    end
  end
end

"Validator process."
function start_validator(sim::Simulation, endpoint::NetworkEndpoint, config::Config)
  blockchain = Blockchain(config)
  table = Table(config.spec.para_n, div(config.spec.validator_set.group_size * 2, 3))
  Process(validating!, sim, endpoint, config, blockchain, table)
  Process(proposing, sim, endpoint, config, blockchain, table)
end

"Collator process."
function start_collator(sim::Simulation, endpoint::NetworkEndpoint, config::Config)
  blockchain = Blockchain(config)
  Process(collating!, sim, endpoint, config, blockchain)
end
