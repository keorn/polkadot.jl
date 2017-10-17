using SimJulia

include("types.jl");

const NodeId = UInt

"All network connections."
mutable struct Network
  pipes::Dict{NodeId, Store}
  delay::Float64
  function Network(sim::Simulation, nodes::Vector{NodeId}, delay::Float64=0, capacity::UInt=typemax(UInt))
    @info "Starting the network with nodes $nodes"
    new(Dict(node => Store{Message}(sim, capacity) for node in nodes), delay)
  end
end

"Add a network node."
function new_connection(network::Network, node::NodeId)
  pipe = Store(network.sim, network.capacity)
  network.pipes[node] = pipe
  pipe
end

mutable struct NetworkEndpoint
  network::Network
  enode::NodeId
end

function broadcast(sim::Simulation, endpoint::NetworkEndpoint, value::Message)
  yield(Timeout(sim, endpoint.network.delay))
  [Put(pipe, value) for pipe in values(endpoint.network.pipes)]
end
function send(sim::Simulation, endpoint::NetworkEndpoint, destination::NodeId, value::Message)
  yield(Timeout(sim, endpoint.network.delay))
  Put(endpoint.network.pipes[destination], value)
end
function send(sim::Simulation, endpoint::NetworkEndpoint, destinations::Vector{NodeId}, value::Message)
  yield(Timeout(sim, endpoint.network.delay))
  [Put(endpoint.network.pipes[destination], value) for destination in destinations]
end
receive(endpoint::NetworkEndpoint) = Get(endpoint.network.pipes[endpoint.enode])
