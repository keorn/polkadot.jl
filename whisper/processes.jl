include("../network.jl")
include("types.jl")

"Validator handling of a relay chain block."
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, relay::RelayBlock)
  if all(b -> isnull(b) || isvalid(table, get(b)), relay.parablocks)
    insert!(chain, relay)
    @info "$(config.engine_signer) at block $(chain.height)"
    clean!(table)
  end
end
"Validator handling of a parachain block."
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, para::ParaBlock)
  if config.engine_signer in paragroup(spec, para.header.timestamp, para.header.chain)
    Process(broadcast, sim, endpoint, Valid(config.engine_signer, para.header, para.header.is_valid))
  else
    Process(broadcast, sim, endpoint, Available(config.engine_signer, para.header))
  end
end
"Validator handling of a statement."
handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, statement::Statement) = insert!(table, statement)

function broadcasting(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain)
  block = ParaBlock(config, now(sim), chain.height)
  Process(send, sim, endpoint, paragroup(spec, now(sim), config.chain_id), block)
  while true
    new_block = yield(receive(endpoint))
    if isa(new_block, RelayBlock)
      insert!(chain, new_block)
      block = ParaBlock(config, now(sim), chain.height)
      Process(send, sim, endpoint, paragroup(spec, now(sim), config.chain_id), block)
    end
  end
end

function listening(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
  while true
    packet = yield(receive(endpoint))
    handle(endpoint, config, packet)
  end
end

function node(sim::Simulation, endpoint::NetworkEndpoint, config::Config)
  Process(broadcasting, sim, endpoint, config)
  Process(listening, sim, endpoint, config)
end
