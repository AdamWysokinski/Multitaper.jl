
# Multitaper.jl

[![Build Status](https://travis-ci.com/clhaley/multitaper.jl.svg?branch=master)](https://travis-ci.com/clhaley/multitaper.jl)
[![Coverage Status](https://coveralls.io/repos/bitbucket/clhaley/multitaper.jl/badge.svg?branch=master)](https://coveralls.io/bitbucket/clhaley/multitaper.jl?branch=master)

When doing exploratory analysis of time series, frequency domain methods, that is,
statistical methods that display information about the temporal correlations of one
or more time series in terms of frequencies, can be used to infer physical mechanisms
for underlying process dynamics in e.g. geophysical time series, medical time series,
etc.). The [multitaper method](https://en.wikipedia.org/wiki/Multitaper), which
leverages Slepian functions to estimate power spectral densities, coherences, and so
forth, is implemented here for application to univariate, multivariate, and
higher-dimensional (e.g. space-time) processes.

See documentation below. 

[![Development branch documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://clhaley.bitbucket.io/Multitaper.jl/)

## Installation

This package is unregistered, so please install with

```

Pkg> add https://bitbucket.org/clhaley/Multitaper.jl.git

```

This package runs on julia v 1.4.2 and above.

## Contributing

Contributions to Multitaper.jl can be done in the form of issues or pull requests. 
