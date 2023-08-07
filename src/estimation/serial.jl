function estimate_serial(model::ModelingToolkit.ODESystem,
	measured_quantities::Vector{ModelingToolkit.Equation},
	inputs::Vector{ModelingToolkit.Equation},
	data_sample::AbstractDict{Any, Vector{T}} = Dict{Any, Vector{T}}();
	at_time::T = 0.0, solver = Tsit5(), interpolators = nothing,
	method = :homotopy,
	real_tol::Float64 = 1e-10) where {T <: Float}
	check_inputs(measured_quantities, data_sample)
	datasize = length(first(values(data_sample)))
	if interpolators === nothing
		interpolators = Dict("AAA" => aaad,
			"FHD3" => fhdn(3),
			"FHD6" => fhdn(6),
			"FHD8" => fhdn(8),
			"Fourier" => FourierInterp,
			"BaryLagrange" => BarycentricLagrange)
		for i in 1:(datasize-1)
			interpolators["Rational($i)"] = SimpleRationalInterp(i)
		end
	end
	id = ParameterEstimation.check_identifiability(model;
		measured_quantities = measured_quantities,
		inputs = [Num(each.lhs)
				  for each in inputs])
	estimates = Vector{Vector{ParameterEstimation.EstimationResult}}()
	@info "Estimating via the interpolators: $(keys(interpolators))"
	@showprogress for interpolator in interpolators
		unfiltered = estimate_fixed_degree(model, measured_quantities, inputs, data_sample;  #TODO(orebas) we will rename estimated_fixed_degree to estimate_single_interpolator
			identifiability_result = id,
			interpolator = interpolator, at_time = at_time,
			method = method, real_tol = real_tol)
		if length(unfiltered) > 0
			filtered = filter_solutions(unfiltered, id, model, inputs, data_sample;
				solver = solver)
			push!(estimates, filtered)
		else
			push!(estimates,
				[
					EstimationResult(model, Dict(), interpolator, at_time,
						Dict{Any, Interpolant}(),
						ReturnCode.Failure, datasize),
				])
		end
	end
	return post_process(estimates)
end
