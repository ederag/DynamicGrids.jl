"""
    ImageConfig(processor, minval, maxval) 
    ImageConfig(; processor=ColorProcessor(), minval=nothing, maxval=nothing) 

Common configuration component for all [`ImageOutput`](@ref).

Holds a [`GridProcessor`](@ref). 
`minval` and `maxval` fields normalise grid values between zero and one, 
for use with Colorshemes.jl. `nothing` values are considered to represent 
zero and one, and will not be normalised.

Values 
"""
struct ImageConfig{P,Min,Max}
    processor::P
    minval::Min
    maxval::Max
end
ImageConfig(; processor=ColorProcessor(), minval=nothing, maxval=nothing, kwargs...) = 
    ImageConfig(processor, minval, maxval)

processor(ic::ImageConfig) = ic.processor
minval(ic::ImageConfig) = ic.minval
maxval(ic::ImageConfig) = ic.maxval

"""
Graphic outputs that display the simulation frames as RGB images.

`ImageOutput`s have a [`ImageConfig`](@ref) component, and define a
[`showimage`](@ref) method.

See [`GifOutput`](@ref) for an example.

Although the majority of the code is maintained here to enable sharing
and reuse, most `ImageOutput`s are not provided in DynamicGrids.jl to avoid
heavey dependencies on graphics libraries. See
[DynamicGridsGtk.jl](https://github.com/cesaraustralia/DynamicGridsGtk.jl)
and [DynamicGridsInteract.jl](https://github.com/cesaraustralia/DynamicGridsInteract.jl)
for implementations.
"""
abstract type ImageOutput{T} <: GraphicOutput{T} end

# Construct one ImageOutput from another Output
(::Type{F})(o::T; frames=frames(o), extent=extent(o), graphicconfig=graphicconfig(o),
    imageconfig=imageconfig(o), kwargs...) where F <: ImageOutput where T <: Output = 
    F(; frames=frames, running=false, extent=extent, graphicconfig=graphicconfig, 
      imageconfig=imagconfig, kwargs...)

# Generic ImageOutput constructor. Converts an init array to vector of arrays.
(::Type{T})(init::Union{NamedTuple,AbstractMatrix}; 
            extent=nothing, graphicconfig=nothing, imageconfig=nothing, kwargs...
           ) where T <: ImageOutput = begin
    extent = extent isa Nothing ? Extent(; init=init, kwargs...) : extent
    graphicconfig = graphicconfig isa Nothing ? GraphicConfig(; kwargs...) : extent
    imageconfig = imageconfig isa Nothing ? ImageConfig(; kwargs...) : imageconfig
    T(; frames=[deepcopy(init)], running=false, 
      extent=extent, graphicconfig=graphicconfig, imageconfig=imageconfig, kwargs...)
end

imageconfig(o::Output) = ImageConfig()
imageconfig(o::ImageOutput) = o.imageconfig

processor(o::Output) = processor(imageconfig(o))
minval(o::Output) = minval(imageconfig(o))
maxval(o::Output) = maxval(imageconfig(o))


# Allow construcing a frame with the ruleset passed in instead of SimData
showframe(frame, o::ImageOutput, data::RulesetOrSimData, f, t) =
    showimage(grid2image(o, data, frame, t), o, data, f, t)

"""
    showimage(image::AbstractArray{AGRB32,2}, output, f, t)

Show image generated by and `GridProcessor` in an ImageOutput.

# Arguments
- `image
- `output`: the output to define the method for
- `f`: the current frame number
- `t`: the current frame date/time
"""
function showimage end
showimage(image, o, data, f, t) = showimage(image, o, f, t)

"""
Default colorscheme. Better performance than using a Colorschemes.jl
scheme as there is no interpolation.
"""
struct Greyscale{M1,M2}
    min::M1
    max::M2
end
Greyscale(; min=nothing, max=nothing) = Greyscale(min, max)

Base.get(scheme::Greyscale, x) = scale(x, scheme.min, scheme.max)

"Alternate name for Greyscale()"
const Grayscale = Greyscale


"""
Grid processors convert a frame of the simulation into an RGB 
image for display. Frames may be one or multiple grids.
"""
abstract type GridProcessor end

textconfig(::GridProcessor) = nothing

"""
    grid2image(o::ImageOutput, data::Union{Ruleset,SimData}, grids, t)
    grid2image(p::GridProcessor, o::ImageOutput, data::Union{Ruleset,SimData}, grids, t)

Convert a grid or named tuple of grids to an RGB image, using a GridProcessor

[`GridProcessor`](@ref) is intentionally not dispatched with the output type in
the methods that finally generate images, to reduce coupling.
But it they can be distpatched on together when required for custom outputs.
"""
function grid2image end

grid2image(o::ImageOutput, data::RulesetOrSimData, frame, t) =
    grid2image(processor(o), o, data, frame, t)

"""
Grid processors that convert one grid to an image.

The first grid will be displayed if a SingleGridProcessor is
used with a NamedTuple of grids.
"""
abstract type SingleGridProcessor <: GridProcessor end

allocimage(grid::AbstractArray) = allocimage(size(grid))
allocimage(size::Tuple) = fill(ARGB32(0.0, 0.0, 0.0, 1.0), size)

grid2image(p::SingleGridProcessor, o::ImageOutput, data::RulesetOrSimData, grids::NamedTuple, t) =
    grid2image(p, o, data, first(grids), t, string(first(keys(grids))))
grid2image(p::SingleGridProcessor, o::Output, data::RulesetOrSimData, grid::AbstractArray, t, name=nothing) =
    grid2image(p, mask(o), minval(o), maxval(o), data, grid, t, name)
grid2image(p::SingleGridProcessor, mask, minval, maxval, data::RulesetOrSimData, grid::AbstractArray, t, name=nothing) = begin
    img = allocimage(grid)
    for j in 1:size(img, 2), i in 1:size(img, 1)
        @inbounds val = grid[i, j]
        pixel = rgb(cell2rgb(p, mask, minval, maxval, data, val, i, j))
        @inbounds img[i, j] = pixel
    end
    rendertext!(img, textconfig(p), name, t)
    img
end

"""
Processors that convert a frame containing multiple grids into a single image.
"""
abstract type MultiGridProcessor <: GridProcessor end

"""
    TextConfig(; font::String, namepixels=14, timepixels=14,
               namepos=(timepixels+namepixels, timepixels),
               timepos=(timepixels, timepixels),
               fcolor=ARGB32(1.0), bcolor=ARGB32(RGB(0.0), 1.0),)
    TextConfig(face, namepixels, namepos, timepixels, timepos, fcolor, bcolor)

Text configuration for printing timestep and grid name on the image.

# Arguments

- `namepixels` and `timepixels`: set the pixel size of the font. 
- `timepos` and `namepos`: tuples that set the label positions, in pixels.
- `fcolor` and `bcolor`: the foreground and background colors, as `ARGB32`.
"""
struct TextConfig{F,NPi,NPo,TPi,TPo,FC,BC}
    face::F
    namepixels::NPi
    namepos::NPo
    timepixels::TPi
    timepos::TPo
    fcolor::FC
    bcolor::BC
end
TextConfig(; font, namepixels=12, timepixels=12,
           namepos=(3timepixels + namepixels, timepixels),
           timepos=(2timepixels, timepixels),
           fcolor=ARGB32(1.0), bcolor=ARGB32(RGB(0.0), 1.0),
          ) = begin
    face = FreeTypeAbstraction.findfont(font)
    face isa Nothing && throw(ArgumentError("Font $font can not be found in this system"))
    TextConfig(face, namepixels, namepos, timepixels, timepos, fcolor, bcolor)
end

rendertext!(img, config::TextConfig, name, t) = begin
    rendername!(img, config::TextConfig, name)
    rendertime!(img, config::TextConfig, t)
end
rendertext!(img, config::Nothing, name, t) = nothing

rendername!(img, config::TextConfig, name) =
    renderstring!(img, name, config.face, config.namepixels, config.namepos...;
                  fcolor=config.fcolor, bcolor=config.bcolor)
rendername!(img, config::TextConfig, name::Nothing) = nothing
rendername!(img, config::Nothing, name) = nothing
rendername!(img, config::Nothing, name::Nothing) = nothing

rendertime!(img, config::TextConfig, t) =
    renderstring!(img, string(t), config.face, config.timepixels, config.timepos...;
                  fcolor=config.fcolor, bcolor=config.bcolor)
rendertime!(img, config::Nothing, t) = nothing
rendertime!(img, config::TextConfig, t::Nothing) = nothing
rendertime!(img, config::Nothing, t::Nothing) = nothing

""""
    ColorProcessor(; scheme=Greyscale(), zerocolor=nothing, maskcolor=nothing)

Converts output grids to a colorsheme.

## Arguments / Keyword Arguments
- `scheme`: a ColorSchemes.jl colorscheme, or `Greyscale`.
- `zerocolor`: a `Color` to use when values are zero, or `nothing` to ignore.
- `maskcolor`: a `Color` to use when cells are masked, or `nothing` to ignore.
- `textconfig`: a [`TextConfig`](@ref) object.
"""
@default_kw struct ColorProcessor{S,Z,M,TC} <: SingleGridProcessor
    scheme::S      | Greyscale()
    zerocolor::Z   | nothing
    maskcolor::M   | nothing
    textconfig::TC | nothing
end
ColorProcessor(scheme::S, zerocolor::Z=nothing, maskcolor::M=nothing, textconfig::TC=nothing
              ) where {S,Z,M,TC} =
    ColorProcessor{S,Z,M,TC}(scheme, zerocolor, maskcolor, textconfig)

scheme(processor::ColorProcessor) = processor.scheme
zerocolor(processor::ColorProcessor) = processor.zerocolor
maskcolor(processor::ColorProcessor) = processor.maskcolor
textconfig(processor::ColorProcessor) = processor.textconfig

# Show colorscheme in Atom etc
Base.show(io::IO, m::MIME"image/svg+xml", p::ColorProcessor) =
    show(io, m, scheme(p))

@inline cell2rgb(p::ColorProcessor, mask, minval, maxval, data::RulesetOrSimData, val, I...) =
    if !(maskcolor(p) isa Nothing) && ismasked(mask, I...)
        rgb(maskcolor(p))
    else
        normval = normalise(val, minval, maxval)
        if !(zerocolor(p) isa Nothing) && normval == zero(normval)
            rgb(zerocolor(p))
        else
            rgb(scheme(p), normval)
        end
    end

"""
    SparseOptInspector()

A [`GridProcessor`](@ref) that checks [`SparseOpt`](@ref) visually. Errors show in red. 
"""
struct SparseOptInspector <: SingleGridProcessor end

@inline cell2rgb(p::SparseOptInspector, mask, minval, maxval, data::RulesetOrSimData, val, I...) = begin
    r = radius(first(grids(data)))
    blocksize = 2r
    blockindex = indtoblock.((I[1] + r,  I[2] + r), blocksize)
    normedval = normalise(val, minval, maxval)
    status = sourcestatus(first(data))
    # This is done at the start of the next frame, so wont show up in
    # the image properly. So do it preemtively?
    wrapstatus!(status)
    if status[blockindex...]
        if normedval > 0
            rgb(normedval)
        else
            rgb(0.0, 0.0, 0.0)
        end
    elseif normedval > 0
        rgb(1.0, 0.0, 0.0) # This (a red cell) would mean there is a bug in SparseOpt
    else
        rgb(0.5, 0.5, 0.5)
    end
end


abstract type BandColor end

struct Red <: BandColor end
struct Green <: BandColor end
struct Blue <: BandColor end

"""
    ThreeColorProcessor(; colors=(Red(), Green(), Blue()), zerocolor=nothing, maskcolor=nothing)

Assigns `Red()`, `Blue()`, `Green()` or `nothing` to
any number of dynamic grids in any order. Duplicate colors will be summed.
The final color sums are combined into a composite color image for display.

## Arguments / Keyword Arguments
- `colors`: a tuple or `Red()`, `Green()`, `Blue()`, or `nothing` matching the number of grids.
- `zerocolor`: an `RGB` color to use when values are zero, or `nothing` to ignore.
- `maskcolor`: an `RGB` color to use when cells are masked, or `nothing` to ignore.
"""
@default_kw struct ThreeColorProcessor{C<:Tuple,Z,M,TC} <: MultiGridProcessor
    colors::C      | (Red(), Green(), Blue())
    zerocolor::Z   | nothing
    maskcolor::M   | nothing
    textconfig::TC | nothing
end

colors(processor::ThreeColorProcessor) = processor.colors
zerocolor(processor::ThreeColorProcessor) = processor.zerocolor
maskcolor(processor::ThreeColorProcessor) = processor.maskcolor

grid2image(p::ThreeColorProcessor, o::ImageOutput, data::RulesetOrSimData, grids::NamedTuple, t) = begin
    img = allocimage(first(grids))
    ncols, ngrids, nmin, nmax = map(length, (colors(p), grids, minval(o), maxval(o)))
    if !(ngrids == ncols == nmin == nmax)
        ArgumentError(
            "Number of grids ($ngrids), processor colors ($ncols), " *
            "minval ($nmin) and maxival ($nmax) must be the same"
        ) |> throw
    end
    for i in CartesianIndices(first(grids))
        img[i] = if !(maskcolor(p) isa Nothing) && ismasked(mask(o), i)
            rgb(maskcolor(p))
        else
            xs = map(values(grids), minval(o), maxval(o)) do g, mi, ma
                normalise(g[i], mi, ma)
            end
            if !(zerocolor(p) isa Nothing) && all(map((x, c) -> c isa Nothing || x == zero(x), xs, colors(p)))
                rgb(zerocolor(p))
            else
                rgb(combinebands(colors(p), xs))
            end
        end
    end
    img
end

"""
    LayoutProcessor(layout::Array, processors, textconfig)

LayoutProcessor allows displaying multiple grids in a block layout,
by specifying a layout matrix and a list of [`SingleGridProcessor`](@ref) 
to be run for each.

## Arguments
- `layout`: A Vector or Matrix containing the keys or numbers of grids in the locations to
  display them. `nothing`, `missing` or `0` values will be skipped.
- `processors`: tuple of SingleGridProcessor, one for each grid in the simulation.
  Can be `nothing` or any other value for grids not in layout.
- `textconfig` : [`TextConfig`] object for printing time and grid name labels.
"""
@default_kw struct LayoutProcessor{L<:AbstractMatrix,P,TC} <: MultiGridProcessor
    layout::L      | throw(ArgumentError("must include an Array for the layout keyword"))
    processors::P  | throw(ArgumentError("must include a tuple of processors, one for each grid"))
    textconfig::TC | nothing
    LayoutProcessor(layouts::L, processors::P, textconfig::TC) where {L,P,TC} = begin
        processors = map(p -> (@set p.textconfig = textconfig), map(_asprocessor, processors))
        new{L,typeof(processors),TC}(layouts, processors, textconfig)
    end
end
# Convenience constructor to convert Vector input to a column Matrix
LayoutProcessor(layout::AbstractVector, processors, textconfig) =
    LayoutProcessor(reshape(layout, length(layout), 1), processors, textconfig)

_asprocessor(p::GridProcessor) = p
_asprocessor(x) = ColorProcessor(x)

layout(p::LayoutProcessor) = p.layout
processors(p::LayoutProcessor) = p.processors
textconfig(p::LayoutProcessor) = p.textconfig


grid2image(p::LayoutProcessor, o::ImageOutput, data::RulesetOrSimData, grids::NamedTuple, t
          ) = begin
    ngrids, nmin, nmax = map(length, (grids, minval(o), maxval(o)))
    if !(ngrids == nmin == nmax)
        ArgumentError(
            "Number of grids ($ngrids), minval ($nmin) and maxval ($nmax) must be the same"
        ) |> throw
    end

    grid_ids = layout(p)
    sze = size(first(grids))
    img = allocimage(sze .* size(grid_ids))
    # Loop over the layout matrix
    for i in 1:size(grid_ids, 1), j in 1:size(grid_ids, 2)
        grid_id = grid_ids[i, j]
        # Accept symbol keys and numbers, skip missing/nothing/0
        (ismissing(grid_id) || grid_id === nothing || grid_id == 0)  && continue
        n = if grid_id isa Symbol
            found = findfirst(k -> k === grid_id, keys(grids))
            found === nothing && throw(ArgumentError("$grid_id is not in $(keys(grids))"))
            found
        else
            grid_id
        end
        # Run processor for section
        key = keys(grids)[n]
        _sectionloop(processors(p)[n], img, mask(o), minval(o)[n], maxval(o)[n], data, grids[n], key, i, j)
    end
    rendertime!(img, textconfig(p), t)
    img
end

_sectionloop(processor::SingleGridProcessor, img, mask, minval, maxval, data, grid, key, i, j) = begin
    # We pass an empty string for time as we don't want to print it multiple times.
    section = grid2image(processor, mask, minval, maxval, data, grid, nothing, string(key))
    @assert eltype(section) == eltype(img)
    sze = size(section)
    # Copy section into image
    for y in 1:sze[2], x in 1:sze[1]
        img[x + (i - 1) * sze[1], y + (j - 1) * sze[2]] = section[x, y]
    end
end


# Color manipulation tools

"""
    normalise(x, min, max)

Set a value to be between zero and one, before converting to Color.
min and max of `nothing` are assumed to be 0 and 1.
"""
normalise(x, minval::Number, maxval::Number) =
    max(min((x - minval) / (maxval - minval), oneunit(x)), zero(x))
normalise(x, minval::Number, maxval::Nothing) =
    max((x - minval) / (oneunit(x) - minval), zero(x))
normalise(x, minval::Nothing, maxval::Number) =
    min(x / maxval, oneunit(x), oneunit(x))
normalise(x, minval::Nothing, maxval::Nothing) = x

"""
    scale(x, min, max)

Rescale a value between 0 and 1 to be between `min` and `max`.
This can be used to shrink the range of a colorsheme that is displayed.
min and max of `nothing` are assumed to be 0 and 1.
"""
scale(x, min, max) = x * (max - min) + min
scale(x, ::Nothing, max) = x * max
scale(x, min, ::Nothing) = x * (oneunit(min) - min) + min
scale(x, ::Nothing, ::Nothing) = x

"""
    rgb(val)

Convert a number, tuple or color to an ARGB32 value.
"""
rgb(vals::Tuple) = ARGB32(vals...)
rgb(vals...) = ARGB32(vals...)
rgb(val::Number) = ARGB32(RGB(val))
rgb(val::Color) = ARGB32(val)
rgb(val::ARGB32) = val
rgb(val::Bool) = (ARGB32(0), ARGB32(1))[val+1]
"""
    rgb(scheme, val)

Convert a color scheme and value to an RGB value.
"""
rgb(scheme, val) = rgb(get(scheme, val))

"""
    combinebands(c::Tuple{Vararg{<:BandColor}, acc, xs)

Assign values to color bands given in any order, and output as RGB.
"""
combinebands(colors, xs) = combinebands(colors, xs, (0.0, 0.0, 0.0))
combinebands(c::Tuple{Red,Vararg}, xs, acc) =
    combinebands(tail(c), tail(xs), (acc[1] + xs[1], acc[2], acc[3]))
combinebands(c::Tuple{Green,Vararg}, xs, acc) =
    combinebands(tail(c), tail(xs), (acc[1], acc[2] + xs[1], acc[3]))
combinebands(c::Tuple{Blue,Vararg}, xs, acc) =
    combinebands(tail(c), tail(xs), (acc[1], acc[2], acc[3] + xs[1]))
combinebands(c::Tuple{Nothing,Vararg}, xs, acc) =
    combinebands(tail(c), tail(xs), acc)
combinebands(c::Tuple{}, xs, acc) = rgb(acc...)

mutable struct NoDisplayImageOutput{T,F<:AbstractVector{T},E,GC,IC} <: ImageOutput{T}
    frames::F
    running::Bool 
    extent::E
    graphicconfig::GC
    imageconfig::IC
end

NoDisplayImageOutput(; frames, running, extent, graphicconfig, imageconfig, kwargs...) =
    NoDisplayImageOutput(frames, running, extent, graphicconfig, imageconfig)
