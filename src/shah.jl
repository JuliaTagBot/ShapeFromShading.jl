@doc raw"""
```
Z,p,q = retrieve_surface(algorithm::Shah, img::AbstractArray, iterations::Int=200)
```
Attempts to produce a hieghtmap from a grayscale image using Shah's algorithm.

Under the assumption that the albedo is constant, and the surface is Lambertian,
the algorithm employs discrete approximations of p and q using finite
differences in order to linearize the reflectance map in terms of Z by taking
the first term of its Taylor series expansion.
# Output
Returns an M by N array (matching dimensions of original image) of Float `Z`
that represents the reconstructed height at the point and the gradients in
M by N arrays of Float 'p' and 'q'.
# Details
Given the reflectance map for the surface defined as bellow:
```math
R(x,y)=\dfrac{-i_xp-i_yq+i_z}{\sqrt{1+p^2+q^2}}=\dfrac{\cos\sigma+p\cos\tau\sin
\sigma+q\sin\tau\sin\sigma}{\sqrt{1+p^2+q^2}}
```
where ``i_x=\frac{I(1)}{I(3)}=\frac{\cos\tau\sin\sigma}{\cos\sigma}=\cos\tau
\tan\sigma`` and ``i_y=\frac{I(2)}{I(3)}=\frac{\sin\tau\sin\sigma}{\cos\sigma}
=\sin\tau\tan\sigma``.

and p and q are discretely approximated as:
```math
\begin{gathered}
p=Z(x,y)-Z(x-1,y)\\
q=Z(x,y)-Z(x,y-1)\\
\end{gathered}
```

Shah linearized the function ``f=E-R=0`` in terms of ``Z`` in the vicinity of
``Z^{k-1}`` by crating a system of linear equations which can be solved iteratively
using the Jacobi iterative scheme, simplifying the Taylor series expansion to the
first order to get the following:
```math
f(Z(x,y))=0\approx f(Z^{n-1}(x,y))+(Z(x,y)-Z^{n-1}(x,y))\dfrac{df(Z^{n-1}(x,y))}
{dZ(x,y)}
```
which by letting ``Z^n(x,y)=Z(x,y)`` gives:
```math
Z^n(x,y=Z^{n-1}(x,y)-\dfrac{f(Z^{n-1}(x,y))}{\dfrac{df(Z^{n-1}(x,y))}{dZ(x,y)}}
```
where,
```math
\dfrac{df(Z^{n-1}(x,y))}{dZ(x,y)}=\dfrac{(p+q)(pi_x+qi_y+1)}{\sqrt{(1+p^2+q^2)^3}
\sqrt{1+i_x+i_y}}-\dfrac{i_x+i_y}{\sqrt{1+p^2+q^2}\sqrt{1+i_x+i_y}}
```
which as ``Z^0(x,y)=0``, allows the algorithm to iteratively solve for ``Z(x,y)``.

The `slant` and `tilt` can be manually defined using the function signature:
```
Z,p,q = retrieve_surface(algorithm::Shah, img::AbstractArray, slant::Real, tilt::Real, iterations::Int=200)
```
# Arguments
The function arguments are described in more detail below.
##  `img`
An `AbstractArray` storing the grayscale value of each pixel within
the range [0,1].
## `iterations`
An `Int` that specifies the number of iterations the algorithm is to perform. If
left unspecified a default value of 200 is used.
## `slant`
A `Real` that specifies the slant value to be used by the algorithm. The `slant`
should be a value in the range [0,π/2]. If `slant` is specified to must the `tilt`.
## `tilt`
A `Real` that specifies the tilt value to be used by the algorithm. The `tilt`
should be a value in the range [0,2π]. If `tilt` is specified to must
the `slant`.
# Example
Compute the heightmap for a synthetic image generated by `generate_surface`.
```julia
using Images, Makie, ShapeFromShading

#generate synthetic image
img = generate_surface(SynthSphere(), 1, [0.2,0,0.9], radius = 5)

#calculate the heightmap
Z,p,q = retrieve_surface(Shah(), img)

#normalize to maximum of 1 (not necessary but makes displaying easier)
Z = Z./maximum(Z)

#display using Makie (Note: Makie can often take several minutes first time)
r = 0.0:0.1:2
surface(r, r, Z)
```
# Reference
1. T. Ping-Sing and M. Shah, "Shape from shading using linear approximation", Image and Vision Computing, vol. 12, no. 8, pp. 487-498, 1994. [doi:10.1016/0262-8856(94)90002-7](https://doi.org/10.1016/0262-8856(94)90002-7)
"""
function retrieve_surface(algorithm::Shah, img::AbstractArray, iterations::Int=200)
    ρ,I,σ,τ = estimate_img_properties(img)
    return retrieve_surface(Shah(), img, σ, τ, iterations)
end

function retrieve_surface(algorithm::Shah, img::AbstractArray, slant::Real, tilt::Real, iterations::Int=200)
    σ, τ = slant,tilt
    E = Float64.(img)
    E = E .* 255
    M, N = size(E)
    p = zeros(axes(E))
    q = zeros(axes(E))
    Z = zeros(axes(E))
    Zx = zeros(axes(E))
    Zy = zeros(axes(E))
    ix = cos(τ) * tan(σ)
    iy = sin(τ) * tan(σ)
    R = zeros(axes(E))
    δfδZ = zeros(axes(E))
    f = zeros(axes(E))
    @inbounds for i = 1:iterations
        #calculate reflectance map
        for i in CartesianIndices(R)
            R[i] = (cos(σ) + p[i] * cos(τ) * sin(σ) + q[i] * sin(τ) * sin(σ)) /
                sqrt(1 + p[i]^2 + q[i]^2)

            R[i] = max(0, R[i])
            f[i] = E[i] - R[i]
        end

        #calculate derivative of f in respect to Z and update Z
        for i in CartesianIndices(δfδZ)
            δfδZ[i] = (p[i] + q[i]) * (ix * p[i] + iy * q[i] + 1) / (sqrt((1
                + p[i]^2 + q[i]^2)^3) * sqrt(1 + ix^2 + iy^2)) - (ix + iy) /
                (sqrt(1 .+ p[i]^2 + q[i]^2) * sqrt(1 + ix^2 + iy^2))

            Z[i] = Z[i] - f[i] / (δfδZ[i] + eps())
        end

        #update surface normals
        for i = 2:M
            for j = 1:N
                Zx[i,j] = Z[i-1,j]
            end
        end
        for i = 2:N
            for j = 1:M
                Zy[j,i] = Z[j,i-1]
            end
        end
        for i in CartesianIndices(p)
            p[i] = Z[i] - Zx[i]
            q[i] = Z[i] - Zy[i]
        end
    end

    #smooth Z using a 21X21 median filter of the absolute values
    for i in CartesianIndices(Z)
        Z[i] = abs(Z[i])
    end
    Z = mapwindow(median!, Z, (21,21))
    return Z, p, q
end
