include("../network.jl")
include("types.jl")

using Distributions

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

function validating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
  while true
    message = yield(receive(endpoint))
    handle!(endpoint, spec, config, chain, table, message)
  end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
  while true
    yield(Timeout(sim, Float64(spec.view_duration)))
    if primary(spec, now(sim)) == config.engine_signer
      block = RelayBlock(config.engine_signer, now(sim), chain.height, proposal(table, chain.height))
      Process(broadcast, sim, endpoint, block)
      @info "$(now(sim)): $(config.engine_signer) broadcasted $(block.parablocks)"
    end
  end
end

function collating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain)
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

"Validator process."
function validator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::Address)
  blockchain = Blockchain()
  table = Table(spec.para_n, div(spec.validator_set.group_size * 2, 3))
  Process(validating!, sim, endpoint, spec, Config(engine_signer, UInt(0)), blockchain, table)
  Process(proposing, sim, endpoint, spec, Config(engine_signer, UInt(0)), blockchain, table)
end

"Collator process."
function collator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config)
  blockchain = Blockchain()
  Process(collating!, sim, endpoint, spec, config, blockchain)
end
