include("processes.jl")

sim = Simulation()
set = ValidatorSet(UInt(3))
collators = rand(UInt, 2)
network = Network(sim, vcat(set.validators, collators))
spec = EngineSpec(5, 1, set)
for i in 1:3
    validator(sim, NetworkEndpoint(network, set.validators[i]), spec, set.validators[i])
end
collator(sim, NetworkEndpoint(network, collators[1]), spec, collators[1])

SIM_TIME = 100.0

run(sim, SIM_TIME)
