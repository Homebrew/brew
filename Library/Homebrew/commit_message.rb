# typed: strict
# frozen_string_literal: true

module Homebrew
  class CommitMessage
    TRAILER_PATTERN = /^[A-Za-z][A-Za-z0-9-]*:\s/

    sig { returns(String) }
    attr_reader :subject

    sig { returns(String) }
    attr_reader :body

    sig { returns(String) }
    attr_reader :trailers

    sig { params(message: String).void }
    def initialize(message)
      parsed = parse(message)
      @subject = T.let(parsed[0], String)
      @body = T.let(parsed[1], String)
      @trailers = T.let(parsed[2], String)
    end

    sig { returns(String) }
    def to_s
      parts = [subject]
      parts << "\n\n#{body}" unless body.empty?
      parts << "\n\n#{trailers}" unless trailers.empty?
      parts.join
    end

    sig { returns(CommitMessage) }
    def normalize
      normalized_subject = subject.strip
      normalized_body = normalize_text(body)
      normalized_trailers = trailers.lines.map(&:strip).reject(&:empty?).uniq.join("\n")

      normalized = [normalized_subject]
      normalized << "\n\n#{normalized_body}" unless normalized_body.empty?
      normalized << "\n\n#{normalized_trailers}" unless normalized_trailers.empty?
      CommitMessage.new(normalized.join)
    end

    sig { params(message: String).returns([String, String, String]) }
    def self.parse(message)
      new(message).then { |cm| [cm.subject, cm.body, cm.trailers] }
    end

    private

    sig { params(message: String).returns([String, String, String]) }
    def parse(message)
      first_line = message.lines.first
      return ["", "", ""] unless first_line

      remaining = message.lines.drop(1)

      # Detect trailers as a contiguous block at the end of the message.
      # Walk backwards from the end: trailer lines match TRAILER_PATTERN,
      # blank lines between trailers are allowed.
      trailer_start = remaining.length
      remaining.reverse_each.with_index do |line, i|
        pos = remaining.length - 1 - i
        if line.match?(TRAILER_PATTERN)
          trailer_start = pos
        elsif line.strip.empty?
          next
        else
          break
        end
      end

      body = remaining[0...trailer_start].to_a.join.strip.gsub(/\n{3,}/, "\n\n")
      trailer_lines = remaining[trailer_start..].to_a.grep(TRAILER_PATTERN).uniq.join.strip

      [first_line.strip, body, trailer_lines]
    end

    sig { params(text: String).returns(String) }
    def normalize_text(text)
      text
        .lines
        .map { |line| line.rstrip.concat("\n") }
        .join
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end
  end
end
