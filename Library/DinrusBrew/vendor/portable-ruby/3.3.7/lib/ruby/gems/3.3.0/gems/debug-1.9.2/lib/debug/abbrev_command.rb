
module DEBUGGER__
  class AbbrevCommand
    class TrieNode
      def initialize
        @children = {}
        @types = {} # set
      end

      def append c, type
        trie = (@children[c] ||= TrieNode.new)
        trie.add_type type
      end

      def [](c)
        @children[c]
      end

      def add_type type
        @types[type] = true
        self
      end

      def types
        @types.keys
      end

      def type
        if @types.size == 1
          @types.keys.first
        else
          nil
        end
      end

      def candidates
        @children.map{|c, n|
          ss = n.candidates
          ss.empty? ? c :
          ss.map{|s|
            c+s
          }
        }.flatten
      end
    end

    # config: { type: [commands...], ... }
    def initialize config
      @trie = TrieNode.new
      build config
    end

    private def build config
      config.each do |type, commands|
        commands.each do |command|
          trie = @trie
          command.each_char do |c|
            trie = trie.append(c, type)
          end
        end
      end
    end

    def search str, if_none = nil
      trie = @trie
      str.each_char do |c|
        if trie = trie[c]
          return trie.type if trie.type
        else
          return if_none
        end
      end
      yield trie.candidates.map{|s| str + s} if block_given?
      if_none
    end
  end
end
