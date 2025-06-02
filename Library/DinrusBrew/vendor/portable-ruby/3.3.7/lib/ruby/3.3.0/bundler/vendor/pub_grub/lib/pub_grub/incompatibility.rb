module Bundler::PubGrub
  class Incompatibility
    ConflictCause = Struct.new(:incompatibility, :satisfier) do
      alias_method :conflict, :incompatibility
      alias_method :other, :satisfier
    end

    InvalidDependency = Struct.new(:package, :constraint) do
    end

    NoVersions = Struct.new(:constraint) do
    end

    attr_reader :terms, :cause

    def initialize(terms, cause:, custom_explanation: nil)
      @cause = cause
      @terms = cleanup_terms(terms)
      @custom_explanation = custom_explanation

      if cause == :dependency && @terms.length != 2
        raise ArgumentError, "a dependency Incompatibility must have exactly two terms. Got #{@terms.inspect}"
      end
    end

    def hash
      cause.hash ^ terms.hash
    end

    def eql?(other)
      cause.eql?(other.cause) &&
        terms.eql?(other.terms)
    end

    def failure?
      terms.empty? || (terms.length == 1 && Package.root?(terms[0].package) && terms[0].positive?)
    end

    def conflict?
      ConflictCause === cause
    end

    # Returns all external incompatibilities in this incompatibility's
    # derivation graph
    def external_incompatibilities
      if conflict?
        [
          cause.conflict,
          cause.other
        ].flat_map(&:external_incompatibilities)
      else
        [this]
      end
    end

    def to_s
      return @custom_explanation if @custom_explanation

      case cause
      when :root
        "(root dependency)"
      when :dependency
        "#{terms[0].to_s(allow_every: true)} depends on #{terms[1].invert}"
      when Bundler::PubGrub::Incompatibility::InvalidDependency
        "#{terms[0].to_s(allow_every: true)} depends on unknown package #{cause.package}"
      when Bundler::PubGrub::Incompatibility::NoVersions
        "no versions satisfy #{cause.constraint}"
      when Bundler::PubGrub::Incompatibility::ConflictCause
        if failure?
          "version solving has failed"
        elsif terms.length == 1
          term = terms[0]
          if term.positive?
            if term.constraint.any?
              "#{term.package} cannot be used"
            else
              "#{term.to_s(allow_every: true)} cannot be used"
            end
          else
            "#{term.invert} is required"
          end
        else
          if terms.all?(&:positive?)
            if terms.length == 2
              "#{terms[0].to_s(allow_every: true)} is incompatible with #{terms[1]}"
            else
              "one of #{terms.map(&:to_s).join(" or ")} must be false"
            end
          elsif terms.all?(&:negative?)
            if terms.length == 2
              "either #{terms[0].invert} or #{terms[1].invert}"
            else
              "one of #{terms.map(&:invert).join(" or ")} must be true";
            end
          else
            positive = terms.select(&:positive?)
            negative = terms.select(&:negative?).map(&:invert)

            if positive.length == 1
              "#{positive[0].to_s(allow_every: true)} requires #{negative.join(" or ")}"
            else
              "if #{positive.join(" and ")} then #{negative.join(" or ")}"
            end
          end
        end
      else
        raise "unhandled cause: #{cause.inspect}"
      end
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end

    def pretty_print(q)
      q.group 2, "#<#{self.class}", ">" do
        q.breakable
        q.text to_s

        q.breakable
        q.text " caused by "
        q.pp @cause
      end
    end

    private

    def cleanup_terms(terms)
      terms.each do |term|
        raise "#{term.inspect} must be a term" unless term.is_a?(Term)
      end

      if terms.length != 1 && ConflictCause === cause
        terms = terms.reject do |term|
          term.positive? && Package.root?(term.package)
        end
      end

      # Optimized simple cases
      return terms if terms.length <= 1
      return terms if terms.length == 2 && terms[0].package != terms[1].package

      terms.group_by(&:package).map do |package, common_terms|
        common_terms.inject do |acc, term|
          acc.intersect(term)
        end
      end
    end
  end
end
