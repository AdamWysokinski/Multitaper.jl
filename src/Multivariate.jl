
""" T squared test for simultaneous line components """ 
function testTsq(dcs,tap::Ecoef)
  ell, k    = (Float64(size(tap.coef,1)), Float64(size(tap.coef,2)))
  if (ell > k)
    println("Tsq test error: you have K = $k tapers and L = $ell eigencoefficients,
            but L must be less than K.")
    return NaN
  else
    sum2dc  = sum(abs2, dcs) 
    # Following Thomson (2011) "Some problems ... cyclostationary data"
    Q       = tap.coef*dcs/sum2dc 
    # vector of mean estimates (15), l of them
    Rt      = copy(transpose(tap.coef)) - kron(transpose(Q),dcs) 
    # tap1 is ell by k, Q is 1 by ell, dc is k by 1
    Tsq     = ((k-ell)/ell)*sum2dc*real.(transpose(Q)*pinv(transpose(Rt)*Rt)*Q)
    pval    = StatsFuns.fdistccdf(2*ell,2*(k-ell),Tsq)
    return pval
  end
end

"""
    multispec(S1, S2; <keyword arguments>)

Computes multitaper cross-spectrum or coherence when given two time series with same sampling.

...
# Arguments
 - `S1::Union{Vector{T},Ecoef} where T<:Float64`: the vector containing the first time series
 - `S2::Union{Vector{T},Ecoef} where T<:Float64`: the vector containing the second time series
 - `outp::Symbol`: output can be either :coh for coherence, :spec for cross-spectrum, or :transf for transfer function
 - `NW::Float64 = 4.0`: time-bandwidth product of estimate
 - `K::Int64 = 6`: number of slepian tapers, must be <= 2*NW
 - `offset::Union{Float64,Int64} = 0` set to nonzero value if offset coherence or cross-spectrum is desired. If Float64 is used, this will be converted to nearest FFT bin.
 - `dt::Float64`: sampling rate in time units 
 - `ctr::Bool`: whether or not to remove the mean before computing the multitaper spectrum
 - `pad::Float64 = 1.0`: factor by which to pad the series, i.e. spectrum length will be pad times length of the time series.
 - `dpVec::Union{Matrix{Float64},Nothing} = nothing`: Matrix of dpss's, if they have been precomputed
 - `guts::Bool = false`: whether or not to return the eigencoefficients in the output struct
 - `jk::Bool = true`: Compute jackknifed confidence intervals
 - `Tsq::Union{Vector{Int64},Vector{Vector{Int64}},Nothing} = nothing`: which frequency indices to compute the T-squared test for multiple line components. Defaults to none.
 - `alph::Float64 = 0.05`: significance cutoff for the Tsquared test
...

...
# Outputs
 - `MtSpec`, `MtCoh`, or `MtTransf` struct containing the spectrum, coherence or transfer function, depending on the selection of `outp` input. 
...

See also: [`dpss_tapers`](@ref), [`MtSpec`](@ref), [`mdmultispec`](@ref), [`mdslepian`](@ref)
"""
function multispec(S1::Union{Vector{T},Ecoef}, S2::Union{Vector{T},Ecoef}; 
                   outp=:coh, NW=4.0, K=6, offset=0, dt=1.0, ctr=true, pad=1.0,
                   dpVec=nothing, guts=false, jk=false, Tsq=nothing, alph=0.05) where{T}
  
  if (typeof(S1) == Ecoef) && (typeof(S2) == Ecoef)
    coefswts = [S1, S2]
    halffreq = size(S1.coef,1)
    fftleng  = 2*halffreq - 1 # This is only for real data
    lengt    = Int64(round(fftleng/pad))
  elseif ((typeof(S1) == Vector{Float64}) && (typeof(S2) == Vector{Float64})) || 
          ((typeof(S1) == Vector{ComplexF64}) && 
         (typeof(S2) == Vector{ComplexF64}))
    # Make sure vectors are compatible
    if (length(S1) != length(S2))
      error("Vectors must be the same length")
    end
    # Compute the lengths of the spec obj
    lengt, fftleng, halffreq = output_len(S1,pad)
    # Compute the array of dpss vectors if they aren't given.
    if (dpVec == nothing) 
      dpVec = dpss_tapers(lengt, NW, K)
      dpVec .*= sqrt(dt)
    end 
    coefswts = map(x->multspec_guts(x,dpVec,fftleng,halffreq,var(x),ctr,nothing),[S1,
                  S2])
  end

  # If offset cross-spectrum or coherence is chosen
  if offset != 0
    offset = freq_to_int([offset], lengt, dt)[1]
    if offset > 0
      ind = vcat(collect(1:halffreq), 
                 collect((halffreq-1):-1:2))[offset:(halffreq+offset-1)]
    elseif offset < 0 
      ind = vcat(collect((halffreq):-1:2), 
                 collect(1:halffreq))[(halffreq+offset):(2*halffreq+offset-1)]
    end
    # Shift the first set of eigencoefficients forward or backwards accordingly
    coefswts[1] = Ecoef(coefswts[1].coef[ind,:], 
                   (coefswts[1].wts == nothing ? nothing : coefswts[1].wts[ind,:]))
    foffset = int_to_freq([offset],lengt,dt)[1]
    freq = (1/dt)*range(foffset, 0.5 + foffset, length=halffreq)  
  elseif offset == 0
    freq = (1/dt)*range(0, 0.5, length=halffreq)
  end

  # Output is spectrum, coherence, or transfer function (outp = :spec, :coh or
  # :transf)
  S, jv    = jk ? jknife(coefswts...,outp) : (jknife(coefswts...,outp)[1], nothing)
  S       .*= (outp == :cross) ? dt : 1.0
  # To compute the transfer functions, we need to use the following helper code
  if outp == :transf
    B = mapreduce(f ->
                  transpose(mttransfn(coefswts[1].coef[f,:],
                  coefswts[2].coef[f,:])[1]),
                  vcat, 1:length(S))
  end
  # Now we need to get the phase estimate 
  phase, jphase = jk ? jknife_phase(coefswts...) : (jknife_phase(coefswts...)[1],
                       nothing)

  # Compute the T^2- test if requested:
  dcs      = (Tsq != nothing) ? map(isodd,1:K).*vec(sum(dpVec,dims=1)) : nothing

  # Do the Tsquared test
  if typeof(Tsq) != Nothing
    Tsq      = (typeof(Tsq) <: Vector{Number}) ? [Tsq] : Tsq
    map!(x -> freq_to_int(Tsq[x], lengt, dt), Tsq, eachindex(Tsq))
    Tsq = Vector{Vector{Int64}}(Tsq)  
    if (2*K < (true ? 1 : 2)*maximum(length.(Tsq)))
      error("There are too few tapers for the number of Tsq tests.")
    end
    Tv = map(x->testTsq(dcs,
             Ecoef(vcat(coefswts[1].coef[Tsq[x],:],coefswts[2].coef[Tsq[x],:]),
             nothing)),eachindex(Tsq)) 
  else
    Tv = nothing
  end

  params = MtParams(NW, K, lengt, dt, fftleng, 1, nothing)   
  if outp == :spec
    return MtSpec(freq, S, phase, params, (guts ? coefswts : nothing), 
                nothing, (jk ?  [jv, jphase] : nothing), Tv) 
  elseif outp == :coh
    return MtCoh(freq, S, phase, params, (guts ? coefswts : nothing), 
                     (jk ?  [jv,jphase] : nothing), Tv) 
    # frequency, spec/crosspec, coef & weights, jackknife, Tsq test.
  elseif outp == :transf
    return MtTransf(freq, abs.(B).^2, unwrapphase(angle.(vec(B))*180/pi,:deg), 
                    params, (guts ? coefswts : nothing), nothing)
  end

end

"""
    mt_ccvf(S; <keyword arguments>)

Computes univariate multitaper cross-covariance/cross-correlation function.
Inputs a MtCoh or MtSpec struct.

...
# Arguments
 - `S::Union{MtCoh,MtSpec}`: the vector containing the result of an multiivariate call to `multispec`
 - `typ::Symbol = :ccvf`: whether to compute cross-correlation function (:ccf) or cross-covariance function (:ccvf)
...

...
# Outputs
 - `MtCcvf`, `MtCcf` depending on the selection of `typ` input above.
...

See also: [`multispec`](@ref)
"""
"""  """
function mt_ccvf(S; typ=:ccvf)   
  if typeof(S) == MtCoh
    lags = S.params.dt*S.params.N*range(-1.0, 1.0, length=length(S.coh))
    if typ == :ccvf
      error("Cannot compute cross covariance from coherence.")
    elseif typ == :ccf
      return MtCcf(lags, fftshift(real.(ifft(S.coh))), S.params)
    end
  elseif typeof(S) == MtSpec
  lags = S.params.dt*S.params.N*range(-1.0, 1.0, length=length(S.S))
    if typ == :ccvf
      return MtCcvf(lags, fftshift(real.(ifft(S.S))), S.params)
    elseif typ == :ccf
      ccvf = real.(ifft(S.S))[1:length(S.S)]
      return MtCcf(lags, fftshift(ccvf)/ccvf[1], S.params)
    end
  else
    error("Select one of :ccvf (cross covariance), :ccf (cross correlation) for
           output")
  end
end

"""
    mt_ccvf(S1, S2; <keyword arguments>)

Computes bivariate multitaper cross-covariance/cross-correlation function from two time series

...
# Arguments
 - `S1::Vector{T} where T<:Number`: the vector containing the first time series
 - `S2::Vector{T} where T<:Number`: the vector containing the second time series
 - `typ::Symbol`: whether to compute cross-covariance function (:ccvf), or cross-correlation function (:ccf)
 - `NW::Float64 = 4.0`: time-bandwidth product of estimate
 - `K::Int64 = 6`: number of slepian tapers, must be <= 2*NW
 - `dt::Float64`: sampling rate in time units 
 - `ctr::Bool`: whether or not to remove the mean before computing the multitaper spectrum
 - `pad::Float64 = 1.0`: factor by which to pad the series, i.e. spectrum length will be pad times length of the time series.
 - `dpVec::Union{Matrix{Float64},Nothing} = nothing`: Matrix of dpss's, if they have been precomputed
 - `guts::Bool = false`: whether or not to return the eigencoefficients in the output struct
 - `jk::Bool = true`: Compute jackknifed confidence intervals
 - `Tsq::Union{Vector{Int64},Vector{Vector{Int64}},Nothing} = nothing`: which frequency indices to compute the T-squared test for multiple line components. Defaults to none.
 - `alph::Float64 = 0.05`: significance cutoff for the Tsquared test
...

...
# Outputs
 - `MtCcvf` struct, depending on the selection of `typ` input above.
...

See also: [`multispec`](@ref)
"""
function mt_ccvf(S1::Vector{T}, S2::Vector{T}; typ=:ccvf, NW=4.0, K=6, dt=1.0,
                 ctr=true, pad=1.0, dpVec=nothing, guts=false, jk=false,
                 Tsq=nothing, alph=0.05) where{T}
  if (typ != :ccvf)&&(typ != :ccf)
    error("Output type must be one of cross-covariance (:ccvf) or cross-correlation 
          (:ccf).")
  end
  S = multispec(S1, S2, outp = :spec, 
                NW = NW, K = K, dt = dt, ctr = ctr, pad = pad, dpVec = dpVec, 
                guts = false, 
                jk = false, Tsq = nothing, alph = alph) 
  return mt_ccvf(S; typ = typ) 
end

"""
    multispec(S1; <keyword arguments>)

Multivariate version of the multispec call, data are in the columns of a matrix
...
# Arguments
 - `S1::Matrix{T} where T<:Float64`: the vector containing the first time series
 - `outp::Symbol`: output can be either :coh for coherence, :justspeccs to compute just the spectra, or :cross for cross-spectra
 - `NW::Float64 = 4.0`: time-bandwidth product of estimate
 - `K::Int64 = 6`: number of slepian tapers, must be <= 2*NW
 - `dt::Float64`: sampling rate in time units 
 - `ctr::Bool`: whether or not to remove the mean before computing the multitaper spectrum
 - `pad::Float64 = 1.0`: factor by which to pad the series, i.e. spectrum length will be pad times length of the time series.
 - `dpVec::Union{Matrix{Float64},Nothing} = nothing`: Matrix of dpss's, if they have been precomputed
 - `guts::Bool = false`: whether or not to return the eigencoefficients in the output struct
 - `a_weight::Bool = true`: whether or not to adaptively weight the spectra
 - `jk::Bool = false`: Compute jackknifed confidence intervals
 - `Ftest:Bool = false`: Compute F-test for line components
 - `Tsq::Union{Vector{Int64},Vector{Vector{Int64}},Nothing} = nothing`: which frequency indices to compute the T-squared test for multiple line components. Defaults to none.
 - `alph::Float64 = 0.05`: significance cutoff for the Tsquared test
...

...
# Outputs
 - `Tuple{Vector{MtSpec},Vector{P},Union{Float64,Vector{Float64}}} where P = Union{MtCoh,MtSpec}` 
struct containing the spectra, coherence or crossspectra, and Tsquared test p-values. 
Ouput of middle arg depends on the selection of `outp` input. 
...

See also: [`dpss_tapers`](@ref), [`MtSpec`](@ref), [`mdmultispec`](@ref), [`mdslepian`](@ref)
"""
""""""
function multispec(S1::Matrix{T}; outp=:coh, NW=4.0, K=6, dt=1.0, ctr=true,
                   pad=1.0, dpVec=nothing, guts=false, a_weight=true, jk=false,
                   Ftest=false, Tsq=nothing, alph=0.05) where{T}

  lengt, p = size(S1)

  if !((outp == :cross)||(outp == :coh) || (outp == :justspecs))
    error("The output must be one of :cross, :coh, or :justspecs")
e end        

  if p > 3
    println("You are computing $(Int64((p)*(p+1)/2 - p)) cross-spectra/coherences.")
  end

  # Compute the array of dpss vectors if they aren't given.
  if (dpVec == nothing) 
    dpVec   = dpss_tapers(lengt, NW, K)
    dpVec .*= sqrt(dt)
  end 
  
  # Get the spectra
  specs     = map(x->multispec(x, NW = NW, K = K, ctr = ctr, dt = dt, pad = pad, guts
                  = true, a_weight = a_weight,
                  jk = jk, alph = alph, dpVec = dpVec, Tsq = Tsq, Ftest = Ftest), 
                  (S1[:,k] for k=1:p))
 
  # Get the cross-spectra
  if (outp != :justspecs)
    crosspecs = (outp == :cross) ? Array{MtSpec,2}(undef, p, p) : 
                                  Array{MtCoh,2}(undef, p, p)
    for x in CartesianIndex.(filter(x -> x[2]>x[1], 
                             Tuple.(eachindex(view(crosspecs,1:p,1:p)))))
      crosspecs[x] = multispec(specs[x[1]].coef, specs[x[2]].coef, 
                               outp = ((outp == :cross) ? :spec : :coh), 
                               NW = NW, K = K, 
                               ctr = ctr, dt = dt, pad = pad, guts = false, 
                               jk = jk, alph = alph, dpVec = dpVec, Tsq = Tsq)
    end
  else
    crosspecs = nothing
  end

  # Compute the T^2- test if requested:
  dcs = (Tsq != nothing) ? map(isodd,1:K).*vec(sum(dpVec,dims=1)) : nothing
  # Do the Tsquared test
  if typeof(Tsq) != Nothing
    Tsq      = (typeof(Tsq) <: Vector{Number}) ? [Tsq] : Tsq
    map!(x -> freq_to_int(Tsq[x], lengt, dt), Tsq, eachindex(Tsq))
    Tsq = Vector{Vector{Int64}}(Tsq)  
    if (2*K < (true ? 1 : 2)*maximum(length.(Tsq)))
      error("There are too few tapers for the number of Tsq tests.")
    end
    Tv = zeros(length(Tsq)) 
    for x = eachindex(Tsq) 
        temp  = mapreduce(y -> y[Tsq[x],:], vcat, (specs[j].coef.coef for j = 1:p))
        Tv[x] = testTsq(dcs, Ecoef(temp,nothing))
    end
  else
    Tv = nothing
  end

  return (specs, crosspecs, Tv)
end


