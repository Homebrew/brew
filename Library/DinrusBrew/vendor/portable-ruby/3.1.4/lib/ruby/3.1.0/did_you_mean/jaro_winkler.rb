module DidYouMean
  module Jaro
    module_function

    def distance(str1, str2)
      str1, str2 = str2, str1 if str1.length > str2.length
      length1, length2 = str1.length, str2.length

      m          = 0.0
      t          = 0.0
      range      = (length2 / 2).floor - 1
      range      = 0 if range < 0
      flags1     = 0
      flags2     = 0

      # Avoid duplicating enumerable objects
      str1_codepoints = str1.codepoints
      str2_codepoints = str2.codepoints

      i = 0
      while i < length1
        last = i + range
        j    = (i >= range) ? i - range : 0

        while j <= last
          if flags2[j] == 0 && str1_codepoints[i] == str2_codepoints[j]
            flags2 |= (1 << j)
            flags1 |= (1 << i)
            m += 1
            break
          end

          j += 1
        end

        i += 1
      end

      k = i = 0
      while i < length1
        if flags1[i] != 0
          j = index = k

          k = while j < length2
            index = j
            break(j + 1) if flags2[j] != 0

            j += 1
          end

          t += 1 if str1_codepoints[i] != str2_codepoints[index]
        end

        i += 1
      end
      t = (t / 2).floor

      m == 0 ? 0 : (m / length1 + m / length2 + (m - t) / m) / 3
    end
  end

  module JaroWinkler
    WEIGHT    = 0.1
    THRESHOLD = 0.7

    module_function

    def distance(str1, str2)
      jaro_distance = Jaro.distance(str1, str2)

      if jaro_distance > THRESHOLD
        codepoints2  = str2.codepoints
        prefix_bonus = 0

        i = 0
        str1.each_codepoint do |char1|
          char1 == codepoints2[i] && i < 4 ? prefix_bonus += 1 : break
          i += 1
        end

        jaro_distance + (prefix_bonus * WEIGHT * (1 - jaro_distance))
      else
        jaro_distance
      end
    end
  end
end
