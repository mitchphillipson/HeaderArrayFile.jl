function read_chunk(file)
    N = read(file, 4) |> x -> reinterpret(Int32, x) |> first
    payload = read(file, N)
    N2 = read(file, 4) |> x -> reinterpret(Int32, x) |> first
    N2 == N || error("Data integrity check failed")
    return (header = HarHeader(payload[1:4]), data = payload[5:end])
end


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