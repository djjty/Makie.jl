using Documenter: Selectors, Expanders, Markdown
using Documenter.Markdown: Link, Paragraph
struct DatabaseLookup <: Expanders.ExpanderPipeline end

Selectors.order(::Type{DatabaseLookup}) = 0.5
Selectors.matcher(::Type{DatabaseLookup}, node, page, doc) = false

const regex_src_pattern = r"example_database\(([\"a-zA-Z_0-9. ]+)\)"
const regex_plot_pattern = r"example_plot\(([\"a-zA-Z_0-9. ]+)\)"

const atomics = (
    heatmap,
    image,
    lines,
    linesegments,
    mesh,
    meshscatter,
    scatter,
    surface,
    text,
    Makie.volume
)

match_kw(x::String) = ismatch(regex_src_pattern, x)
match_kw(x::Paragraph) = any(match_kw, x.content)
match_kw(x::Any) = false

Selectors.matcher(::Type{DatabaseLookup}, node, page, doc) = match_kw(node)

# ============================================= Simon's implementation
function look_up_source(database_key)
    entries = find(x-> x.title == database_key, database)
    # current implementation finds titles, but we can also search for tags too
    isempty(entries) && error("No entry found for database reference $database_key")
    length(entries) > 1 && error("Multiple entries found for database reference $database_key")
    sprint() do io
        idx = entries[1]
        print_code(
            io, database[entries[1]],
            scope_start = "",
            scope_end = "",
            indent = "",
            resolution = (entry)-> "resolution = (500, 500)",
            outputfile = (entry, ending)-> Pkg.dir("Makie", "docs", "media", string(entry.unique_name, ending))
        )
    end
end

function Selectors.runner(::Type{DatabaseLookup}, x, page, doc)
    matched = nothing
    for elem in x.content
        if isa(elem, AbstractString)
            matched = match(regex_src_pattern, elem)
            matched != nothing && break
        end
    end
    matched == nothing && error("No match: $x")
    # The sandboxed module -- either a new one or a cached one from this page.
    database_keys = filter(x-> !(x in ("", " ")), split(matched[1], '"'))
    content = map(database_keys) do database_key
        Markdown.Code("julia", look_up_source(database_key))
    end
    # Evaluate the code block. We redirect stdout/stderr to `buffer`.
    page.mapping[x] = Markdown.MD(content)
end

function Selectors.runner(::Type{PlotLookup}, x, page, doc)
    matched = nothing
    for elem in x.content
        if isa(elem, AbstractString)
            matched = match(regex_plot_pattern, elem)
            matched != nothing && break
        end
    end
    matched == nothing && error("No match: $x")
    # The sandboxed module -- either a new one or a cached one from this page.
    database_keys = filter(x-> !(x in ("", " ")), split(matched[1], '"'))

    map(database_keys) do database_key
        # embed plot
        idx = find(x-> x.title == database_key, database)
        entry = database[idx[1]]
        uname = string(entry.unique_name)
        lines = entry.file_range

        io = IOBuffer()
        embed_plot(io, uname, mediapath, buildpath; src_lines = lines, raw_mode = false)
        str = String(take!(io))

        # write raw HTML using Documenter
        page.mapping[x] = Documenter.Documents.RawHTML(str)
    end
end


"""
    embed_video(relpath::AbstractString[; raw_mode::Bool = true])

Generates a MD-formatted string for embedding video into Markdown files
(since `Documenter.jl` doesn't support directly embedding mp4's).
"""
function embed_video(relpath::AbstractString; raw_mode::Bool = true)
    embed_code = """
        <video controls autoplay loop muted>
          <source src="$(relpath)" type="video/mp4">
          Your browser does not support mp4. Please use a modern browser like Chrome or Firefox.
        </video>
    """
    if raw_mode
        return str = "```@raw html\n" * embed_code * "```"
    else
        return embed_code
    end
end


"""
    embed_thumbnail(io::IO, func::Function, currpath::AbstractString)

Insert thumbnails matching a search tag.
"""
function embed_thumbnail(io::IO, func::Function, currpath::AbstractString)
    indices = find_indices(func)
    !ispath(currpath) && warn("currepath does not exist!")
    for idx in indices
        uname = database[idx].unique_name
        title = database[idx].title
        # TODO: currently exporting video thumbnails as .jpg because of ImageMagick issue#120
        testpath1 = joinpath(srcmediapath, "thumb-$uname.png")
        testpath2 = joinpath(srcmediapath, "thumb-$uname.jpg")
        if isfile(testpath1)
            embedpath = relpath(testpath1, currpath)
            println(io, "![]($(embedpath))")
            # [![Alt text](/path/to/img.jpg)](http://example.net/)
            # println(io, "[![$title]($(embedpath))](@ref)")
        elseif isfile(testpath2)
            embedpath = relpath(testpath2, currpath)
            println(io, "![]($(embedpath))")
            # println(io, "[![$title]($(embedpath))](@ref)")
        else
            warn("thumbnail for index $idx with uname $uname not found")
            embedpath = "not_found"
        end
        embedpath = []
    end
end

embed_thumbnail(io::IO, func::Function) = embed_thumbnail(io::IO, func::Function, atomicspath)


"""
    embed_thumbnail_link(io::IO, func::Function, currpath::AbstractString, tarpath::AbstractString)

Insert thumbnails matching a search tag.
"""
function embed_thumbnail_link(io::IO, func::Function, currpath::AbstractString, tarpath::AbstractString)
    indices = find_indices(func)
    !ispath(currpath) && warn("currepath does not exist!")
    !ispath(tarpath) && warn("$(tarpath) does not exist! Note that on your first run of docs generation and before you `makedocs`, you will likely get this error.")
    for idx in indices
        entry = database[idx]
        uname = entry.unique_name
        title = entry.title
        src_lines = entry.file_range
        # TODO: currently exporting video thumbnails as .jpg because of ImageMagick issue#120
        testpath1 = joinpath(mediapath, "thumb-$uname.png")
        testpath2 = joinpath(mediapath, "thumb-$uname.jpg")
        link = relpath(tarpath, currpath)
        if isfile(testpath1)
            embedpath = relpath(testpath1, currpath)
            println(io, "[![library lines $(src_lines)]($(embedpath))]($(link))")
        elseif isfile(testpath2)
            embedpath = relpath(testpath2, currpath)
            println(io, "[![library lines $(src_lines)]($(embedpath))]($(link))")
        else
            warn("thumbnail for index $idx with uname $uname not found")
            embedpath = "not_found"
        end
        embedpath = []
    end
end

# embed_thumbnail_link(io::IO, func::Function) = embed_thumbnail_link(io::IO, func::Function, atomicspath)


"""
    embed_plot(io::IO, uname::AbstractString, mediapath::AbstractString, buildpath::AbstractString[;
    raw_mode::Bool = true])

Outputs markdown code for embedding plots in `Documenter.jl`.
"""
function embed_plot(
        io::IO,
        uname::AbstractString,
        mediapath::AbstractString,
        buildpath::AbstractString;
        src_lines::Range = nothing,
        raw_mode::Bool = true
    )
    isa(uname, AbstractString) ? nothing : error("uname must be a string!")
    isa(mediapath, AbstractString) ? nothing : error("mediapath must be a string!")
    isa(buildpath, AbstractString) ? nothing : error("buildpath must be a string!")
    medialist = readdir(mediapath)
    if "$(uname).png" in medialist
        embedpath = joinpath(relpath(mediapath, buildpath), "$(uname).png")
        println(io, "![library lines $(src_lines)]($(embedpath))")
    elseif "$(uname).jpg" in medialist
        embedpath = joinpath(relpath(mediapath, buildpath), "$(uname).jpg")
        println(io, "![library lines $(src_lines)]($(embedpath))")
    elseif "$(uname).gif" in medialist
        embedpath = joinpath(relpath(mediapath, buildpath), "$(uname).gif")
        println(io, "![library lines $(src_lines)]($(embedpath))")
    elseif "$(uname).mp4" in medialist
        embedcode = embed_video(joinpath(relpath(mediapath, buildpath), "$(uname).mp4"); raw_mode = raw_mode)
        println(io, embedcode)
    else
        warn("file $(uname) with unknown extension in mediapath, or file nonexistent")
    end
    print(io, "\n")
end


"""
    print_table(io::IO, dict::Dict)

Print a Markdown-formatted table with the entries from `dict` to specified `io`.
"""
function print_table(io::IO, dict::Dict)
    # get max length of the keys
    k = string.("`", collect(keys(attr_desc)), "`")
    maxlen_k = max(length.(k)...)

    # get max length of the values
    v = string.(collect(values(attr_desc)))
    maxlen_v = max(length.(v)...)

    j = sort(collect(attr_desc), by = x -> x[1])

    # column labels
    labels = ["Symbol", "Description"]

    # print top header
    print(io, "|")
    print(io, "$(labels[1])")
    print(io, " "^(maxlen_k - length(labels[1])))
    print(io, "|")
    print(io, "$(labels[2])")
    print(io, " "^(maxlen_v - length(labels[2])))
    print(io, "|")
    print(io, "\n")

    # print second line (toprule)
    print(io, "|")
    print(io, "-"^maxlen_k)
    print(io, "|")
    print(io, "-"^maxlen_v)
    print(io, "|")
    print(io, "\n")

    for (idx, entry) in enumerate(j)
        print(io, "|")
        print(io, "`$(entry[1])`")
        print(io, " "^(maxlen_k - length(string(entry[1])) - 2))
        print(io, "|")
        print(io, "$(entry[2])")
        print(io, " "^(maxlen_v - length(entry[2])))
        print(io, "|")
        print(io, "\n")
    end
end



using Makie, ImageTransformations, FileIO
using ImageFiltering  # needed for Gaussian-filtering images during resize


function rescale_image(path::AbstractString, target_path::AbstractString, sz::Int = 200)
    !isfile(path) && warn("Input argument must be a file!")
    img = FileIO.load(path)

    # calculate new image size `newsz`
    (height, width) = size(img)
    (scale_height, scale_width) = sz ./ (height, width)
    scale = min(scale_height, scale_width)
    newsz = round.(Int, (height, width) .* scale)

    # filter image + resize image
    gaussfactor = 0.4
    σ = map((o,n) -> gaussfactor*o/n, size(img), newsz)
    kern = KernelFactors.gaussian(σ)   # from ImageFiltering
    imgf = ImageFiltering.imfilter(img, kern, NA())
    newimg = ImageTransformations.imresize(imgf, newsz)
    # save image
    FileIO.save(target_path, newimg)
end


"""
    generate_thumbnail(path::AbstractString, target_path, thumb_size::Int = 200)

Generates a (proportionally-scaled) thumbnail with maximum side dimension `sz`.
`sz` must be an integer, and the default value is 200 pixels.
"""
function generate_thumbnail(path, thumb_path, thumb_size = 128)
    if any(ext-> endswith(path, ext), (".png", ".jpeg", ".jpg"))
        rescale_image(path, thumb_path, thumb_size)
    elseif any(ext-> endswith(path, ext), (".gif", ".mp4", ".webm"))
        seektime = get_video_duration(path) / 2
        println(thumb_path)
        run(`ffmpeg -loglevel quiet -ss $seektime -i $path -vframes 1 -vf "scale=$(thumb_size):-2" -y -f image2 $thumb_path`)
    else
        warn("Unsupported return file format in $path")
    end
end


"""
    get_video_duration(path::AbstractString)

Returns the duration of the video in seconds (Float32).
Accepted file types: mp4, mkv, and gif.

Requires `ffprobe` (usually comes installed with `ffmpeg`).

Note that while this accepts gif, it will not work to get duration of the gif
(`ffprobe` doesn't support that), so it will just fallback to return 0.5 sec.
"""
function get_video_duration(path::AbstractString)
    !isfile(path) && error("input is not a file!")
    accepted_exts = ("mp4", "gif", "mkv")
    filename = basename(path)
    !(split(filename, ".")[2] in accepted_exts) && error("accepted file types are mp4 and gif!")
    try
        dur = readstring(`ffprobe -loglevel quiet -print_format compact=print_section=0:nokey=1:escape=csv -show_entries format=duration -i "$(path)"`)
        dur = parse(Float32, dur)
    catch e
        warn("`get_video_duration` on $filename did not work, using fallback video duration of 0.5 seconds")
        dur = 0.5
    end
end
