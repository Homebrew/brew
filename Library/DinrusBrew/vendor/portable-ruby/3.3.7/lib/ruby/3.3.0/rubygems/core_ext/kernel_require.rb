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
    # :stopdoc:
    alias_method :gem_original_require, :require
    private :gem_original_require
    # :startdoc:
  end

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

  def require(path) # :doc:
    return gem_original_require(path) unless Gem.discover_gems_on_require

    RUBYGEMS_ACTIVATION_MONITOR.synchronize do
      path = File.path(path)

      # If +path+ belongs to a default gem, we activate it and then go straight
      # to normal require

      if spec = Gem.find_default_spec(path)
        name = spec.name

        next if Gem.loaded_specs[name]

        # Ensure -I beats a default gem
        resolved_path = begin
          rp = nil
          load_path_check_index = Gem.load_path_insert_index - Gem.activated_gem_paths
          Gem.suffixes.find do |s|
            $LOAD_PATH[0...load_path_check_index].find do |lp|
              if File.symlink? lp # for backward compatibility
                next
              end

              full_path = File.expand_path(File.join(lp, "#{path}#{s}"))
              rp = full_path if File.file?(full_path)
            end
          end
          rp
        end

        Kernel.send(:gem, name, Gem::Requirement.default_prerelease) unless
          resolved_path

        next
      end

      # If there are no unresolved deps, then we can use just try
      # normal require handle loading a gem from the rescue below.

      if Gem::Specification.unresolved_deps.empty?
        next
      end

      # If +path+ is for a gem that has already been loaded, don't
      # bother trying to find it in an unresolved gem, just go straight
      # to normal require.
      #--
      # TODO request access to the C implementation of this to speed up RubyGems

      if Gem::Specification.find_active_stub_by_path(path)
        next
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

        found_specs.each(&:activate)

      # We found +path+ directly in an unresolved gem. Now we figure out, of
      # the possible found specs, which one we should activate.
      else

        # Check that all the found specs are just different
        # versions of the same gem
        names = found_specs.map(&:name).uniq

        if names.size > 1
          raise Gem::LoadError, "#{path} found in multiple gems: #{names.join ", "}"
        end

        # Ok, now find a gem that has no conflicts, starting
        # at the highest version.
        valid = found_specs.find {|s| !s.has_conflicts? }

        unless valid
          le = Gem::LoadError.new "unable to find a version of '#{names.first}' to activate"
          le.name = names.first
          raise le
        end

        valid.activate
      end
    end

    begin
      gem_original_require(path)
    rescue LoadError => load_error
      if load_error.path == path &&
         RUBYGEMS_ACTIVATION_MONITOR.synchronize { Gem.try_activate(path) }

        return gem_original_require(path)
      end

      raise load_error
    end
  end

  private :require
end
