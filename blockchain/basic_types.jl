using MicroLogging

include("../types.jl");

const Hash = UInt
const Address = UInt
const Timestamp = UInt
Timestamp(time::Float64) = round(UInt, time)

"Relay chain view."
view(time::Number, view_duration::UInt) = div(Timestamp(time), view_duration)
view(time::UInt, view_duration::UInt) = div(time, view_duration)
