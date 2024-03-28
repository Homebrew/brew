# frozen_string_literal: false
require 'bigdecimal'

#
# Solves a*x = b for x, using LU decomposition.
#
module LUSolve
  module_function

  # Performs LU decomposition of the n by n matrix a.
  def ludecomp(a,n,zero=0,one=1)
    prec = BigDecimal.limit(nil)
    ps     = []
    scales = []
    for i in 0...n do  # pick up largest(abs. val.) element in each row.
      ps <<= i
      nrmrow  = zero
      ixn = i*n
      for j in 0...n do
        biggst = a[ixn+j].abs
        nrmrow = biggst if biggst>nrmrow
      end
      if nrmrow>zero then
        scales <<= one.div(nrmrow,prec)
      else
        raise "Singular matrix"
      end
    end
    n1          = n - 1
    for k in 0...n1 do # Gaussian elimination with partial pivoting.
      biggst  = zero;
      for i in k...n do
        size = a[ps[i]*n+k].abs*scales[ps[i]]
        if size>biggst then
          biggst = size
          pividx  = i
        end
      end
      raise "Singular matrix" if biggst<=zero
      if pividx!=k then
        j = ps[k]
        ps[k] = ps[pividx]
        ps[pividx] = j
      end
      pivot   = a[ps[k]*n+k]
      for i in (k+1)...n do
        psin = ps[i]*n
        a[psin+k] = mult = a[psin+k].div(pivot,prec)
        if mult!=zero then
          pskn = ps[k]*n
          for j in (k+1)...n do
            a[psin+j] -= mult.mult(a[pskn+j],prec)
          end
        end
      end
    end
    raise "Singular matrix" if a[ps[n1]*n+n1] == zero
    ps
  end

  # Solves a*x = b for x, using LU decomposition.
  #
  # a is a matrix, b is a constant vector, x is the solution vector.
  #
  # ps is the pivot, a vector which indicates the permutation of rows performed
  # during LU decomposition.
  def lusolve(a,b,ps,zero=0.0)
    prec = BigDecimal.limit(nil)
    n = ps.size
    x = []
    for i in 0...n do
      dot = zero
      psin = ps[i]*n
      for j in 0...i do
        dot = a[psin+j].mult(x[j],prec) + dot
      end
      x <<= b[ps[i]] - dot
    end
    (n-1).downto(0) do |i|
      dot = zero
      psin = ps[i]*n
      for j in (i+1)...n do
        dot = a[psin+j].mult(x[j],prec) + dot
      end
      x[i]  = (x[i]-dot).div(a[psin+i],prec)
    end
    x
  end
end
