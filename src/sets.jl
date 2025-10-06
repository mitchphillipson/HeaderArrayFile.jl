abstract type AbstractHarSet <: AbstractHarData end

struct HarSet <: AbstractHarSet
    name::String
    data::Vector{String}
    function HarSet(file::IOStream, metadata::HarMetadata)
        name = description(metadata)




        length(dimension_sizes(metadata)) == 2 || error("Datatype 1C must be 2-dimensional found $(length(dimension_sizes(metadata)))")

        num_elements, byte_length = dimension_sizes(metadata)
        found_data_points = 0
        data = String[]
        while found_data_points < num_elements
            _, line_data = read_chunk(file)
            new_data = line_data[13:end] |> y -> Iterators.partition(y, byte_length) .|> String .|> strip 
            append!(data, new_data)
            found_data_points += length(new_data)
        end
        
        new(name, data)
    end
end

name(x::HarSet) = x.name
data(x::HarSet) = x.data

DataFrames.DataFrame(x::HarSet) = DataFrames.DataFrame([data(x)], [name(x)])
NamedArrays.NamedArray(x::HarSet) = NamedArrays.NamedArray(data(x))#, (data(x),), (name(x),))