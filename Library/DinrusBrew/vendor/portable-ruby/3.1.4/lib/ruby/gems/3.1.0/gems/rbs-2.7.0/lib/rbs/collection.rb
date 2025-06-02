# frozen_string_literal: true

require 'yaml'
require 'bundler'

require_relative './collection/sources'
require_relative './collection/config'
require_relative './collection/config/lockfile_generator'
require_relative './collection/installer'
require_relative './collection/cleaner'

module RBS
  module Collection
  end
end
