include("types.jl")

"Validator handling of a relay chain block."
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, relay::RelayBlock)
	insert!(chain, relay)
	clean!(table)
end
"Validator handling of a parachain block."
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, para::ParaBlock)
	if config.engine_signer in paragroup(spec, para.header.timestamp, config.chain_id)
		broadcast(endpoint, Valid(config.engine_signer, para.header, para.header.is_valid))
	else
		broadcast(endpoint, Available(config.engine_signer, para.header))
	end
end
"Validator handling of a statement."
handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, statement::Statement) = insert!(table, statement)

function validating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, chain::Blockchain)
	while true
		new_block = yield(receive(endpoint))
		if isa(new_block, RelayBlock)
			insert!(chain, new_block)
		end
	end
end

function validating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
	while true
		message = yield(receive(endpoint))
		handle!(endpoint, spec, config, chain, table, message)
	end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
	while true
		yield(Timeout(sim, Float64(spec.view_duration)))
		@info "$(now(sim)): $(config.engine_signer) at block $(chain.height)"
		if primary(spec, now(sim)) == config.engine_signer
			block = RelayBlock(sim, config.engine_signer, chain.height, proposal(table, chain.height))
			broadcast(endpoint, block)
			@info "$(now(sim)): $(config.engine_signer) broadcasted $block"
		end
	end
end

function collating(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain)
	while true
		yield(Timeout(sim, Float64(spec.view_duration)))
		block = ParaBlock(sim, config, chain.height + 1)
		send(endpoint, paragroup(spec, now(sim), config.chain_id), block)
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
	Process(validating!, sim, endpoint, spec, blockchain)
	Process(collating, sim, endpoint, spec, config, blockchain)
end
