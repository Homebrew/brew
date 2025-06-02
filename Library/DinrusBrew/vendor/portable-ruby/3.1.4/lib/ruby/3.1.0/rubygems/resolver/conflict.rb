# frozen_string_literal: true
##
# Used internally to indicate that a dependency conflicted
# with a spec that would be activated.

class Gem::Resolver::Conflict
  ##
  # The specification that was activated prior to the conflict

  attr_reader :activated

  ##
  # The dependency that is in conflict with the activated gem.

  attr_reader :dependency

  attr_reader :failed_dep # :nodoc:

  ##
  # Creates a new resolver conflict when +dependency+ is in conflict with an
  # already +activated+ specification.

  def initialize(dependency, activated, failed_dep=dependency)
    @dependency = dependency
    @activated = activated
    @failed_dep = failed_dep
  end

  def ==(other) # :nodoc:
    self.class === other &&
      @dependency == other.dependency &&
      @activated  == other.activated  &&
      @failed_dep == other.failed_dep
  end

  ##
  # A string explanation of the conflict.

  def explain
    "<Conflict wanted: #{@failed_dep}, had: #{activated.spec.full_name}>"
  end

  ##
  # Return the 2 dependency objects that conflicted

  def conflicting_dependencies
    [@failed_dep.dependency, @activated.request.dependency]
  end

  ##
  # Explanation of the conflict used by exceptions to print useful messages

  def explanation
    activated   = @activated.spec.full_name
    dependency  = @failed_dep.dependency
    requirement = dependency.requirement
    alternates  = dependency.matching_specs.map {|spec| spec.full_name }

    unless alternates.empty?
      matching = <<-MATCHING.chomp

  Gems matching %s:
    %s
      MATCHING

      matching = matching % [
        dependency,
        alternates.join(", "),
      ]
    end

    explanation = <<-EXPLANATION
  Activated %s
  which does not match conflicting dependency (%s)

  Conflicting dependency chains:
    %s

  versus:
    %s
%s
    EXPLANATION

    explanation % [
      activated, requirement,
      request_path(@activated).reverse.join(", depends on\n    "),
      request_path(@failed_dep).reverse.join(", depends on\n    "),
      matching
    ]
  end

  ##
  # Returns true if the conflicting dependency's name matches +spec+.

  def for_spec?(spec)
    @dependency.name == spec.name
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[Dependency conflict: ", "]" do
      q.breakable

      q.text "activated "
      q.pp @activated

      q.breakable
      q.text " dependency "
      q.pp @dependency

      q.breakable
      if @dependency == @failed_dep
        q.text " failed"
      else
        q.text " failed dependency "
        q.pp @failed_dep
      end
    end
  end

  ##
  # Path of activations from the +current+ list.

  def request_path(current)
    path = []

    while current do
      case current
      when Gem::Resolver::ActivationRequest then
        path <<
          "#{current.request.dependency}, #{current.spec.version} activated"

        current = current.parent
      when Gem::Resolver::DependencyRequest then
        path << "#{current.dependency}"

        current = current.requester
      else
        raise Gem::Exception, "[BUG] unknown request class #{current.class}"
      end
    end

    path = ["user request (gem command or Gemfile)"] if path.empty?

    path
  end

  ##
  # Return the Specification that listed the dependency

  def requester
    @failed_dep.requester
  end
end
