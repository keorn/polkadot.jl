#!/usr/bin/env julia

println("Getting packages...")
[Pkg.add(req) for req in ["SimJulia", "Distributions", "DataStructures"]]
[Pkg.clone(req) for req in ["git@github.com:c42f/FastClosures.jl.git", "git@github.com:c42f/MicroLogging.jl.git"]]
