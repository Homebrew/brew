require_relative 'assignment'

module Bundler::PubGrub
  class PartialSolution
    attr_reader :assignments, :decisions
    attr_reader :attempted_solutions

    def initialize
      reset!

      @attempted_solutions = 1
      @backtracking = false
    end

    def decision_level
      @decisions.length
    end

    def relation(term)
      package = term.package
      return :overlap if !@terms.key?(package)

      @relation_cache[package][term] ||=
        @terms[package].relation(term)
    end

    def satisfies?(term)
      relation(term) == :subset
    end

    def derive(term, cause)
      add_assignment(Assignment.new(term, cause, decision_level, assignments.length))
    end

    def satisfier(term)
      assignment =
        @assignments_by[term.package].bsearch do |assignment_by|
          @cumulative_assignments[assignment_by].satisfies?(term)
        end

      assignment || raise("#{term} unsatisfied")
    end

    # A list of unsatisfied terms
    def unsatisfied
      @required.keys.reject do |package|
        @decisions.key?(package)
      end.map do |package|
        @terms[package]
      end
    end

    def decide(package, version)
      @attempted_solutions += 1 if @backtracking
      @backtracking = false;

      decisions[package] = version
      assignment = Assignment.decision(package, version, decision_level, assignments.length)
      add_assignment(assignment)
    end

    def backtrack(previous_level)
      @backtracking = true

      new_assignments = assignments.select do |assignment|
        assignment.decision_level <= previous_level
      end

      new_decisions = Hash[decisions.first(previous_level)]

      reset!

      @decisions = new_decisions

      new_assignments.each do |assignment|
        add_assignment(assignment)
      end
    end

    private

    def reset!
      # { Array<Assignment> }
      @assignments = []

      # { Package => Array<Assignment> }
      @assignments_by = Hash.new { |h,k| h[k] = [] }
      @cumulative_assignments = {}.compare_by_identity

      # { Package => Package::Version }
      @decisions = {}

      # { Package => Term }
      @terms = {}
      @relation_cache = Hash.new { |h,k| h[k] = {} }

      # { Package => Boolean }
      @required = {}
    end

    def add_assignment(assignment)
      term = assignment.term
      package = term.package

      @assignments << assignment
      @assignments_by[package] << assignment

      @required[package] = true if term.positive?

      if @terms.key?(package)
        old_term = @terms[package]
        @terms[package] = old_term.intersect(term)
      else
        @terms[package] = term
      end
      @relation_cache[package].clear

      @cumulative_assignments[assignment] = @terms[package]
    end
  end
end
