# typed: strict
# frozen_string_literal: true

module Homebrew
  # Parses and normalizes Git commit messages into subject, body and trailers.
  class CommitMessage
    TRAILER_PATTERN = T.let(
      /^(
        [a-z][\w-]*-by
        |Closes
        |Fixes
        |Resolves
        |Reviewed-on
        |Change-Id
        |Acked-by
        |Tested-by
        |Reported-by
        |Cc
        |Suggested-by
        |Ref
        |See-also
        |Bug
        |Issue
      )\s*[:#]/ix,
      Regexp,
    )

    sig { returns(String) }
    attr_reader :subject, :body, :trailers

    sig { params(subject: String, body: String, trailers: String).void }
    def initialize(subject: "", body: "", trailers: "")
      @subject = T.let(subject, String)
      @body = T.let(body, String)
      @trailers = T.let(trailers, String)
    end

    sig { params(message: String).returns(CommitMessage) }
    def self.parse(message)
      first_line = message.lines.first
      return new unless first_line

      trailer_lines, body_lines = message.lines.drop(1).partition { |s| s.match?(TRAILER_PATTERN) }

      new(
        subject:  first_line.strip,
        body:     body_lines.join.strip.gsub(/\n{3,}/, "\n\n"),
        trailers: trailer_lines.uniq.join.strip,
      )
    end

    sig { returns(CommitMessage) }
    def normalize
      normalized_subject = subject.rstrip

      normalized_body = body
                        .lines
                        .map(&:rstrip)
                        .join("\n")
                        .gsub(/\n{3,}/, "\n\n")
                        .strip

      normalized_trailers = trailers
                            .lines
                            .map(&:rstrip)
                            .join("\n")
                            .strip

      self.class.new(
        subject:  normalized_subject,
        body:     normalized_body,
        trailers: normalized_trailers,
      )
    end

    sig { returns(String) }
    def to_s
      parts = [subject]
      parts << "\n\n#{body}" unless body.empty?
      parts << "\n\n#{trailers}" unless trailers.empty?
      parts.join
    end
  end
end
