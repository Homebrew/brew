module Test
  module Unit
    class CodeSnippetFetcher
      def initialize
        @sources = {}
      end

      def fetch(path, line, options={})
        n_context_line = options[:n_context_line] || 3
        lines = source(path)
        return [] if lines.nil?
        min_line = [line - n_context_line, 1].max
        max_line = [line + n_context_line, lines.length].min
        window = min_line..max_line
        window.collect do |n|
          attributes = {:target_line? => (n == line)}
          [n, lines[n - 1].chomp, attributes]
        end
      end

      def source(path)
        @sources[path] ||= read_source(path)
      end

      private
      def read_source(path)
        return nil unless File.exist?(path)
        lines = []
        File.open(path, "rb") do |file|
          first_line = file.gets
          break if first_line.nil?
          encoding = detect_encoding(first_line) || Encoding::UTF_8
          first_line.force_encoding(encoding)
          lines << first_line
          file.each_line do |line|
            line.force_encoding(encoding)
            lines << line
          end
        end
        lines
      end

      def detect_encoding(first_line)
        return nil unless first_line.respond_to?(:ascii_only?)
        return nil unless first_line.ascii_only?
        if /\b(?:en)?coding[:=]\s*([a-z\d_-]+)/i =~ first_line
          begin
            Encoding.find($1)
          rescue ArgumentError
            nil
          end
        else
          nil
        end
      end
    end
  end
end
