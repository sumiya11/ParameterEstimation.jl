"""
    rational_interpolation_coefficients(x, y, n)

Perform a rational interpolation of the data `y` at the points `x` with numerator degree `n`.
This function only returns the coefficients of the numerator and denominator polynomials.

# Arguments
- `x`: the points where the data is sampled (e.g. time points).
- `y`: the data sample.
- `n`: the degree of the numerator.

# Returns
- `c`: the coefficients of the numerator polynomial.
- `d`: the coefficients of the denominator polynomial.
"""
function rational_interpolation_coefficients(x, y, n)
    N = length(x)
    m = N - n - 1
    A = zeros(N, N)
    if m > 0
        A_left_submatrix = reduce(hcat, [x .^ (i) for i in 0:(n)])
        A_right_submatrix = reduce(hcat, [x .^ (i) for i in 0:(m - 1)])
        A = hcat(A_left_submatrix, -y .* A_right_submatrix)
        b = y .* (x .^ m)
        @info det(A), cond(A)
        open("A.txt", "w") do io
            for i in 1:size(A, 1)
                for j in 1:size(A, 2)
                    print(io, A[i, j], " ")
                end
                println(io)
            end
        end
        open("b.txt", "w") do io
            for i in 1:length(b)
                println(io, b[i])
            end
        end
        # TODO: check for det < 1e-20
        e = @det(A)
        m = e < 1e-20 ? (1 / e)^(1 / N) : 1
        A = m * A
        prob = LinearSolve.LinearProblem(A, b)
        c = LinearSolve.solve(prob) / m
        return c[1:(n + 1)], [c[(n + 2):end]; 1]
    else
        A = reduce(hcat, [x .^ i for i in 0:n])
        b = y
        prob = LinearSolve.LinearProblem(A, b)
        c = LinearSolve.solve(prob)
        return c, [1]
    end
end

"""
    interpolate(identifiability_result, data_sample, time_interval,
                measured_quantities,
                interpolation_degree::Int = 1,
                diff_order::Int = 1,
                at_t::Float = 0.0)

This function performs the key step in parameter estimation.

    It interpolates the data in `data_sample` and computes the `TaylorSeries` expansion.
    These results are stored in the `Interpolant` object and are applied to the polynomial system in `identifiability_result`.

# Arguments
- `identifiability_result`: the result of the identifiability check.
- `data_sample`: a dictionary of the data samples. The keys are the symbols of the measured quantities and the values are the data samples.
- `time_interval`: the time interval where the data is sampled.
- `measured_quantities`: the measured quantities (equations of the form `y ~ x`).
- `interpolation_degree::Int = 1`: the degree of the numerator of the rational interpolation.
- `diff_order::Int = 1`: the order of the derivative to be computed.
- `at_t::Float = 0.0`: the time point where the Taylor series expansion is computed.

# Returns
- `System`: the polynomial system with the interpolated data applied. This system is compatible with `HomotopyContinuation` solving.
"""
function interpolate(identifiability_result, data_sample, time_interval,
                     measured_quantities,
                     interpolation_degree::Int = 1,
                     diff_order::Int = 1,
                     at_t::Float = 0.0)
    polynomial_system = identifiability_result["polynomial_system"]
    interpolants = Dict{Any, Interpolant}()
    for (key, sample) in pairs(data_sample)
        y_function_name = map(x -> replace(string(x.lhs), "(t)" => ""),
                              filter(x -> string(x.rhs) == string(key),
                                     measured_quantities))[1]
        tsteps = range(time_interval[1], time_interval[2], length = length(sample))
        interpolant = ParameterEstimation.interpolate(tsteps, sample,
                                                      interpolation_degree,
                                                      diff_order, at_t)
        interpolants[key] = interpolant
        err = sum(abs.(sample - interpolant.I.(tsteps))) / length(tsteps)
        @info "Mean Absolute error in interpolation: $err interpolating $key"
        for (y_func, y_deriv_order) in pairs(identifiability_result["Y_eq"])
            if occursin(y_function_name, string(y_func))
                y_derivs_vals = Dict(ParameterEstimation.nemo2hc(y_func) => interpolant.dIdt[y_deriv_order] *
                                                                            factorial(y_deriv_order))
                polynomial_system = HomotopyContinuation.evaluate(ParameterEstimation.nemo2hc.(polynomial_system),
                                                                  y_derivs_vals)
            end
        end
    end
    try
        return System(polynomial_system), interpolants
    catch KeyError
        throw(ArgumentError("HomotopyContinuation threw a KeyError, it is likely that " *
                            "you are using Unicode characters in your input. Consider " *
                            "using ASCII characters instead."))
    end
end

"""
    interpolate(time, sample, numer_degree::Int, diff_order::Int = 1)

This function performs a rational interpolation of the data `sample` at the points `time` with numerator degree `numer_degree`.
It returns an `Interpolant` object that contains the interpolated function and its derivatives.
"""
function interpolate(time, sample, numer_degree::Int, diff_order::Int = 1,
                     at_t::Float = 0.0)
    # TODO: make numer_degree optional
    numer_coef, denom_coef = rational_interpolation_coefficients(time, sample,
                                                                 numer_degree)
    numer_function(t) = sum(numer_coef[i] * t^(i - 1) for i in 1:length(numer_coef))
    denom_function(t) = sum(denom_coef[i] * t^(i - 1) for i in 1:length(denom_coef))
    interpolated_function(t) = numer_function(t) / denom_function(t)
    return Interpolant(interpolated_function,
                       differentiate_interpolated(interpolated_function, diff_order, at_t))
end

function differentiate_interpolated(interpolated_function, diff_order::Int,
                                    at_t::Float = 0.0)
    τ = Taylor1(diff_order + 1)
    taylor_expantion = interpolated_function(τ - at_t)
    return taylor_expantion
end