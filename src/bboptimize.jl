# FIXME replace Any with Type{Optimizer} when the support for Julia v0.3 would be dropped
ValidMethods = @compat Dict{Symbol,Union(Any,Function)}(
  :random_search => random_search,
  :de_rand_1_bin => de_rand_1_bin,
  :de_rand_2_bin => de_rand_2_bin,
  :de_rand_1_bin_radiuslimited => de_rand_1_bin_radiuslimited,
  :de_rand_2_bin_radiuslimited => de_rand_2_bin_radiuslimited,
  :adaptive_de_rand_1_bin => adaptive_de_rand_1_bin,
  :adaptive_de_rand_1_bin_radiuslimited => adaptive_de_rand_1_bin_radiuslimited,
  :separable_nes => separable_nes,
  :xnes => xnes,
  :resampling_memetic_search => resampling_memetic_searcher,
  :resampling_inheritance_memetic_search => resampling_inheritance_memetic_searcher,
  :simultaneous_perturbation_stochastic_approximation => SimultaneousPerturbationSA2,
  :generating_set_search => GeneratingSetSearcher,
  :probabilistic_descent => direct_search_probabilistic_descent,
)

MethodNames = collect(keys(ValidMethods))

# Default parameters for all convenience methods that are exported to the end user.
DefaultParameters = @compat Dict{Symbol,Any}(
  :NumDimensions  => :NotSpecified, # Dimension of problem to be optimized
  :SearchRange    => (-10.0, 10.0), # Default search range to use per dimension unless specified
  :SearchSpace    => false, # Search space can be directly specified and takes precedence over Dimension and SearchRange if specified.

  :MaxTime        => false,   # Max time in seconds (takes precedence over the other budget-related params if specified)
  :MaxFuncEvals   => false,   # Max func evals (takes precedence over max iterations, but not max time)
  :MaxSteps       => 10000,   # Max iterations gives the least control since different optimizers have different "size" of their "iterations"
  :MinDeltaFitnessTolerance => 1e-50, # Minimum delta fitness (difference between two consecutive best fitness improvements) we can accept before terminating
  :FitnessTolerance => 1e-8,  # Stop optimization when the best fitness found is within this distance of the actual optimum (if known)

  :MaxNumStepsWithoutFuncEvals => 100, # Stop optimization if no func evals in this many steps (indicates a converged/degenerate search)

  :NumRepetitions => 1,     # Number of repetitions to run for each optimizer for each problem

  :ShowTrace      => true,  # Print tracing information during the optimization
  :TraceInterval  => 0.50,  # Minimum number of seconds between consecutive trace messages printed to STDOUT
  :SaveTrace      => false,
  :SaveFitnessTraceToCsv => false, # Save a csv file with information about the major fitness improvement events (only the first event in each fitness magnitude class is saved)
  :SaveParameters => false, # Save parameters to a json file for later scrutiny

  :RandomizeRngSeed => true, # Randomize the RngSeed value before using any random numbers.
  :RngSeed        => 1234,   # The specific random seed to set before any random numbers are generated. The seed is randomly selected if RandomizeRngSeed is true, and this parameter is updated with its actual value.

  :PopulationSize => 50
)

# Setup a fixed-dimensional problem
function setup_problem(problem::OptimizationProblem, parameters = @compat Dict{Symbol,Any}())
  params = Parameters(parameters, DefaultParameters)
  return problem, params
end

# Create a fixed-dimensional problem given
#   any-dimensional problem and a number of dimensions as a parameter
function setup_problem(family::FunctionBasedProblemFamily, parameters = @compat Dict{Symbol,Any}())
  params = Parameters(parameters, DefaultParameters)

  # If an anydim problem was given the dimension param must have been specified.
  if params[:NumDimensions] == :NotSpecified
    throw(ArgumentError("You MUST specify the number of dimensions in a solution when a problem family is given"))
  end
  problem = fixed_dim_problem(family, parameters[:NumDimensions])

  return problem, params
end

# Create a fixed-dimensional problem given
#   a function and a search range + number of dimensions.
function setup_problem(func::Function, parameters = @compat Dict{Symbol,Any}())
  params = Parameters(parameters, DefaultParameters)
  # Check that a valid search space has been stated and create the search_space
  # based on it, or bail out.
  if typeof(params[:SearchRange]) == typeof((0.0, 1.0))
      if params[:NumDimensions] == :NotSpecified
          throw(ArgumentError("You MUST specify the number of dimensions in a solution when giving a search range $(searchRange)"))
      end
      ss = symmetric_search_space(params[:NumDimensions], params[:SearchRange])
  elseif typeof(params[:SearchRange]) == typeof([(0.0, 1.0)])
      ss = RangePerDimSearchSpace(params[:SearchRange])
  else
      throw(ArgumentError("Invalid search range specification."))
  end

  # Now create an optimization problem with the given information. We currently reuse the type
  # from our pre-defined problems so some of the data for the constructor is dummy.

  problem = convert(FunctionBasedProblem, func, "", MinimizingFitnessScheme, ss) # FIXME v0.3 workaround

  return problem, params
end

function compare_optimizers(functionOrProblem::Union(Function, OptimizationProblem);
  max_time = false, search_space = false, search_range = (0.0, 1.0), dimensions = 2,
  methods = MethodNames, parameters = @compat Dict{Symbol,Any}())

  evaluator = 1.0

  results = Any[]
  for(m in methods)
    tic()
    best, fitness, reason, etime, parameters = bboptimize(functionOrProblem; method = m, parameters = parameters,
      max_time = max_time, search_space = search_space, dimensions = dimensions,
      search_range = search_range)
    push!( results,  (m, best, fitness, toq()) )
    evaluator = parameters[:Evaluator]
    delete!(parameters, :Evaluator)
  end

  sorted = sort( results, by = (t) -> t[3] )

  if parameters[:ShowTrace]
    println("\n********************************************************************************")
    println(describe(evaluator))
    for(i in 1:length(sorted))
      println("$(i). $(sorted[i][1]), fitness = $(sorted[i][3]), time = $(sorted[i][4])")
    end
    println("********************************************************************************\n")
  end

  return sorted

end

function compare_optimizers(problems::Dict{Any, OptimizationProblem}; max_time = false,
  methods = MethodNames, parameters = @compat Dict{Symbol,Any}())

  # Lets create an array where we will save how the methods ranks per problem.
  ranks = zeros(length(methods), length(problems))
  fitnesses = zeros(Float64, length(methods), length(problems))
  times = zeros(Float64, length(methods), length(problems))

  problems = collect(problems)

  for i in 1:length(problems)
    name, p = problems[i]
    res = compare_optimizers(p; max_time = max_time, methods = methods, parameters = parameters)
    for(j in 1:length(res))
      method, best, fitness, elapsedtime = res[j]
      index = findfirst(methods, method)
      ranks[index, i] = j
      fitnesses[index, i] = fitness
      times[index, i] = elapsedtime
    end
  end

  avg_ranks = round(mean(ranks, 2), 2)
  avg_fitness = round(mean(fitnesses, 2), 3)
  avg_times = round(mean(times, 2), 2)

  perm = sortperm(avg_ranks[:])
  println("\nBy avg rank:")
  for(i in 1:length(methods))
    j = perm[i]
    print("\n$(i). $(methods[j]), avg rank = $(avg_ranks[j]), avg fitness = $(avg_fitness[j]), avg time = $(avg_times[j]), ranks = ")
    showcompact(ranks[j,:][:])
  end

  perm = sortperm(avg_fitness[:])
  println("\n\nBy avg fitness:")
  for(i in 1:length(methods))
    j = perm[i]
    print("\n$(i). $(methods[j]), avg rank = $(avg_ranks[j]), avg fitness = $(avg_fitness[j]), avg time = $(avg_times[j]), ranks = ")
    showcompact(ranks[j,:][:])
  end

  return ranks, fitnesses
end

function bboptimize(functionOrProblem; max_time = false,
  search_space = false, search_range = (0.0, 1.0), dimensions = 2,
  method = :adaptive_de_rand_1_bin_radiuslimited,
  parameters = @compat Dict{Symbol,Any}())

  # We just pass the kw params along...
  optimizer, problem, params = setup_bboptimize(functionOrProblem;
    max_time = max_time,
    search_space = search_space, search_range = search_range, dimensions = dimensions,
    method = method, parameters = parameters)

  run_optimizer(optimizer, problem, params)

end

function setup_bboptimize(functionOrProblem; max_time = false,
  search_space = false, search_range = (0.0, 1.0), dimensions = 2,
  method = :adaptive_de_rand_1_bin_radiuslimited,
  parameters = @compat Dict{Symbol,Any}())

  params = Parameters(parameters, DefaultParameters)
  params[:MaxTime] = max_time
  params[:SearchSpace] = search_space
  params[:SearchRange] = search_range
  params[:NumDimensions] = dimensions

  problem, params = setup_problem(functionOrProblem, params)

  # Create a random solution from the search space and ensure that the given function returns a Number.
  ind = rand_individual(BlackBoxOptim.search_space(problem))
  res = fitness(ind, problem)
  if !isa(res, Number)
    throw(ArgumentError("The supplied function does NOT return a number when called with a potential solution (when called with $(ind) it returned $(res)) so we cannot optimize it!"))
  end

  # Check that max_time is larger than zero if it has been specified.
  if params[:MaxTime] != false
    if params[:MaxTime] <= 0.0
      throw(ArgumentError("The max_time must be a positive number"))
    else
      params[:MaxTime] = convert(Float64, params[:MaxTime])
    end
  end

  # Check that a valid number of iterations has been specified. Print warning if higher than 1e8.
  if params[:MaxFuncEvals] != false
    if params[:MaxFuncEvals] < 1
      throw(ArgumentError("The number of function evals MUST be a positive number"))
    elseif params[:MaxFuncEvals] >= 1e8
      println("Number of allowed function evals is $(params[:MaxFuncEvals]); this can take a LONG time")
    end
  end

  # Check that a valid number of iterations has been specified. Print warning if higher than 1e8.
  if params[:MaxSteps] < 1
    throw(ArgumentError("The number of iterations MUST be a positive number"))
  elseif params[:MaxSteps] >= 1e7
    println("Number of allowed iterations is $(params[:MaxSteps]); this can take a LONG time")
  end

  # Check that a valid population size has been given.
  if params[:PopulationSize] < 2
    throw(ArgumentError("The population size MUST be at least 2"))
  end

  # Check that a valid method has been specified and then set up the optimizer
  if (typeof(method) != Symbol) || !any([(method == vm) for vm in MethodNames])
    throw(ArgumentError("The method specified, $(method), is NOT among the valid methods: $(MethodNames)"))
  end

  params = Parameters(params, @compat Dict{Symbol,Any}(
    :Evaluator    => ProblemEvaluator(problem)
  ))
  optimizer_func = ValidMethods[method]
  optimizer = optimizer_func(problem, params)

  return (optimizer, problem, params)
end

function tr(msg, parameters, obj = None)
  if parameters[:ShowTrace]
    print(msg)
    if obj != None
      showcompact(obj)
    end
  end
  if parameters[:SaveTrace]
    # No saving for now
  end
end

# The ask and tell interface is more general since you can mix and max
# elements from several optimizers using it. However, in this top-level
# execution function we do not make use of this flexibility...
function step!(optimizer::AskTellOptimizer, evaluator::Evaluator)
  candidates = ask(optimizer)
  rank_by_fitness!(evaluator, candidates)
  return tell!(optimizer, candidates)
end

# step for SteppingOptimizers
function step!(optimizer::SteppingOptimizer, evaluator::Evaluator)
  step!(optimizer)
  return 0
end

function run_optimizer(opt::Optimizer, problem::OptimizationProblem, parameters = @compat Dict{Symbol,Any}())

  # init RNG
  if parameters[:RandomizeRngSeed]
    parameters[:RngSeed] = rand(1:1_000_000)
    srand(parameters[:RngSeed])
  end

  # No max time if unspecified. If max time specified it takes precedence over
  # max_steps and MaxFuncEvals. If no max time MaxFuncEvals takes precedence over
  # MaxSteps.
  if parameters[:MaxTime] == false
    max_time = Inf
    if parameters[:MaxFuncEvals] != false
      max_fevals = parameters[:MaxFuncEvals]
      max_steps = Inf
    else
      max_steps = parameters[:MaxSteps]
      max_fevals = Inf
    end
  else
    max_steps = Inf
    max_fevals = Inf
    max_time = parameters[:MaxTime]
  end

  # Now set up an evaluator for this problem. This will handle fitness
  # comparisons, keep track of the number of function evals as well as
  # keep an archive and top list.
  evaluator = get(parameters, :Evaluator, ProblemEvaluator(problem))

  num_better = 0
  num_better_since_last = 0
  tr("Starting optimization with optimizer $(name(opt))\n", parameters)

  termination_reason = "" # Will be set in loop below...

  last_numfevals = -1
  num_steps_without_fevals = 0

  step = 1
  t = last_report_time = start_time = time()
  elapsed_time = 0.0

  while( true )

    if elapsed_time > max_time
      termination_reason = "Max time reached"
      break
    end

    if num_evals(evaluator) > max_fevals
      termination_reason = "Max number of function evaluations reached"
      break
    end

    if num_evals(evaluator) == last_numfevals
        num_steps_without_fevals += 1
        if num_steps_without_fevals > parameters[:MaxNumStepsWithoutFuncEvals]
            termination_reason = "Too many steps ($(num_steps_without_fevals)) without any function evaluations (probably search has converged)"
            break
        end
    else
        num_steps_without_fevals = 0
    end
    last_numfevals = num_evals(evaluator)

    if step > max_steps
      termination_reason = "Max number of steps reached"
      break
    end

    if delta_fitness(evaluator.archive) < parameters[:MinDeltaFitnessTolerance]
      termination_reason = "Delta fitness below tolerance"
      break
    end

    if fitness_is_within_ftol(evaluator, parameters[:FitnessTolerance])
      termination_reason = "Within fitness tolerance of optimum"
      break
    end

    # Report on progress every now and then...
    if (t - last_report_time) > parameters[:TraceInterval]
      last_report_time = t
      num_better += num_better_since_last

      # Always print step number, num fevals and elapsed time
      tr(@sprintf("%.2f secs, %d evals, %d steps",
        elapsed_time, num_evals(evaluator), step), parameters)

      # Only print if this optimizer reports on number of better. They return 0
      # if they do not.
      if num_better_since_last > 0
        tr(@sprintf(", improv/step: %.3f (last = %.4f)",
          num_better/step, num_better_since_last/step), parameters)
        num_better_since_last = 0
      end

      # Always print fitness if num_evals > 0
      if num_evals(evaluator) > 0
        tr(@sprintf(", %.9f", best_fitness(evaluator.archive)), parameters)
      end

      tr("\n", parameters)
    end

    num_better_since_last += step!(opt, evaluator)

    step += 1
    t = time()
    elapsed_time = t - start_time
  end

  step -= 1 # Since it is one too high after while loop above

  tr("\nOptimization stopped after $(step) steps and $(elapsed_time) seconds\n", parameters)
  tr("Termination reason: $(termination_reason)\n", parameters)
  tr("Steps per second = $(step/elapsed_time)\n", parameters)
  tr("Function evals per second = $(num_evals(evaluator)/elapsed_time)\n", parameters)
  tr("Improvements/step = $((num_better+num_better_since_last)/max_steps)\n", parameters)
  tr("Total function evaluations = $(num_evals(evaluator))\n", parameters)

  if typeof(opt) <: PopulationOptimizer
    tr("\nMean value (in population) per position:", parameters, params_mean(population(opt)))
    tr("\n\nStd dev (in population) per position:", parameters, params_std(population(opt)))
  end

  best = best_candidate(evaluator.archive)
  fitness = best_fitness(evaluator.archive)
  tr("\n\nBest candidate found: ", parameters, best)
  tr("\n\nFitness: ", parameters, fitness)
  tr("\n\n", parameters)

  if parameters[:SaveFitnessTraceToCsv]
    timestamp = strftime("%y%m%d_%H%M%S", ifloor(start_time))
    filename = "$(timestamp)_$(problem_summary(evaluator))_$(name(opt)).csv"
    filename = replace(replace(filename, r"\s+", "_"), r"/", "_")
    header_prefix = "Problem,Dimension,Optimizer"
    line_prefix = "$(name(problem)),$(numdims(problem)),$(name(opt))"
    save_fitness_history_to_csv_file(evaluator.archive, filename;
      header_prefix = header_prefix, line_prefix = line_prefix,
      bestfitness = opt_value(problem))
  end

  return best, fitness, termination_reason, elapsed_time, parameters, num_evals(evaluator)
end

# Summarize a vector of float values by stating its mean, std dev and median.
function report_on_values(desc, v, lpad = "", rpad = "", digits = 3)
  println("$(lpad)$(desc): $(signif(mean(v), digits)) (std. dev = $(signif(std(v), digits)), median = $(signif(median(v), digits)))")
end

# Report on the number of times each key in a count dict was encountered.
# Returns a percentage dict calculated while iterating over the counted items.
function count_dict_report(dict, desc, lpad = "", rpad = "")
  println(desc, ":")
  total = sum(collect(values(dict)))
  pdict = Dict()
  for (r, c) in dict
    pdict[r] = round(100.0*c/total, 2)
    println(lpad, r, ": ", c, " (", pdict[r], "%)", rpad)
  end
  pdict
end

# Print a report based on a result dict from one set of repeated runs of
# an optimization method. Returns the success rate, i.e. number of times the
# termination reason was "Within fitness tolerance...".
function report_from_result_dict(statsdict)
  println("Method: $(statsdict[:method])")
  pdict = count_dict_report(statsdict[:reasoncounts], "  Termination reasons", "    ")
  report_on_values("Fitness", statsdict[:fitnesses], "  ")
  report_on_values("Time", statsdict[:times], "  ")
  report_on_values("Num function evals", statsdict[:numevals], "  ")
  println("  Success rate: ", round(pdict["Within fitness tolerance of optimum"], 3), "%\n")
  pdict["Within fitness tolerance of optimum"]
end

function rank_result_dicts_by(result_dicts, byfunc, desc; rev = false,
  descsummary = "mean", digits = 3, rpad = "")

  ranked = BlackBoxOptim.Utils.assign_ranks_within_tolerance(result_dicts; by = byfunc, tolerance = 1e-3, rev = rev)
  println("Ranked by $(descsummary) $(desc):")
  for (rank, rd, value) in ranked
    println("  $(rank). $(rd[:method]), $(signif(value, digits))$(rpad)")
  end
  println("")

end

function report_on_methods_results_on_one_problem(problem, result_dicts, numrepeats, max_time, ftol)

  println("********************************************************************************\n")

  println("Problem: $(name(problem)), num dims = $(numdims(problem))")
  println("  Num repeats per method = ", numrepeats)
  println("  Fitness tolerance = ", ftol, " (a run is a success if it reaches to within this value of true optimum)")
  println("  Max time budget per run = ", max_time, " secs\n")

  rank_result_dicts_by(result_dicts, (d) -> d[:success_rate], "success rate (to reach within $(ftol) of optimum)";
    descsummary = "median", rev = true, rpad = "%")
  rank_result_dicts_by(result_dicts, (d) -> median(d[:fitnesses]), "fitness"; descsummary = "median")
  rank_result_dicts_by(result_dicts, (d) -> median(d[:times]), "time (in seconds)";
    descsummary = "median", rpad = " secs")
  rank_result_dicts_by(result_dicts, (d) -> int(median(d[:numevals])), "num function evals"; descsummary = "median")

  for rd in result_dicts
    report_from_result_dict(rd)
  end

end

function repeated_bboptimize(numrepeats, problem, dim, methods, max_time, ftol = 1e-5, parameters = Dict{Symbol, Any}())

  fp = BlackBoxOptim.fixed_dim_problem(problem, dim)
  result_dicts = Dict{Symbol,Any}[]

  # Just so they are declared
  ps = best_so_far = nothing

  params = Parameters(parameters, @compat Dict{Symbol,Any}(:FitnessTolerance => ftol))

  for m in methods

    ts, fs, nes = zeros(numrepeats), zeros(numrepeats), zeros(Int, numrepeats)
    rcounts = @compat Dict{String,Int}("Within fitness tolerance of optimum" => 0)

    for i in 1:numrepeats
      p = fp # BlackBoxOptim.ShiftedAndBiasedProblem(fp)
      best, fs[i], reason, ts[i], ps, nes[i] = bboptimize(p; max_time = max_time,
        method = m, parameters = params)
      rcounts[reason] = 1 + get(rcounts, reason, 0)
    end

    if best_so_far == nothing
      best_so_far = worst_fitness(ps[:Evaluator])
    end

    best_so_far =

    rdict = @compat Dict{Symbol,Any}(:method => m, :fitnesses => fs, :times => ts, :numevals => nes, :reasoncounts => rcounts)
    rdict[:success_rate] = report_from_result_dict(rdict)
    push!(result_dicts, rdict)

  end

  report_on_methods_results_on_one_problem(fp, result_dicts, numrepeats, max_time, ftol)

end
