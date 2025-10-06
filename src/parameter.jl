abstract type AbstractHarParameter <: AbstractHarData end

"""
    HarParameter <: AbstractHarParameter

A container for a parameter in a Header Array File. This contains the name 
(if provided, defaults to the header name), the column names and values, and the 
data as a vector of (index, value) tuples.

Loads data for `REFULL` and `RESPSE` storage types.
"""
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
dimension_sizes(x::HarParameter) = length.(column_values.(Ref(x), column_names(x)))
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

"""
    DataFrame(C::HarParameter)

Convert a `HarParameter` to a `DataFrame`. The resulting `DataFrame` will have 
one column for each dimension, plus a `:value` column for the data values.
"""
function DataFrames.DataFrame(C::HarParameter) 
    cols = make_column_names_unique(column_names(C))
    return DataFrame(C.data, [:index, :value]) |>
        x -> transform!(x,
            :index => ByRow(i -> index_to_elements(C, i)) => cols
        ) |>
        x -> select!(x, [cols..., :value])
end


"""
    NamedArray(C::HarParameter)

Convert a `HarParameter` to a `NamedArray`. The resulting `NamedArray` will have
one dimension for each dimension in the parameter, with names and sizes taken from
the parameter metadata.
"""
function NamedArrays.NamedArray(C::HarParameter)
    x = C.data
    dim_sizes = dimension_sizes(C)
    N = prod(dim_sizes)
    missing_index = setdiff(1:N, get.(x, 1, 0))
    y = [x; collect(zip(missing_index, zeros(Float32, length(missing_index))))]
    sort!(y)

    dims = length.(column_values.(Ref(C), column_names(C)))
    dim_names = Tuple(column_values.(Ref(C), column_names(C)))
    reshape(get.(y, 2, 0), Tuple(dims)) |> x -> NamedArray(x, Tuple(dim_names), Tuple(column_names(C)))
end