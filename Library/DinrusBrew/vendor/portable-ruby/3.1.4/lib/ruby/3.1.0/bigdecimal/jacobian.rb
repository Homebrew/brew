# frozen_string_literal: false

require 'bigdecimal'

# require 'bigdecimal/jacobian'
#
# Provides methods to compute the Jacobian matrix of a set of equations at a
# point x. In the methods below:
#
# f is an Object which is used to compute the Jacobian matrix of the equations.
# It must provide the following methods:
#
# f.values(x):: returns the values of all functions at x
#
# f.zero:: returns 0.0
# f.one:: returns 1.0
# f.two:: returns 2.0
# f.ten:: returns 10.0
#
# f.eps:: returns the convergence criterion (epsilon value) used to determine whether two values are considered equal. If |a-b| < epsilon, the two values are considered equal.
#
# x is the point at which to compute the Jacobian.
#
# fx is f.values(x).
#
module Jacobian
  module_function

  # Determines the equality of two numbers by comparing to zero, or using the epsilon value
  def isEqual(a,b,zero=0.0,e=1.0e-8)
    aa = a.abs
    bb = b.abs
    if aa == zero &&  bb == zero then
      true
    else
      if ((a-b)/(aa+bb)).abs < e then
        true
      else
        false
      end
    end
  end


  # Computes the derivative of f[i] at x[i].
  # fx is the value of f at x.
  def dfdxi(f,fx,x,i)
    nRetry = 0
    n = x.size
    xSave = x[i]
    ok = 0
    ratio = f.ten*f.ten*f.ten
    dx = x[i].abs/ratio
    dx = fx[i].abs/ratio if isEqual(dx,f.zero,f.zero,f.eps)
    dx = f.one/f.ten     if isEqual(dx,f.zero,f.zero,f.eps)
    until ok>0 do
      deriv = []
      nRetry += 1
      if nRetry > 100
        raise "Singular Jacobian matrix. No change at x[" + i.to_s + "]"
      end
      dx = dx*f.two
      x[i] += dx
      fxNew = f.values(x)
      for j in 0...n do
        if !isEqual(fxNew[j],fx[j],f.zero,f.eps) then
          ok += 1
          deriv <<= (fxNew[j]-fx[j])/dx
        else
          deriv <<= f.zero
        end
      end
      x[i] = xSave
    end
    deriv
  end

  # Computes the Jacobian of f at x. fx is the value of f at x.
  def jacobian(f,fx,x)
    n = x.size
    dfdx = Array.new(n*n)
    for i in 0...n do
      df = dfdxi(f,fx,x,i)
      for j in 0...n do
        dfdx[j*n+i] = df[j]
      end
    end
    dfdx
  end
end
