# Implements the memtic search algorithms RS and RIS.
#
# The "Resampling Search" (RS) memetic algorithm is described in:
#
#  F. Caraffini, F. Neri, M. Gongora and B. N. Passow, "Re-sampling Search: A 
#  Seriously Simple Memetic Approach with a High Performance", 2013.
#
# and its close sibling "Resampling Inheritance Search" (RIS) is described in:
#
#  F. Caraffini, F. Neri, B. N. Passow and G. Iacca, "Re-sampled Inheritance 
#  Search: High Performance Despite the Simplicity", 2013.
#  

RSDefaultParameters = {
  :PrecisionRatio    => 0.40, # 40% of the diameter is used as the initial step length
  :PrecisionTreshold => 1e-6  # This is the one they use in the papers; I want to set this even lower...
}

# SteppingOptimizer's do not have an ask and tell interface since they would be
# complex to implement if forced into that form.
abstract SteppingOptimizer <: Optimizer
has_ask_tell_interface(rms::SteppingOptimizer) = false

type ResamplingMemeticSearcher <: SteppingOptimizer
  name::ASCIIString
  params::Parameters
  evaluator::Evaluator
  resampling_func::Function

  precisions      # Cache the starting precision values so we need not calc them for each step
  diameters       # Cache the diameters...

  elite           # Current elite (best) candidate
  elite_fitness   # Fitness of current elite

  # Constructor for RS:
  ResamplingMemeticSearcher(evaluator; parameters = {},
    resampling_function = random_resample,
    name = "Resampling Memetic Search (RS)"
    ) = begin

    params = Parameters(parameters, RSDefaultParameters)

    elite = rand_individual(search_space(evaluator))

    diams = diameters(search_space(evaluator))

    new(name, params, evaluator, resampling_function,
      params[:PrecisionRatio] * diams, diams,
      elite, evaluate(evaluator, elite))

  end
end

RISDefaultParameters = {
  :InheritanceRatio => 0.30   # On average, 30% of positions are inherited when resampling in RIS
}

# Constructor for the RIS:
function ResamplingInheritanceMemeticSearcher(evaluator; parameters = {})
  ResamplingMemeticSearcher(evaluator; 
    parameters = Parameters(parameters, RISDefaultParameters, RSDefaultParameters),
    resampling_function = random_resample_with_inheritance, 
    name = "Resampling Inheritance Memetic Search (RIS)")
end

function resampling_memetic_searcher(params)
  ResamplingMemeticSearcher(params[:Evaluator]; parameters = params)
end

function resampling_inheritance_memetic_searcher(params)
  ResamplingMemeticSearcher(params[:Evaluator]; parameters = params)
end

# For Resampling Search (RS) the resample is purely random.
random_resample(rms::ResamplingMemeticSearcher) = rand_individual(search_space(rms.evaluator))

# For Resampling Inheritance Search (RIS) the resample has an inheritance component.
function random_resample_with_inheritance(rms::ResamplingMemeticSearcher)
  xt = random_resample(rms)
  n = numdims(rms.evaluator)
  i = rand(1:n)
  Cr = 0.5^(1/(rms.params[:InheritanceRatio]*n)) # See equation 3 in the RIS paper
  k = 1

  while rand() <= Cr && k < n
    xt[i] = rms.elite[i]
    i = 1 + mod(i, n)
    k += 1
  end

  return xt
end

function step(rms::ResamplingMemeticSearcher)

  # First randomly sample two candidates and select the best one. It seems
  # RS and RIS might be doing this in two different ways but use the RS way for 
  # now.
  trial, fitness = best_of(rms.evaluator, rms.resampling_func(rms), rms.resampling_func(rms))

  # Update elite if new trial is better. This is how they write it in the RIS paper
  # but in the RS paper it seems they always update the elite. Unclear! To me it
  # seems we should always update since we have already done a local search from
  # the current elite so it has a "head start" compared to new sampled points
  # which have not yet gone through local refinement. Since the evaluator/archive
  # keeps the best candidates anyway there is no risk for us in always overwriting the elite...
  set_as_elite_if_better(rms, trial, fitness)

  # Then run the local search on the elite one until step length too small.
  return local_search(rms)

end

function set_as_elite_if_better(rms::ResamplingMemeticSearcher, candidate, fitness)
  if is_better(rms.evaluator, fitness, rms.elite_fitness)
    rms.elite = candidate
    rms.elite_fitness = fitness
    return true
  else
    return false
  end
end

function stop_due_to_low_precision(rms::ResamplingMemeticSearcher, precisions)
  norm(precisions ./ rms.diameters) < rms.params[:PrecisionTreshold]
end

function local_search(rms::ResamplingMemeticSearcher)
  ps = copy(rms.precisions)
  xt = copy(rms.elite)
  oldfitness = tfitness = copy(rms.elite_fitness)

  #println("In: ps = $(ps), xt = $(xt), tfitness = $(tfitness)")

  while !stop_due_to_low_precision(rms, ps)

    xs = copy(xt)

    for i in 1:numdims(rms.evaluator)

      # This is how it is written in orig papers. To me it seems better to
      # take the step in a random direction; why prioritize one direction?
      xs[i] = xt[i] - ps[i]
      #println("xs = $(xs), xt = $(xt), tfitness = $(tfitness)")

      if is_better(rms.evaluator, xs, tfitness)
        #println("xs better 1! $(xt[i]) -> $(xs[i]), $(tfitness) -> $(last_fitness(rms.evaluator))")
        xt[i] = xs[i]
        tfitness = last_fitness(rms.evaluator)
      else
        xs[i] = xt[i] + ps[i]/2

        if is_better(rms.evaluator, xs, tfitness)
          #println("xs better 2! $(xt[i]) -> $(xs[i]), $(tfitness) -> $(last_fitness(rms.evaluator))")
          xt[i] = xs[i]
          tfitness = last_fitness(rms.evaluator)
        end
      end

    end

    if !set_as_elite_if_better(rms, xt, tfitness)
      ps = ps / 2
    end

  end

  # println("oldfitness = $(oldfitness), tfitness = $(tfitness)")

  return xt, tfitness
end