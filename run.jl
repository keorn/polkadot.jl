include("processes.jl")

sim = Simulation()
set = ValidatorSet(UInt(3))
network = Network(sim, set.validators)
spec = EngineSpec(5, set)
for i in 1:3
    Validator(sim, NetworkEndpoint(network, set.validators[i]), spec, set.validators[i])
end

SIM_TIME = 100.0

run(sim, SIM_TIME)
