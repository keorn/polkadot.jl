include("../BaseTypes.jl")
include("ValidatorSet.jl")
include("NodeConfig.jl")
include("Visualise.jl")
include("Messages.jl")
include("processes.jl")

using ValidatorSet, NodeConfig, Processes, SimNetwork, SimJulia.Simulation

VALIDATORS = UInt(4)
PARACHAINS = UInt(3)
COLLATORS = 2*PARACHAINS
VIEW_DURATION = 5
NETWORK_DELAY = 0.5

sim = Simulation()
set = Validators(VALIDATORS, PARACHAINS)
collators = rand(UInt, COLLATORS)
network = Network(sim, vcat(set.validators, collators), NETWORK_DELAY)
spec = EngineSpec(VIEW_DURATION, PARACHAINS, set)
for i in 1:VALIDATORS
  start_validator(sim, NetworkEndpoint(network, set.validators[i]), Config(spec, set.validators[i]))
end
for i in 1:COLLATORS-1
  start_collator(sim, NetworkEndpoint(network, collators[i]), Config(spec, collators[i], i%PARACHAINS + 1))
end
start_collator(sim, NetworkEndpoint(network, collators[COLLATORS]), Config(spec, collators[COLLATORS], COLLATORS%PARACHAINS + 1, Malicious(true, false)))

SIM_TIME = 50.0

run(sim, SIM_TIME)
