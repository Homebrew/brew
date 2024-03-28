# frozen_string_literal: false
require "bigdecimal/ludcmp"
require "bigdecimal/jacobian"

#
# newton.rb
#
# Solves the nonlinear algebraic equation system f = 0 by Newton's method.
# This program is not dependent on BigDecimal.
#
# To call:
#    n = nlsolve(f,x)
#  where n is the number of iterations required,
#        x is the initial value vector
#        f is an Object which is used to compute the values of the equations to be solved.
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
# On exit, x is the solution vector.
#
module Newton
  include LUSolve
  include Jacobian
  module_function

  def norm(fv,zero=0.0) # :nodoc:
    s = zero
    n = fv.size
    for i in 0...n do
      s += fv[i]*fv[i]
    end
    s
  end

  # See also Newton
  def nlsolve(f,x)
    nRetry = 0
    n = x.size

    f0 = f.values(x)
    zero = f.zero
    one  = f.one
    two  = f.two
    p5 = one/two
    d  = norm(f0,zero)
    minfact = f.ten*f.ten*f.ten
    minfact = one/minfact
    e = f.eps
    while d >= e do
      nRetry += 1
      # Not yet converged. => Compute Jacobian matrix
      dfdx = jacobian(f,f0,x)
      # Solve dfdx*dx = -f0 to estimate dx
      dx = lusolve(dfdx,f0,ludecomp(dfdx,n,zero,one),zero)
      fact = two
      xs = x.dup
      begin
        fact *= p5
        if fact < minfact then
          raise "Failed to reduce function values."
        end
        for i in 0...n do
          x[i] = xs[i] - dx[i]*fact
        end
        f0 = f.values(x)
        dn = norm(f0,zero)
      end while(dn>=d)
      d = dn
    end
    nRetry
  end
end
