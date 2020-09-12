
fn  = "../Examples/data/soirecruitment.dat"
dat = readdlm(fn)

# Spectrum tests
NW = 4.0
K  = 6
dt = 1.0/12
multiv = multispec(dat[:, 3:4], dt = dt, NW = NW, K = K, jk = true, Ftest = true,
                    guts = true, pad = 2.0)

@testset "Multivariate tests: Cross-spectrum, Coherency, Cross-covariance" begin  
  
  println("Testing multivariate frequency")
  @test multiv[1][1].f[1:5]         == 12*LinRange(0, 1, 454 + 453)[1:5]

  println("Testing multivariate MT coherence")
  @test multiv[1][1].S[1:5]         ≈ [0.05776450047987208, 0.0510836499696889,
                               0.053947076576308435,
                               0.03960810660934419, 0.03238905443102084]

  println("Testing multivariate MT phase")
  @test multiv[1][2].phase          == nothing 

  println("Testing multivariate parameters")
  @test multiv[1][2].params.M       == 906

  println("Testing multivariate eigencoefficients")
  @test multiv[1][1].coef.coef[1:2] ≈ [0.0763450617941093 + 0.0im,
                              -0.018461837449426248 - 0.07253045824096403im]

  println("Testing multivariate F-test")
  @test multiv[1][1].Fpval[1:5]     ≈ [0.9999999498486979, 0.3106832963307704,
                              0.46150154664925935, 
                              0.7590806611936394, 0.023822662121927296]

  println("Testing multivariate jackknife")
  @test multiv[1][1].jkvar[1:5]     ≈ [0.48594970945868243, 0.48941505597497825, 
                                       0.23173477815035817, 
                                       0.2766449068431087, 0.16729659627580204] 

  # Currently not testing this functionality
  println("Testing multivariate T-squared test")
  @test multiv[1][1].Tsq_pval       == nothing

  println("Testing the coherency")
  @test multiv[2][1,2].coh[1:5]     ≈ [7.046455236530036, 6.697940886784345, 
                                       6.226973678450996, 
                                       5.18871118000256, 5.082716554324644]

  println("Testing the phase")
  @test multiv[2][1,2].phase[1:5]   ≈ [180.0, 178.71279387445034, 178.30193928288293,
  177.60013658787375, 179.26526345068578]

  # Time-domain type tests
  println("Cross-covariance:")
  ccvf = mt_ccvf(dat[:,3], dat[:,4], NW = NW, K = K, dt = dt, pad = 2.0)

  println("Testing multivariate ccvf")
  @test collect(ccvf.lags[1:3])     ≈ [0.0, 0.013245033112582781, 0.026490066225165563]
  @test ccvf.ccvf[1:5]              ≈ [5.229250073634581, 4.722595266526602, 4.938340417516514, 
                                      3.503387684516827, 2.900003495964591]
  @test ccvf.params.K               == K

end
