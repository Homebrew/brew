# frozen_string_literal: false
module IRB
  class << (MagicFile = Object.new)
    # see parser_magic_comment in parse.y
    ENCODING_SPEC_RE = %r"coding\s*[=:]\s*([[:alnum:]\-_]+)"

    def open(path)
      io = File.open(path, 'rb')
      line = io.gets
      line = io.gets if line[0,2] == "#!"
      encoding = detect_encoding(line)
      internal_encoding = encoding
      encoding ||= IRB.default_src_encoding
      io.rewind
      io.set_encoding(encoding, internal_encoding)

      if block_given?
        begin
          return (yield io)
        ensure
          io.close
        end
      else
        return io
      end
    end

    private
    def detect_encoding(line)
      return unless line[0] == ?#
      line = line[1..-1]
      line = $1 if line[/-\*-\s*(.*?)\s*-*-$/]
      return nil unless ENCODING_SPEC_RE =~ line
      encoding = $1
      return encoding.sub(/-(?:mac|dos|unix)/i, '')
    end
  end
end
