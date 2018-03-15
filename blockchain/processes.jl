include("../SimNetwork.jl")
include("Blockchain.jl")

module Processes

export start_collator, start_validator

include("table.jl")

using Distributions, SimJulia, SimNetwork, NodeConfig, Blockchain, Visualise

"Validator handling of a relay chain block."
function handle!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain, table::Table, relay::RelayBlock)
  if isvalid(table, relay)
    insert!(chain, relay)
    v_r_relay_block(config, height(relay))
    clean!(table)
  end
end
"Validator handling of a parachain block."
function handle!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain, table::Table, para::ParaBlock)
  Process(SimNetwork.broadcast, sim, endpoint, reaction(config, para))
end
"Validator handling of a statement."
handle!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain, table::Table, statement::Statement) = insert!(table, statement)

function validating!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain, table::Table)
  while true
    message = yield(receive(endpoint))
    handle!(sim, endpoint, config, chain, table, message)
  end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain, table::Table)
  while true
    yield(Timeout(sim, Float64(config.spec.view_duration)))
    block = proposal(config, chain.head, table, height(chain), Timestamp(now(sim)))
    if !isnull(block)
      Process(SimNetwork.broadcast, sim, endpoint, get(block))
      #@info "$(now(sim)): $(config.engine_signer) broadcasted $(get(block).parablocks)"
    end
  end
end

function collating!(sim::Simulation, endpoint::NetworkEndpoint, config::Config, chain::Chain)
  block = ParaBlock(config, chain.head.hash, now(sim), height(chain))
  Process(SimNetwork.send, sim, endpoint, paragroup(config.spec, now(sim), config.chain_id), block)
  while true
    new_block = yield(receive(endpoint))
    if isa(new_block, RelayBlock)
      insert!(chain, new_block)
      block = ParaBlock(config, chain.head.hash, now(sim), height(chain))
      v_r_relay_block(config, height(block))
      v_c_para_block(config, height(block))
      Process(SimNetwork.send, sim, endpoint, paragroup(config.spec, now(sim), config.chain_id), block)
    end
  end
end

"Validator process."
function start_validator(sim::Simulation, endpoint::NetworkEndpoint, config::Config)
  blockchain = Chain(config)
  table = Table(config.spec.para_n, div(config.spec.validator_set.group_size * 2, 3))
  Process(validating!, sim, endpoint, config, blockchain, table)
  Process(proposing, sim, endpoint, config, blockchain, table)
end

"Collator process."
function start_collator(sim::Simulation, endpoint::NetworkEndpoint, config::Config)
  blockchain = Chain(config)
  Process(collating!, sim, endpoint, config, blockchain)
end

end
