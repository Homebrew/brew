## 1. First step of the `test-unit`

Let's getting start `test-unit`.

This document creates an example gem package called `sample` with the `test-unit` testing framework.

## 2. Install bundler and test-unit.

* First, install the `bundler` gem for generating gem template.
* Second, install the `test-unit` itself.

~~~
!!!plain
gem install bundler
gem install test-unit
~~~

The `gem list` command output installed packages.
You will find the following lines.

~~~
!!!plain
gem list
...
bundler (1.14.6)
...
test-unit (3.2.3)
~~~

## 3. Create gem template.

Next, create a gem template using `bundler` command.
This command generates package skeleton with a testing framework.
However, this command can't generate test templates for `test-unit`.

So, First create gem template with the `minitest` testing framework.
(It's similar to `unit-test`).
After that, replace some files for `test-unit`.

The `bundle gem -t minitest sample` command will generate the following files.

~~~
!!!plain
.
|-- Gemfile
|-- README.md
|-- Rakefile
|-- bin
|   |-- console
|   `-- setup
|-- lib
|   |-- sample
|   |   `-- version.rb
|   `-- sample.rb
|-- sample.gemspec  # <- Modify
`-- test
    |-- sample_test.rb # <- Modify
    `-- test_helper.rb # <- Modify
~~~

## 4. Edit files for `test-unit`

### 4.1. Edit gemspec

Edit `sample.gemspec` like the below.
Replace `minitest` line to `test-unit`.

Before

~~~
!!!ruby
  spec.add_development_dependency "minitest", "~> 5.0"
~~~

After

~~~
!!!ruby
  spec.add_development_dependency "test-unit", "~> 3.2.3"
~~~

### 4.2. Edit `test/test_helper.rb`

Next, edit the `test/test_helper.rb` file.

Before

~~~
!!!ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'sample'

require 'minitest/autorun' # <-- Modify this line.
~~~

After

~~~
!!!ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'sample'

require 'test/unit' # <-- After modification.
~~~

### 4.3 Rakefile (No edit)

This file doesn't need to modify.
The output is the below.

~~~
!!!ruby
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
~~~

### 4.4 Edit `test/sample_test.rb`

The bundler generate the file `test/sample_test.rb`.
This file originally templates for `minitest`.

Let's modify this file for `test-unit`

before

~~~
!!!ruby
require 'test_helper'

class SampleTest < Minitest::Test # <- Modify here
  def test_that_it_has_a_version_number
    refute_nil ::Sample::VERSION
  end

  def test_it_does_something_useful
    assert false
  end
end
~~~

After

~~~
!!!ruby
require 'test_helper'

class SampleTest < Test::Unit::TestCase # <- After modification
  def test_that_it_has_a_version_number
    refute_nil ::Sample::VERSION
  end

  def test_it_does_something_useful
    assert false
  end
end
~~~

## 5. Execute test.

The `rake test` command execute test scenarios in the `test` directory.
Now it tries to two tests. One will success the other one fails.

~~~
!!!plain
rake test
Loaded suite
/path/to/ruby/lib/ruby/gems/2.3.0/gems/rake-12.0.0/lib/rake/rake_test_loader
Started
F
================================================================================
Failure: <false> is not true.
test_it_does_something_useful(SampleTest)
/path/to/sample/test/sample_test.rb:9:in `test_it_does_something_useful'
      6:   end
      7:
      8:   def test_it_does_something_useful
  =>  9:     assert false
     10:   end
     11: end
================================================================================
.

Finished in 0.011521 seconds.
--------------------------------------------------------------------------------
2 tests, 2 assertions, 1 failures, 0 errors, 0 pendings, 0 omissions, 0 notifications
50% passed
--------------------------------------------------------------------------------
173.60 tests/s, 173.60 assertions/s
rake aborted!
Command failed with status (1)

Tasks: TOP => test
(See full trace by running task with --trace)
~~~

## 6. Create original tests.

Let's create your original tests with the following rules.

* Create a test file in the `test` directory.
* The file needs suffix  `xxx_test.rb`.
* You can put test file into the subdirectory like `test/sub`.

Example directory layout.

~~~
!!!plain
test
|-- sample_test.rb
|-- sub
|   `-- sample2_test.rb
`-- test_helper.rb
~~~

Example test file in the sub directory.

~~~
!!!ruby
require 'test_helper'

module Sub
  class Sample2Test < Test::Unit::TestCase
    def test_that_it_has_a_version_number
      refute_nil ::Sample::VERSION
    end

    def test_it_does_something_useful
      assert false
    end
  end
end
~~~

## 7. For more information

Let's read the official document.

* [test-unit](http://test-unit.github.io/index.html)
