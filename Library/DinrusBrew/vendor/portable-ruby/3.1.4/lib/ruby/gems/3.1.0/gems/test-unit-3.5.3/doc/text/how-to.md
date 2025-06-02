# How To

## Run all tests

To make it easy to run all your tests, you can add a `run_test.rb` script
to your `test` directory. A simple example might look like:

    base_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    lib_dir  = File.join(base_dir, "lib")
    test_dir = File.join(base_dir, "test")

    $LOAD_PATH.unshift(lib_dir)

    require 'test/unit'

    exit Test::Unit::AutoRunner.run(true, test_dir)

Then it's easy to run tests via the command line with,

    $ ruby test/run_test.rb

## Change test runner via the command line

The output format can be changed via the command line with
the `--runner` option. Simply tack it to the end:

    ruby test/run_test.rb --runner tap


## Configure test-unit per-project

Test::Unit reads `test-unit.yml` or `.test-unit.yml` in the current working
directory as Test::Unit's configuration file. It can contain the following
settings:

* color scheme definitions
* test runner to be used
* test runner options
* test collector to be used

Except color scheme definitions, all of them can be specified by command
line option.

Here are sample color scheme definitions:

    color_schemes:
      inverted:
        success:
          name: red
          bold: true
        failure:
          name: green
          bold: true
      other_scheme:
        ...

Here are the syntax of color scheme definitions:

    color_schemes:
      SCHEME_NAME:
        EVENT_NAME:
          name: COLOR_NAME
          intensity: BOOLEAN
          bold: BOOLEAN
          italic: BOOLEAN
          underline: BOOLEAN
        ...
      ...

| Definition  | Description                  |
|-------------|------------------------------|
| SCHEME_NAME | the name of the color scheme |
| EVENT_NAME  | success, failure, pending, omission, notification, error |
| COLOR_NAME  | black, red, green, yellow, blue, magenta, cyan, white    |
| BOOLEAN     | true or false |

You can use the above 'inverted' color scheme with the following configuration:

    runner: console
    console_options:
      color_scheme: inverted
    color_schemes:
      inverted:
        success:
          name: red
          bold: true
        failure:
          name: green
          bold: true

