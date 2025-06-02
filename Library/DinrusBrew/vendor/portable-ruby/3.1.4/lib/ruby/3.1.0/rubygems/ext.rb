# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

##
# Classes for building C extensions live here.

module Gem::Ext; end

require_relative "ext/build_error"
require_relative "ext/builder"
require_relative "ext/configure_builder"
require_relative "ext/ext_conf_builder"
require_relative "ext/rake_builder"
require_relative "ext/cmake_builder"
require_relative "ext/cargo_builder"
