using SimJulia, Distributions, MicroLogging

const Address = UInt

"Node specific config."
struct Config
	engine_signer::Address
	chain_id::UInt
end

"Anything that can be passed through the network."
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

"Relay chain block."
struct RelayBlock <: Block
	header::Header
	parablocks::Vector{Nullable{Header}}
	function RelayBlock(sim::Simulation, engine_signer::Address, height::UInt, parablocks::Vector{Nullable{Header}})
		new(Header(sim, Config(engine_signer, UInt(0)), height), parablocks)
	end
end
"Parachain block."
struct ParaBlock <: Block
	header::Header
	function ParaBlock(sim::Simulation, config::Config, height::UInt)
		new(Header(sim, config, height))
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

"Relay chain view."
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

"All network connections."
mutable struct Network
	pipes::Dict{Address, Store}
	function Network(sim::Simulation, nodes::Vector{Address}, capacity::UInt=typemax(UInt))
		@info "Starting the network with nodes $nodes"
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

"Validity and availability table used to make decisions about block proposals."
mutable struct Table
	chains::UInt
	threshold::UInt
	validity::Dict{Header, UInt}
	availability::Dict{Header, UInt}
	seen::Set{Statement}
	invalid::Set{Header}
	Table(chains::UInt, threshold::UInt) = new(chains, threshold, Dict(), Dict())
end

function clean!(table::Table)
	table.validity = Dict()
	table.availability = Dict()
end
function insert_new!(table::Table, available::Available)
	current = get!(table.availability, available.block, UInt(1))
	table.availability[available.block] = current + 1
end
function insert_new!(table::Table, valid::Valid)
	if valid.is_valid
		insert!(table, Available(valid.from, valid.block))
		current = get!(table.validity, valid.block, UInt(1))
		table.validity[valid.block] = current + 1
	else
		insert!(table.invalid, valid.block)
	end
end
function insert!(table::Table, statement::Statement)
	if !in(statement, table.seen) && !in(statement.block, invalid)
		insert_new!(table, statement)
		insert!(table.seen, statement)
	end
end
function proposal(table::Table, height::UInt)
	criterium = h -> h.height == height && !in(h, table.invalid) && get(table.validity, h, 0) >= table.threshold
	good = Iterators.filter(criterium, keys(table.availability))
	proposal = fill(Nullable{Header}(), table.chains)
	for h in good
		current = proposal[h.chain_id]
		if isnull(current) || table.availability[get(current)] < table.availability[h]
			proposal[h.chain_id] = Nullable(h)
		end
	end
	proposal
end
