"""
    frule([::RuleConfig,] (Δf, Δx...), f, x...)

Expressing the output of `f(x...)` as `Ω`, return the tuple:

    (Ω, ΔΩ)

The second return value is the differential w.r.t. the output.

If no method matching `frule((Δf, Δx...), f, x...)` has been defined, then return `nothing`.

Examples:

unary input, unary output scalar function:

```jldoctest frule
julia> dself = NoTangent();

julia> x = rand()
0.8236475079774124

julia> sinx, Δsinx = frule((dself, 1), sin, x)
(0.7336293678134624, 0.6795498147167869)

julia> sinx == sin(x)
true

julia> Δsinx == cos(x)
true
```

Unary input, binary output scalar function:

```jldoctest frule
julia> sincosx, Δsincosx = frule((dself, 1), sincos, x);

julia> sincosx == sincos(x)
true

julia> Δsincosx[1] == cos(x)
true

julia> Δsincosx[2] == -sin(x)
true
```

Note that techically speaking julia does not have multiple output functions, just functions
that return a single output that is iterable, like a `Tuple`.
So this is actually a [`Tangent`](@ref):
```jldoctest frule
julia> Δsincosx
Tangent{Tuple{Float64, Float64}}(0.6795498147167869, -0.7336293678134624)
```

The optional [`RuleConfig`](@ref) option allows specifying frules only for AD systems that
support given features. If not needed, then it can be omitted and the `frule` without it
will be hit as a fallback. This is the case for most rules.

See also: [`rrule`](@ref), [`@scalar_rule`](@ref), [`RuleConfig`](@ref)
"""
frule(::Any, ::Vararg{Any}; kwargs...) = nothing

"""
    rrule([::RuleConfig,] f, x...)

Expressing `x` as the tuple `(x₁, x₂, ...)` and the output tuple of `f(x...)`
as `Ω`, return the tuple:

    (Ω, (Ω̄₁, Ω̄₂, ...) -> (s̄elf, x̄₁, x̄₂, ...))

Where the second return value is the the propagation rule or pullback.
It takes in differentials corresponding to the outputs (`x̄₁, x̄₂, ...`),
and `s̄elf`, the internal values of the function itself (for closures)

If no method matching `rrule(f, xs...)` has been defined, then return `nothing`.

Examples:

unary input, unary output scalar function:

```jldoctest
julia> x = rand();

julia> sinx, sin_pullback = rrule(sin, x);

julia> sinx == sin(x)
true

julia> sin_pullback(1) == (NoTangent(), cos(x))
true
```

binary input, unary output scalar function:

```jldoctest
julia> x, y = rand(2);

julia> hypotxy, hypot_pullback = rrule(hypot, x, y);

julia> hypotxy == hypot(x, y)
true

julia> hypot_pullback(1) == (NoTangent(), (x / hypot(x, y)), (y / hypot(x, y)))
true
```

The optional [`RuleConfig`](@ref) option allows specifying rrules only for AD systems that
support given features. If not needed, then it can be omitted and the `rrule` without it
will be hit as a fallback. This is the case for most rules.

See also: [`frule`](@ref), [`@scalar_rule`](@ref), [`RuleConfig`](@ref)
"""
rrule(::Any, ::Vararg{Any}) = nothing

# Manual fallback for keyword arguments. Usually this would be generated by
#
#   rrule(::Any, ::Vararg{Any}; kwargs...) = nothing
#
# However - the fallback method is so hot that we want to avoid any extra code
# that would be required to have the automatically generated method package up
# the keyword arguments (which the optimizer will throw away, but the compiler
# still has to manually analyze). Manually declare this method with an
# explicitly empty body to save the compiler that work.

(::Core.kwftype(typeof(rrule)))(::Any, ::Any, ::Vararg{Any}) = nothing

"""
    RuleConfig{F, R, T}

The configuration
 - `F`: **frule-like**. This is singleton `typeof` a function which acts like `frule`, but
   which functions via invoking an AD system. It must match the [`frule`](@ref) signature.
   If you do not have such a function it must be set to `Nothing` instead.
 - `R`: **rrule-like**. This is singleton `typeof` a function which acts like `rrule`, but
   which functions via invoking an AD system. It must match the [`rrule`](@ref) signature.
   If you do not have such a function it must be set to `Nothing` instead.
 - `T`: **traits**. This should be a `Union` of all special traits needed for rules to be
   allowed to be defined for your AD. If nothing special this should be set to `Union{}`.

Rule authors can dispatch on this config when defining rules.
For example:
```julia
# only define rrule for `pop!` on AD systems where mutation is supported.
rrule(::RuleConfig{<:Any,<:Any,>:SupportsMutation}, typeof(pop!), ::Vector) = ...

# this definition of map is for any AD that defines a forwards mode
rrule(conf::RuleConfig{<:Function}, typeof(map), ::Vector) = ...

# this definition of map is for any AD that only defines a reverse mode.
# It is not as good as the rrule that can be used if the AD defines a forward-mode as well.
rrule(conf::RuleConfig{Nothing,<:Function}, typeof(map), ::Vector) = ...
```

For more details see [rule configurations and calling back into AD](@ref config).
"""
abstract type RuleConfig{F<:Union{Function,Nothing}, R<:Union{Function,Nothing}, T} where T end

# if no config is present then fallback to config-less rules
frule(::RuleConfig, ārgs, f, args...; kwargs...) = frule(ārgs, f, args...; kwargs...))
rrule(::RuleConfig, f, args...; kwargs...) = rrule(f, args...; kwargs...)

function frule_via_ad(::RuleConfig{F}, ārgs, f, args...; kwargs...) where F <: Function
    #TODO: Should this pass on the config? I suspect it should so we can use it for avoiding stack-overflows
    return F.instance(ārgs, f, args...; kwargs...)
end
function rrule_via_ad(::RuleConfig{<:Any,R}, f, args...; kwargs...) where R <: Function
    #TODO: Should this pass on the config? I suspect it should so we can use it for avoiding stack-overflows
    return R.instance(ārgs, f, args...; kwargs...)
end

# TODO: do we want this? Or do we need to avoid ending up in a circumstance where it is needed
function frule_via_ad(::RuleConfig{Nothing}, ārgs, f, args...; kwargs...) where F<: Function
    return frule(ārgs, f, args...; kwargs...)
end
function rrule_via_ad(::RuleConfig{<:Any,Nothing}, f, args...; kwargs...)
    return rrule(f, args...; kwargs...)
end
