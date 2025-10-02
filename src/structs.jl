abstract type AbstractHarData end


struct HarHeader
    name::String
    function HarHeader(data::Vector{UInt8})  
        length(data) == 4 || error("Header must be 4 bytes")
        new(String(data) |> strip)
    end
end

name(x::HarHeader) = x.name
Base.isempty(x::HarHeader) = name(x) == ""


struct HarMetadata
    data_type::String
    storage_type::String
    description::String
    num_dimensions::Int32 # Remove
    dimension_sizes::Vector{Int32}
    function HarMetadata(data::Vector{UInt8})
        length(data) >= 80 || error("Metadata must be at least 80 bytes")

        data_type = String(data[1:2]) |> strip
        storage_type = String(data[3:6]) |> strip
        dimension_sizes = reinterpret(Int32, data[81:end]) 
        
        if data_type ∈ ["RE", "RL"]
            dimension_sizes = filter(!=(1), dimension_sizes)
        end

        new(
            data_type,
            storage_type,
            String(data[7:76]) |> strip,
            length(dimension_sizes),
            dimension_sizes
        )
    end
end

datatype(x::HarMetadata) = x.data_type
storage_type(x::HarMetadata) = x.storage_type
description(x::HarMetadata) = x.description
dimension_sizes(x::HarMetadata) = x.dimension_sizes


struct HarRecord 
    header::HarHeader
    metadata::HarMetadata
    data::AbstractHarData
end

header(x::HarRecord) = x.header
metadata(x::HarRecord) = x.metadata
data(x::HarRecord) = x.data


struct HarFile
    records::OrderedDict{String, HarRecord}
    function HarFile()
        new(OrderedDict{String, HarRecord}())
    end
end

records(x::HarFile) = x.records
Base.getindex(x::HarFile, name::String) = records(x)[name]
Base.setindex!(x::HarFile, record::HarRecord, name::String) = (records(x)[name] = record)

Base.keys(x::HarFile) = keys(records(x))
Base.values(x::HarFile) = values(records(x))
Base.length(x::HarFile) = length(records(x))
Base.iterate(x::HarFile) = iterate(records(x))
Base.iterate(x::HarFile, state) = iterate(records(x), state)

function internal_data(x::HarFile)
    return OrderedDict(
        key => value for (key, value) in x if startswith(key, "XX")
    )
end

function sets(x::HarFile)
    return OrderedDict(
        key => value for (key, value) in x if !startswith(key, "XX") && isa(data(value), AbstractHarSet)
    )

end

function parameters(x::HarFile)
    return OrderedDict(
        key => value for (key, value) in x if !startswith(key, "XX") && isa(data(value), AbstractHarParameter)
    )
end

function not_loaded(x::HarFile)
    return OrderedDict(
        key => value for (key, value) in x if !startswith(key, "XX") && isa(data(value), HarDefaultData)
    )
end