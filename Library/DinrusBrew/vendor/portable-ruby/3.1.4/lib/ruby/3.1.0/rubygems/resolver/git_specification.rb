# frozen_string_literal: true
##
# A GitSpecification represents a gem that is sourced from a git repository
# and is being loaded through a gem dependencies file through the +git:+
# option.

class Gem::Resolver::GitSpecification < Gem::Resolver::SpecSpecification
  def ==(other) # :nodoc:
    self.class === other &&
      @set  == other.set &&
      @spec == other.spec &&
      @source == other.source
  end

  def add_dependency(dependency) # :nodoc:
    spec.dependencies << dependency
  end

  ##
  # Installing a git gem only involves building the extensions and generating
  # the executables.

  def install(options = {})
    require_relative "../installer"

    installer = Gem::Installer.for_spec spec, options

    yield installer if block_given?

    installer.run_pre_install_hooks
    installer.build_extensions
    installer.run_post_build_hooks
    installer.generate_bin
    installer.run_post_install_hooks
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[GitSpecification", "]" do
      q.breakable
      q.text "name: #{name}"

      q.breakable
      q.text "version: #{version}"

      q.breakable
      q.text "dependencies:"
      q.breakable
      q.pp dependencies

      q.breakable
      q.text "source:"
      q.breakable
      q.pp @source
    end
  end
end
