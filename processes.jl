using SimJulia, Distributions

abstract type Message end

struct Block{T} <: Message
	author::UInt
	timestamp::UInt
	body::T
	height::UInt
	function Block{T}(sim::Simulation, engine_signer::UInt, height::UInt, body::T) where T
		new(engine_signer, round(UInt, now(sim)), body, height + 1)
	end
end

const RelayBlock = Block{Vector{UInt}}
const ParaBlock = Block{UInt}

#const Message = Union{RelayBlock, ParaBlock}

struct ValidatorSet
	validators::Vector{UInt}
	validator_n::UInt
	ValidatorSet(validator_n::UInt) = new(rand(UInt, validator_n), validator_n)
end

get_validator(set::ValidatorSet, nonce::Int) = set.validators[nonce % set.validator_n + 1]

struct EngineSpec
	step_duration::UInt
	validator_set::ValidatorSet
end

function get_validator(spec::EngineSpec, time::Float64)
	get_validator(spec.validator_set, div(round(Int, time), spec.step_duration))
end

mutable struct Network
	pipes::Dict{UInt, Store}
	function Network(sim::Simulation, nodes::Vector{UInt}, capacity::UInt=typemax(UInt))
		println("Starting the network with nodes $nodes")
		new(Dict(node => Store{Message}(sim, capacity) for node in nodes))
	end
end

function new_connection(network::Network, node::UInt)
	pipe = Store(network.sim, network.capacity)
	network.pipes[node] = pipe
	pipe
end

mutable struct NetworkEndpoint
	network::Network
	enode::UInt
end

mutable struct Blockchain
	height::UInt
	blocks::Vector{Block}
	Blockchain() = new(0, [])
end

function broadcast(endpoint::NetworkEndpoint, value::Message)
	[Put(pipe, value) for pipe in values(endpoint.network.pipes)]
end
receive(endpoint::NetworkEndpoint) = Get(endpoint.network.pipes[endpoint.enode])

function validating!(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, chain::Blockchain)
	while true
		new_block = yield(receive(endpoint))
		if typeof(new_block) == RelayBlock
			chain.height = new_block.height
		else
			println("Ignoring para")
		end
		#println(now(sim), ": ", endpoint.enode, " received $new_block")
	end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::UInt, chain::Blockchain)
	while true
		yield(Timeout(sim, Float64(spec.step_duration)))
		println(now(sim), ": $engine_signer at block ", chain.height)
		if get_validator(spec, now(sim)) == engine_signer
			block = RelayBlock(sim, engine_signer, chain.height, rand(UInt, 2))
			broadcast(endpoint, block)
			println(now(sim), ": $engine_signer broadcasted $block")
		end
	end
end

function collating(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::UInt, chain::Blockchain)
	while true
		yield(Timeout(sim, Float64(spec.step_duration)))
		block = ParaBlock(sim, engine_signer, chain.height, rand(UInt))
		broadcast(endpoint, block)
	end
end

function validator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::UInt)
	blockchain = Blockchain()
	Process(validating!, sim, endpoint, spec, blockchain)
	Process(proposing, sim, endpoint, spec, engine_signer, blockchain)
end

function collator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::UInt)
	blockchain = Blockchain()
	Process(validating!, sim, endpoint, spec, blockchain)
	Process(collating, sim, endpoint, spec, engine_signer, blockchain)
end
