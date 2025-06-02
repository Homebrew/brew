# frozen_string_literal: false
class Matrix
  # Adapted from JAMA: http://math.nist.gov/javanumerics/jama/

  #
  # For an m-by-n matrix A with m >= n, the LU decomposition is an m-by-n
  # unit lower triangular matrix L, an n-by-n upper triangular matrix U,
  # and a m-by-m permutation matrix P so that L*U = P*A.
  # If m < n, then L is m-by-m and U is m-by-n.
  #
  # The LUP decomposition with pivoting always exists, even if the matrix is
  # singular, so the constructor will never fail.  The primary use of the
  # LU decomposition is in the solution of square systems of simultaneous
  # linear equations.  This will fail if singular? returns true.
  #

  class LUPDecomposition
    # Returns the lower triangular factor +L+

    include Matrix::ConversionHelper

    def l
      Matrix.build(@row_count, [@column_count, @row_count].min) do |i, j|
        if (i > j)
          @lu[i][j]
        elsif (i == j)
          1
        else
          0
        end
      end
    end

    # Returns the upper triangular factor +U+

    def u
      Matrix.build([@column_count, @row_count].min, @column_count) do |i, j|
        if (i <= j)
          @lu[i][j]
        else
          0
        end
      end
    end

    # Returns the permutation matrix +P+

    def p
      rows = Array.new(@row_count){Array.new(@row_count, 0)}
      @pivots.each_with_index{|p, i| rows[i][p] = 1}
      Matrix.send :new, rows, @row_count
    end

    # Returns +L+, +U+, +P+ in an array

    def to_ary
      [l, u, p]
    end
    alias_method :to_a, :to_ary

    # Returns the pivoting indices

    attr_reader :pivots

    # Returns +true+ if +U+, and hence +A+, is singular.

    def singular?
      @column_count.times do |j|
        if (@lu[j][j] == 0)
          return true
        end
      end
      false
    end

    # Returns the determinant of +A+, calculated efficiently
    # from the factorization.

    def det
      if (@row_count != @column_count)
        raise Matrix::ErrDimensionMismatch
      end
      d = @pivot_sign
      @column_count.times do |j|
        d *= @lu[j][j]
      end
      d
    end
    alias_method :determinant, :det

    # Returns +m+ so that <tt>A*m = b</tt>,
    # or equivalently so that <tt>L*U*m = P*b</tt>
    # +b+ can be a Matrix or a Vector

    def solve b
      if (singular?)
        raise Matrix::ErrNotRegular, "Matrix is singular."
      end
      if b.is_a? Matrix
        if (b.row_count != @row_count)
          raise Matrix::ErrDimensionMismatch
        end

        # Copy right hand side with pivoting
        nx = b.column_count
        m = @pivots.map{|row| b.row(row).to_a}

        # Solve L*Y = P*b
        @column_count.times do |k|
          (k+1).upto(@column_count-1) do |i|
            nx.times do |j|
              m[i][j] -= m[k][j]*@lu[i][k]
            end
          end
        end
        # Solve U*m = Y
        (@column_count-1).downto(0) do |k|
          nx.times do |j|
            m[k][j] = m[k][j].quo(@lu[k][k])
          end
          k.times do |i|
            nx.times do |j|
              m[i][j] -= m[k][j]*@lu[i][k]
            end
          end
        end
        Matrix.send :new, m, nx
      else # same algorithm, specialized for simpler case of a vector
        b = convert_to_array(b)
        if (b.size != @row_count)
          raise Matrix::ErrDimensionMismatch
        end

        # Copy right hand side with pivoting
        m = b.values_at(*@pivots)

        # Solve L*Y = P*b
        @column_count.times do |k|
          (k+1).upto(@column_count-1) do |i|
            m[i] -= m[k]*@lu[i][k]
          end
        end
        # Solve U*m = Y
        (@column_count-1).downto(0) do |k|
          m[k] = m[k].quo(@lu[k][k])
          k.times do |i|
            m[i] -= m[k]*@lu[i][k]
          end
        end
        Vector.elements(m, false)
      end
    end

    def initialize a
      raise TypeError, "Expected Matrix but got #{a.class}" unless a.is_a?(Matrix)
      # Use a "left-looking", dot-product, Crout/Doolittle algorithm.
      @lu = a.to_a
      @row_count = a.row_count
      @column_count = a.column_count
      @pivots = Array.new(@row_count)
      @row_count.times do |i|
         @pivots[i] = i
      end
      @pivot_sign = 1
      lu_col_j = Array.new(@row_count)

      # Outer loop.

      @column_count.times do |j|

        # Make a copy of the j-th column to localize references.

        @row_count.times do |i|
          lu_col_j[i] = @lu[i][j]
        end

        # Apply previous transformations.

        @row_count.times do |i|
          lu_row_i = @lu[i]

          # Most of the time is spent in the following dot product.

          kmax = [i, j].min
          s = 0
          kmax.times do |k|
            s += lu_row_i[k]*lu_col_j[k]
          end

          lu_row_i[j] = lu_col_j[i] -= s
        end

        # Find pivot and exchange if necessary.

        p = j
        (j+1).upto(@row_count-1) do |i|
          if (lu_col_j[i].abs > lu_col_j[p].abs)
            p = i
          end
        end
        if (p != j)
          @column_count.times do |k|
            t = @lu[p][k]; @lu[p][k] = @lu[j][k]; @lu[j][k] = t
          end
          k = @pivots[p]; @pivots[p] = @pivots[j]; @pivots[j] = k
          @pivot_sign = -@pivot_sign
        end

        # Compute multipliers.

        if (j < @row_count && @lu[j][j] != 0)
          (j+1).upto(@row_count-1) do |i|
            @lu[i][j] = @lu[i][j].quo(@lu[j][j])
          end
        end
      end
    end
  end
end
