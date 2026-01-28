# typed: strict
# frozen_string_literal: true

require "pycall/import"
# This was a rewrite from `include(Module.new(...))`,
# to appease Sorbet, so let's keep the existing behaviour
# and silence RuboCop.
# rubocop:disable Style/MixinUsage
include PyCall::Import
# rubocop:enable Style/MixinUsage

pyfrom "influxdb_client_3", import: :InfluxDBClient3
