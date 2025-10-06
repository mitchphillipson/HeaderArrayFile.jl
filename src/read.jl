
"""
    read_chunk(file::IOStream)

Internal function to read a chunk from a Header Array File. This reads the
header and data, returning a tuple with the header as a `HarHeader` and the
data as a `Vector{UInt8}`.
"""
function read_chunk(file::IOStream)
    N = read(file, 4) |> x -> reinterpret(Int32, x) |> first
    payload = read(file, N)
    N2 = read(file, 4) |> x -> reinterpret(Int32, x) |> first
    N2 == N || error("Data integrity check failed")
    return (header = HarHeader(payload[1:4]), data = payload[5:end])
end

"""
    File(
        file_path::String;
        parameter_types = Dict(
            "1C" => HarSet,
            "RE" => HarParameter,
            )
        )

Read a Header Array File from the specified file path. The `parameter_types`
dictionary maps data types to their corresponding container types. If a data type
is not found in the dictionary, it defaults to `HarDefaultData`.
"""
function File(
        file_path::String;
        parameter_types = Dict(
            "1C" => HarSet,
            "RE" => HarParameter,
            #"RL" => HarParameter,
            )
        )

    out = HarFile()

    file = open(file_path)

    parameter = nothing
    
    while !eof(file)
        header, data = read_chunk(file)
        if !isempty(header)
            _, M = read_chunk(file)
            metadata = HarMetadata(M)
            parameter_type = get(parameter_types, datatype(metadata), HarDefaultData)
            parameter = parameter_type(file, metadata)
            out[name(header)] = HarRecord(header, metadata, parameter)
            #push!(out, HarRecord(header, metadata, parameter))
        else
            add_data!(parameter, data)
        end
    end

    close(file)

    return out

end