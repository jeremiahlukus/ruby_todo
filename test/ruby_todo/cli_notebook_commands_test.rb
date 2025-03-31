# frozen_string_literal: true

require_relative "../test_helper"

module RubyTodo
  class CLINotebookCommandsTest < Minitest::Test
    def setup
      super
      @cli = RubyTodo::CLI.new

      # Capture stdout for CLI tests
      @original_stdout = $stdout
      @output = StringIO.new

      # Make StringIO work with TTY by adding necessary methods
      def @output.ioctl(*_args)
        80
      end

      $stdout = @output

      # Create test notebooks
      @default_notebook = Notebook.create(name: "default_test_notebook", is_default: true)
      @regular_notebook = Notebook.create(name: "regular_test_notebook")
    end

    def teardown
      super
      $stdout = @original_stdout if @original_stdout
    end

    # Test for notebook:list command with explicit method
    def test_notebook_list_with_explicit_method
      @cli.notebook_list

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:list command"
      assert_match(/default_test_notebook/i, output, "Expected to see default notebook in the output")
      assert_match(/regular_test_notebook/i, output, "Expected to see regular notebook in the output")
      assert_match(/✓/, output, "Expected to see default indicator in the output")
    end

    # Test for notebook:create command with explicit method
    def test_notebook_create_with_explicit_method
      new_notebook_name = "new_test_notebook_#{Time.now.to_i}"
      @cli.notebook_create(new_notebook_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:create command"
      assert_match(/Created notebook: #{new_notebook_name}/i, output, "Expected confirmation of notebook creation")

      # Verify notebook was created
      assert Notebook.find_by(name: new_notebook_name), "New notebook should exist in the database"
    end

    # Test for notebook:set_default command with explicit method
    def test_notebook_set_default_with_explicit_method
      @cli.notebook_set_default("regular_test_notebook")

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:set_default command"
      assert_match(/Successfully set 'regular_test_notebook' as the default notebook/i, output,
                   "Expected confirmation of setting default notebook")

      # Verify notebook is set as default
      @default_notebook.reload
      @regular_notebook.reload
      refute_predicate @default_notebook, :is_default?, "Original default notebook should no longer be default"
      assert_predicate @regular_notebook, :is_default?, "New notebook should be set as default"
    end

    # Test for error handling in notebook commands
    def test_notebook_set_default_with_nonexistent_notebook
      @cli.notebook_set_default("nonexistent_notebook")

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:set_default command"
      assert_match(/Notebook 'nonexistent_notebook' not found/i, output,
                   "Expected error message for nonexistent notebook")
    end
  end
end
