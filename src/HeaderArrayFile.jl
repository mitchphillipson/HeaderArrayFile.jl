module HeaderArrayFile

    using DataFrames

    import OrderedCollections: OrderedDict

    include("structs.jl")

    export HarHeader, name, HarMetadata, datatype, storage_type, description, dimension_sizes, 
        HarRecord, HarFile

    include("parameter.jl")

    export HarParameter

    include("sets.jl")

    export HarSet

    include("default.jl")

    export HarDefaultData, add_data!

    include("read.jl")

    export read_chunk

end # module HeaderArrayFiles
