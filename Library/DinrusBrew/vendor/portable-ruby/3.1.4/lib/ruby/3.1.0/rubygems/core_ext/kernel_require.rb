# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require "monitor"

module Kernel

  RUBYGEMS_ACTIVATION_MONITOR = Monitor.new # :nodoc:

  # Make sure we have a reference to Ruby's original Kernel#require
  unless defined?(gem_original_require)
    alias gem_original_require require
    private :gem_original_require
  end

  file = Gem::KERNEL_WARN_IGNORES_INTERNAL_ENTRIES ? "<internal:#{__FILE__}>" : __FILE__
  module_eval <<'RUBY', file, __LINE__ + 1 # rubocop:disable Style/EvalWithLocation
  ##
  # When RubyGems is required, Kernel#require is replaced with our own which
  # is capable of loading gems on demand.
  #
  # When you call <tt>require 'x'</tt>, this is what happens:
  # * If the file can be loaded from the existing Ruby loadpath, it
  #   is.
  # * Otherwise, installed gems are searched for a file that matches.
  #   If it's found in gem 'y', that gem is activated (added to the
  #   loadpath).
  #
  # The normal <tt>require</tt> functionality of returning false if
  # that file has already been loaded is preserved.

  def require(path)
    if RUBYGEMS_ACTIVATION_MONITOR.respond_to?(:mon_owned?)
      monitor_owned = RUBYGEMS_ACTIVATION_MONITOR.mon_owned?
    end
    RUBYGEMS_ACTIVATION_MONITOR.enter

    path = path.to_path if path.respond_to? :to_path

    if spec = Gem.find_unresolved_default_spec(path)
      # Ensure -I beats a default gem
      resolved_path = begin
        rp = nil
        load_path_check_index = Gem.load_path_insert_index - Gem.activated_gem_paths
        Gem.suffixes.each do |s|
          $LOAD_PATH[0...load_path_check_index].each do |lp|
            safe_lp = lp.dup.tap(&Gem::UNTAINT)
            begin
              if File.symlink? safe_lp # for backward compatibility
                next
              end
            rescue SecurityError
              RUBYGEMS_ACTIVATION_MONITOR.exit
              raise
            end

            full_path = File.expand_path(File.join(safe_lp, "#{path}#{s}"))
            if File.file?(full_path)
              rp = full_path
              break
            end
          end
          break if rp
        end
        rp
      end

      begin
        Kernel.send(:gem, spec.name, Gem::Requirement.default_prerelease)
      rescue Exception
        RUBYGEMS_ACTIVATION_MONITOR.exit
        raise
      end unless resolved_path
    end

    # If there are no unresolved deps, then we can use just try
    # normal require handle loading a gem from the rescue below.

    if Gem::Specification.unresolved_deps.empty?
      RUBYGEMS_ACTIVATION_MONITOR.exit
      return gem_original_require(path)
    end

    # If +path+ is for a gem that has already been loaded, don't
    # bother trying to find it in an unresolved gem, just go straight
    # to normal require.
    #--
    # TODO request access to the C implementation of this to speed up RubyGems

    if Gem::Specification.find_active_stub_by_path(path)
      RUBYGEMS_ACTIVATION_MONITOR.exit
      return gem_original_require(path)
    end

    # Attempt to find +path+ in any unresolved gems...

    found_specs = Gem::Specification.find_in_unresolved path

    # If there are no directly unresolved gems, then try and find +path+
    # in any gems that are available via the currently unresolved gems.
    # For example, given:
    #
    #   a => b => c => d
    #
    # If a and b are currently active with c being unresolved and d.rb is
    # requested, then find_in_unresolved_tree will find d.rb in d because
    # it's a dependency of c.
    #
    if found_specs.empty?
      found_specs = Gem::Specification.find_in_unresolved_tree path

      found_specs.each do |found_spec|
        found_spec.activate
      end

    # We found +path+ directly in an unresolved gem. Now we figure out, of
    # the possible found specs, which one we should activate.
    else

      # Check that all the found specs are just different
      # versions of the same gem
      names = found_specs.map(&:name).uniq

      if names.size > 1
        RUBYGEMS_ACTIVATION_MONITOR.exit
        raise Gem::LoadError, "#{path} found in multiple gems: #{names.join ', '}"
      end

      # Ok, now find a gem that has no conflicts, starting
      # at the highest version.
      valid = found_specs.find {|s| !s.has_conflicts? }

      unless valid
        le = Gem::LoadError.new "unable to find a version of '#{names.first}' to activate"
        le.name = names.first
        RUBYGEMS_ACTIVATION_MONITOR.exit
        raise le
      end

      valid.activate
    end

    RUBYGEMS_ACTIVATION_MONITOR.exit
    return gem_original_require(path)
  rescue LoadError => load_error
    RUBYGEMS_ACTIVATION_MONITOR.enter

    begin
      if load_error.path == path and Gem.try_activate(path)
        require_again = true
      end
    ensure
      RUBYGEMS_ACTIVATION_MONITOR.exit
    end

    return gem_original_require(path) if require_again

    raise load_error
  ensure
    if RUBYGEMS_ACTIVATION_MONITOR.respond_to?(:mon_owned?)
      if monitor_owned != (ow = RUBYGEMS_ACTIVATION_MONITOR.mon_owned?)
        STDERR.puts [$$, Thread.current, $!, $!.backtrace].inspect if $!
        raise "CRITICAL: RUBYGEMS_ACTIVATION_MONITOR.owned?: before #{monitor_owned} -> after #{ow}"
      end
    end
  end
RUBY

  private :require

end
