

mutable struct HarDefaultData <: AbstractHarData
    data::Vector{Vector{UInt8}}
    function HarDefaultData(file::IOStream, metadata::HarMetadata)
        new([])
    end
end

add_data!(X::HarDefaultData, data::Vector{UInt8}) = push!(X.data, data)