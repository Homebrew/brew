require "bundler/gem_tasks"

helper = Bundler::GemHelper.new(__dir__)
def helper.version_tag
  version
end

helper.install

desc "Run test"
task :test do
  ruby("test/run-test.rb")
end

task :default => :test
