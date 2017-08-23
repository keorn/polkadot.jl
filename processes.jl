include("types.jl")

using SimJulia, Distributions

"All network connections."
mutable struct Network
	pipes::Dict{Address, Store}
	delay::Float64
	function Network(sim::Simulation, nodes::Vector{Address}, delay::Float64=0, capacity::UInt=typemax(UInt))
		@info "Starting the network with nodes $nodes"
		new(Dict(node => Store{Message}(sim, capacity) for node in nodes), delay)
	end
end

function new_connection(network::Network, node::Address)
	pipe = Store(network.sim, network.capacity)
	network.pipes[node] = pipe
	pipe
end

mutable struct NetworkEndpoint
	network::Network
	enode::Address
end

function broadcast(sim::Simulation, endpoint::NetworkEndpoint, value::Message)
	yield(Timeout(sim, endpoint.network.delay))
	[Put(pipe, value) for pipe in values(endpoint.network.pipes)]
end
function send(sim::Simulation, endpoint::NetworkEndpoint, destination::Address, value::Message)
	yield(Timeout(sim, endpoint.network.delay))
	Put(endpoint.network.pipes[destination], value)
end
function send(sim::Simulation, endpoint::NetworkEndpoint, destinations::Vector{Address}, value::Message)
	yield(Timeout(sim, endpoint.network.delay))
	[Put(endpoint.network.pipes[destination], value) for destination in destinations]
end
receive(endpoint::NetworkEndpoint) = Get(endpoint.network.pipes[endpoint.enode])

"Validator handling of a relay chain block."
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, relay::RelayBlock)
	insert!(chain, relay)
	@info "$(config.engine_signer) at block $(chain.height)"
	clean!(table)
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
			@info "$(now(sim)): $(config.engine_signer) broadcasted $block"
		end
	end
end

function collating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain)
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
