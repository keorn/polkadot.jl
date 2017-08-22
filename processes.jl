using SimJulia, Distributions

const Address = UInt

struct Config
	engine_signer::Address
	chain_id::UInt
end

abstract type Message end

abstract type Block <: Message end

struct Header
	author::Address
	timestamp::UInt
	height::UInt
	hash::UInt
	chain::UInt
	is_valid::Bool
	function Header(sim::Simulation, config::Config, height::UInt)
		new(config.engine_signer, round(UInt, now(sim)), height + 1, rand(UInt), config.chain_id, true)
	end
end

struct RelayBlock <: Block
	header::Header
	parablocks::Vector{Header}
	function RelayBlock(sim::Simulation, engine_signer::Address, height::UInt, parablocks::Vector{Header})
		new(Header(sim, Config(engine_signer, UInt(0)), height), parablocks)
	end
end
struct ParaBlock <: Block
	header::Header
	function ParaBlock(sim::Simulation, config::Config, height::UInt)
		new(Header(sim, config, height))
	end
end

abstract type Statement <: Message end

struct Available <: Statement
	from::Address
	block::Header
end

struct Valid <: Statement
	from::Address
	block::Header
	is_valid::Bool
end

view(time::Number, view_duration::UInt) = div(round(UInt, abs(time)), view_duration)

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

mutable struct Network
	pipes::Dict{Address, Store}
	function Network(sim::Simulation, nodes::Vector{Address}, capacity::UInt=typemax(UInt))
		println("Starting the network with nodes $nodes")
		new(Dict(node => Store{Message}(sim, capacity) for node in nodes))
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

function broadcast(endpoint::NetworkEndpoint, value::Message)
	[Put(pipe, value) for pipe in values(endpoint.network.pipes)]
end
send(endpoint::NetworkEndpoint, destination::Address, value::Message) = Put(endpoint.network.pipes[destination], value)
send(endpoint::NetworkEndpoint, destinations::Vector{Address}, value::Message) = [Put(endpoint.network.pipes[destination], value) for destination in destinations]
receive(endpoint::NetworkEndpoint) = Get(endpoint.network.pipes[endpoint.enode])

mutable struct Blockchain
	height::UInt
	blocks::Vector{Block}
	Blockchain() = new(0, [])
end

function insert!(chain::Blockchain, block::Block)
	chain.height = block.header.height
	push!(chain.blocks, block)
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

mutable struct Table
	blocks::Dict{Header, Statements}
	Table() = new(Dict())
end

insert!(table::Table, statement::Statement) = insert!(get!(table.blocks, statement.block, Statements()), statement)
proposal(table::Table)::Vector{Header} = collect(keys(table.blocks))

handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, relay::RelayBlock) = insert!(chain, relay)
function handle!(endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table, para::ParaBlock)
	broadcast(endpoint, Available(config.engine_signer, para.header))
	if config.engine_signer in paragroup(spec, para.header.timestamp, config.chain_id)
		broadcast(endpoint, Valid(config.engine_signer, para.header, para.header.is_valid))
	end
end
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
		#println(now(sim), ": ", endpoint.enode, " received $new_block")
	end
end

function proposing(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain, table::Table)
	while true
		yield(Timeout(sim, Float64(spec.view_duration)))
		println(now(sim), ": $config at block ", chain.height)
		if primary(spec, now(sim)) == config.engine_signer
			block = RelayBlock(sim, config.engine_signer, chain.height, proposal(table))
			broadcast(endpoint, block)
			println(now(sim), ": $config broadcasted $block")
		end
	end
end

function collating(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config, chain::Blockchain)
	while true
		yield(Timeout(sim, Float64(spec.view_duration)))
		block = ParaBlock(sim, config, chain.height)
		send(endpoint, paragroup(spec, now(sim), config.chain_id), block)
	end
end

function validator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, engine_signer::Address)
	blockchain = Blockchain()
	table = Table()
	Process(validating!, sim, endpoint, spec, Config(engine_signer, UInt(0)), blockchain, table)
	Process(proposing, sim, endpoint, spec, Config(engine_signer, UInt(0)), blockchain, table)
end

function collator(sim::Simulation, endpoint::NetworkEndpoint, spec::EngineSpec, config::Config)
	blockchain = Blockchain()
	Process(validating!, sim, endpoint, spec, blockchain)
	Process(collating, sim, endpoint, spec, config, blockchain)
end

sim = Simulation()
set = ValidatorSet(UInt(3), UInt(1))
collators = rand(UInt, 2)
network = Network(sim, vcat(set.validators, collators))
spec = EngineSpec(5, 1, set)
for i in 1:3
    validator(sim, NetworkEndpoint(network, set.validators[i]), spec, set.validators[i])
end
collator(sim, NetworkEndpoint(network, collators[1]), spec, Config(collators[1], UInt(1)))

SIM_TIME = 100.0

run(sim, SIM_TIME)
