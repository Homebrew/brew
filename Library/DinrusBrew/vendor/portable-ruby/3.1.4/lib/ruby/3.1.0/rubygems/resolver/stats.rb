# frozen_string_literal: true
class Gem::Resolver::Stats
  def initialize
    @max_depth = 0
    @max_requirements = 0
    @requirements = 0
    @backtracking = 0
    @iterations = 0
  end

  def record_depth(stack)
    if stack.size > @max_depth
      @max_depth = stack.size
    end
  end

  def record_requirements(reqs)
    if reqs.size > @max_requirements
      @max_requirements = reqs.size
    end
  end

  def requirement!
    @requirements += 1
  end

  def backtracking!
    @backtracking += 1
  end

  def iteration!
    @iterations += 1
  end

  PATTERN = "%20s: %d\n".freeze

  def display
    $stdout.puts "=== Resolver Statistics ==="
    $stdout.printf PATTERN, "Max Depth", @max_depth
    $stdout.printf PATTERN, "Total Requirements", @requirements
    $stdout.printf PATTERN, "Max Requirements", @max_requirements
    $stdout.printf PATTERN, "Backtracking #", @backtracking
    $stdout.printf PATTERN, "Iteration #", @iterations
  end
end
