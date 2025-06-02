# frozen_string_literal: true

require_relative "shared_helpers"
Bundler::SharedHelpers.major_deprecation 2,
  "The Bundler task for Vlad"

# Vlad task for Bundler.
#
# Add "require 'bundler/vlad'" in your Vlad deploy.rb, and
# include the vlad:bundle:install task in your vlad:deploy task.
require_relative "deployment"

include Rake::DSL if defined? Rake::DSL

namespace :vlad do
  Bundler::Deployment.define_task(Rake::RemoteTask, :remote_task, roles: :app)
end
