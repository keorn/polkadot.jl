include("processes.jl")

sim = Simulation()
VALIDATORS = UInt(2)
PARACHAINS = UInt(1)
COLLATORS = PARACHAINS
set = ValidatorSet(VALIDATORS, PARACHAINS)
collators = rand(UInt, COLLATORS)
network = Network(sim, vcat(set.validators, collators), 0.5)
spec = EngineSpec(5, PARACHAINS, set)
for i in 1:VALIDATORS
	validator(sim, NetworkEndpoint(network, set.validators[i]), spec, set.validators[i])
end
for i in 1:COLLATORS
	collator(sim, NetworkEndpoint(network, collators[i]), spec, Config(collators[i], i%PARACHAINS + 1))
end

SIM_TIME = 50.0

run(sim, SIM_TIME)
