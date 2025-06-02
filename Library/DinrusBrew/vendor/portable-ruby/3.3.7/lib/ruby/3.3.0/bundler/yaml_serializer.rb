# frozen_string_literal: true

module Bundler
  # A stub yaml serializer that can handle only hashes and strings (as of now).
  module YAMLSerializer
    module_function

    def dump(hash)
      yaml = String.new("---")
      yaml << dump_hash(hash)
    end

    def dump_hash(hash)
      yaml = String.new("\n")
      hash.each do |k, v|
        yaml << k << ":"
        if v.is_a?(Hash)
          yaml << dump_hash(v).gsub(/^(?!$)/, "  ") # indent all non-empty lines
        elsif v.is_a?(Array) # Expected to be array of strings
          if v.empty?
            yaml << " []\n"
          else
            yaml << "\n- " << v.map {|s| s.to_s.gsub(/\s+/, " ").inspect }.join("\n- ") << "\n"
          end
        else
          yaml << " " << v.to_s.gsub(/\s+/, " ").inspect << "\n"
        end
      end
      yaml
    end

    ARRAY_REGEX = /
      ^
      (?:[ ]*-[ ]) # '- ' before array items
      (['"]?) # optional opening quote
      (.*) # value
      \1 # matching closing quote
      $
    /xo

    HASH_REGEX = /
      ^
      ([ ]*) # indentations
      ([^#]+) # key excludes comment char '#'
      (?::(?=(?:\s|$))) # :  (without the lookahead the #key includes this when : is present in value)
      [ ]?
      (['"]?) # optional opening quote
      (.*) # value
      \3 # matching closing quote
      $
    /xo

    def load(str)
      res = {}
      stack = [res]
      last_hash = nil
      last_empty_key = nil
      str.split(/\r?\n/) do |line|
        if match = HASH_REGEX.match(line)
          indent, key, quote, val = match.captures
          val = strip_comment(val)

          depth = indent.size / 2
          if quote.empty? && val.empty?
            new_hash = {}
            stack[depth][key] = new_hash
            stack[depth + 1] = new_hash
            last_empty_key = key
            last_hash = stack[depth]
          else
            val = [] if val == "[]" # empty array
            stack[depth][key] = val
          end
        elsif match = ARRAY_REGEX.match(line)
          _, val = match.captures
          val = strip_comment(val)

          last_hash[last_empty_key] = [] unless last_hash[last_empty_key].is_a?(Array)

          last_hash[last_empty_key].push(val)
        end
      end
      res
    end

    def strip_comment(val)
      if val.include?("#") && !val.start_with?("#")
        val.split("#", 2).first.strip
      else
        val
      end
    end

    class << self
      private :dump_hash
    end
  end
end
