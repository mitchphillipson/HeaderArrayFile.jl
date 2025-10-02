abstract type AbstractHarParameter <: AbstractHarData end

struct HarParameter <: AbstractHarParameter
    name::String
    column_names::Vector{Symbol}
    column_values::NamedTuple
    data::Vector{Tuple{Int, Float32}}

    function HarParameter(file::IOStream, metadata::HarMetadata)
        name, column_names, column_values = read_RE_metadata(file, metadata)

        if storage_type(metadata) == "FULL"
            data = read_REFULL_data(file, metadata)
        elseif storage_type(metadata) == "SPSE"
            data = read_RESPSE_data(file, metadata)
        else
            error("Storage type $(storage_type(metadata)) not implemented for RE")
        end

        new(name, column_names, column_values, data)

    end
end

name(x::HarParameter) = x.name
column_names(x::HarParameter) = x.column_names
column_values(x::HarParameter) = x.column_values
column_values(x::HarParameter, col::Symbol) = getfield(column_values(x), col)
data(x::HarParameter) = x.data

function read_RE_metadata(file::IOStream, metadata::HarMetadata)
    N = length(dimension_sizes(metadata))
    data_length = 29+12*N-1

    _, M = read_chunk(file)
    length(M) > data_length || error("Parameter metadata data must be at least $data_length bytes")

    name = M[13:24] |> String |> strip
    column_names = M[29:29+12*N-1] |> x -> Iterators.partition(x, 12) .|> String .|> strip .|> Symbol
    unique_column_names = Tuple(unique(column_names))
    column_values = NamedTuple{unique_column_names}([
        read_chunk(file) |> x -> Iterators.partition(x[:data][13:end], 12) .|> String .|> strip
        for _ in unique_column_names
    ])

    return name, column_names, column_values

end

function read_REFULL_data(file::IOStream, metadata::HarMetadata)
    _, M = read_chunk(file)
    dims = M[9:end] |> x -> reinterpret(Int32, x) |> x -> filter(!=(1), x)
    dims == dimension_sizes(metadata) || error("Data dimensions do not match metadata") ## Improve error message
    
    total_data_points = prod(dims)

    found_data_points = 0
    data = []
    while found_data_points < total_data_points
        _, line_meta = read_chunk(file)
        _, line_data = read_chunk(file)

        new_data = line_data[5:end] |> x -> reinterpret(Float32, x)

        append!(data, enumerate(new_data) .|> x -> (x[1]+found_data_points, x[2]))
        found_data_points += length(new_data)
    end
    return data
end


function read_RESPSE_data(file::IOStream, metadata::HarMetadata)
    _, M = read_chunk(file)
    #dims = M[9:end] |> x -> reinterpret(Int32, x) |> x -> filter(!=(1), x)
    #dims == dimension_sizes(metadata) || error("Data dimensions do not match metadata") ## Improve error message

    total_data_points = M[1:4] |> x -> reinterpret(Int32, x) |> first
    key_size = M[5:8] |> x -> reinterpret(Int32, x) |> first
    data_size = M[9:12] |> x -> reinterpret(Int32, x) |> first

    found_data_points = 0
    data = []

    if total_data_points == 0
        read_chunk(file)
        return data
    end

    while found_data_points < total_data_points
        _, line_data = read_chunk(file)

        N = line_data[9:12] |> x -> reinterpret(Int32, x) |> first


        labels = line_data[13:13+N*key_size-1] |> x -> reinterpret(Int32, x) 
        new_data = line_data[13+N*key_size:end] |> x -> reinterpret(Float32, x)
        append!(data, zip(labels, new_data))

        found_data_points += length(new_data)
    end
    return data
end



function index_to_elements(X::HarParameter, i::Integer)
    col_lengths = length.([column_values(X, col) for col in column_names(X)])
    
    if prod(col_lengths) < i
        error("Index $i is out of bounds for parameter with $(prod(col_lengths)) data points")
    end

    out = []
    for (col_num, (column, N)) in enumerate(zip(column_names(X), col_lengths))
        index = i%N + (col_num == 1 ? 0 : 1)
        if col_num == 1 && index ==0 
            index = N
        end
        i = div(i, N)
        push!(out, column_values(X, column)[index])

    end

    return out
end

function make_column_names_unique(column_names::Vector{Symbol})
    out = Symbol[]
    for col in column_names
        unique_indicator = col
        try_idx = 0
        while unique_indicator in out
            try_idx += 1
            unique_indicator = Symbol(col, "_", try_idx)
        end
        push!(out, unique_indicator)
    end
    return out
end


function DataFrames.DataFrame(C::HarParameter) 
    cols = make_column_names_unique(column_names(C))
    return DataFrame(C.data, [:index, :value]) |>
        x -> transform!(x,
            :index => ByRow(i -> index_to_elements(C, i)) => cols
        ) |>
        x -> select!(x, [cols..., :value])


end