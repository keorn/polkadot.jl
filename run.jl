#!/usr/bin/env julia
include("processes.jl")

VALIDATORS = UInt(2)
PARACHAINS = UInt(1)
COLLATORS = PARACHAINS
VIEW_DURATION = 5
NETWORK_DELAY = 0.5

sim = Simulation()
set = ValidatorSet(VALIDATORS, PARACHAINS)
collators = rand(UInt, COLLATORS)
network = Network(sim, vcat(set.validators, collators), NETWORK_DELAY)
spec = EngineSpec(VIEW_DURATION, PARACHAINS, set)
for i in 1:VALIDATORS
	validator(sim, NetworkEndpoint(network, set.validators[i]), spec, set.validators[i])
end
for i in 1:COLLATORS
	collator(sim, NetworkEndpoint(network, collators[i]), spec, Config(collators[i], i%PARACHAINS + 1))
end

SIM_TIME = 50.0

run(sim, SIM_TIME)
