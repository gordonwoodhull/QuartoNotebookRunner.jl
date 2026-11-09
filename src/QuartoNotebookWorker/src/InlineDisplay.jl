# InlineDisplay type.

# Intercepts all calls to `display` within the cell and passes the
# objects instead to our own `InlineDisplay` display that is pushed onto
# the display stack. The `InlineDisplay` just reuses the same
# `render_mimetypes` function as "normal" cell output does.
struct InlineDisplay <: AbstractDisplay
    queue::Vector{Any}
    # The 1-based index of the top-level expression running when each queued display
    # arrived; `current` is set by `include_str` between expressions and `kind` by the
    # logger wrapper while one log record is written. `trace` says whether the caller
    # wants outputs attributed (the `emitUnits` option); without it streams are not
    # split by expression or kind and `warning: false` drops stderr as it always did.
    expressions::Vector{Int}
    current::Base.RefValue{Int}
    kind::Base.RefValue{String}
    trace::Bool
    cell_options::Dict
    # Shared with the cell's output capture, which reads the queue's length.
    lock::ReentrantLock

    function InlineDisplay(cell_options::Dict; trace::Bool = false)
        new(Any[], Int[], Ref(0), Ref(""), trace, cell_options, ReentrantLock())
    end
end

function Base.display(d::InlineDisplay, mime::MIME, x)
    only = string(mime)
    _enqueue!(d, Base.@invokelatest render_mimetypes(x, d.cell_options; only))
end
function Base.display(d::InlineDisplay, x)
    _enqueue!(d, Base.@invokelatest render_mimetypes(x, d.cell_options))
end
Base.displayable(::InlineDisplay, m::MIME) = true

function _enqueue!(d::InlineDisplay, result)
    lock(d.lock) do
        push!(d.queue, result)
        push!(d.expressions, d.current[])
    end
    return nothing
end

# `f` receives the display so that the cell's output capture can place its
# streams relative to the displays.
function with_inline_display(f, cell_options; trace::Bool = false)
    inline_display = InlineDisplay(cell_options; trace)
    pushdisplay(inline_display)
    try
        return f(inline_display), inline_display.queue, inline_display.expressions
    finally
        popdisplay(inline_display)
    end
end
