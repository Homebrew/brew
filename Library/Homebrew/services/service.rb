# typed: strict
# frozen_string_literal: true

# fix loadppath
$LOAD_PATH.unshift(File.expand_path(__dir__))

require "service/formula_wrapper"
require "service/services_cli"
require "service/system"
require "service/commands/cleanup"
require "service/commands/info"
require "service/commands/list"
require "service/commands/restart"
require "service/commands/run"
require "service/commands/start"
require "service/commands/stop"
require "service/commands/kill"
