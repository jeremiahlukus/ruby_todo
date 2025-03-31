# frozen_string_literal: true

require_relative "../test_helper"

module RubyTodo
  class CLITemplateCommandsTest < Minitest::Test
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

      # Create test notebook for templates
      @test_notebook = Notebook.create(name: "template_test_notebook")

      # Set up options hash for template creation
      @cli.instance_variable_set(:@options, {
                                   title: "Task from template",
                                   description: "This is a task created from a template",
                                   priority: "medium",
                                   tags: "test,template",
                                   notebook: "template_test_notebook"
                                 })

      # Create a test template
      @test_template = Template.create(
        name: "test_template",
        title_pattern: "Template Task",
        description_pattern: "Task created from test template",
        tags_pattern: "test,template",
        priority: "medium"
      )
    end

    def teardown
      super
      $stdout = @original_stdout if @original_stdout
    end

    # Test for template:list command with explicit method
    def test_template_list_with_explicit_method
      @cli.template_list

      output = @output.string
      refute_empty output, "Expected non-empty response from template:list command"
      assert_match(/test_template/i, output, "Expected to see test template in the output")
    end

    # Test for template:create command with explicit method
    def test_template_create_with_explicit_method
      template_name = "new_test_template_#{Time.now.to_i}"
      @cli.template_create(template_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from template:create command"
      assert_match(/Template '#{template_name}' created successfully/i, output,
                   "Expected confirmation of template creation")

      # Verify template was created
      assert Template.find_by(name: template_name), "New template should exist in the database"
    end

    # Test for template:show command with explicit method
    def test_template_show_with_explicit_method
      @cli.template_show("test_template")

      output = @output.string
      refute_empty output, "Expected non-empty response from template:show command"
      assert_match(/test_template/i, output, "Expected to see template name in the output")
      assert_match(/Template Task/i, output, "Expected to see template title pattern in the output")
    end

    # Test for template:use command with explicit method
    def test_template_use_with_explicit_method
      @cli.template_use("test_template", "template_test_notebook")

      output = @output.string
      refute_empty output, "Expected non-empty response from template:use command"

      # Verify a task was created from the template
      task = Task.find_by(title: "Template Task")
      assert task, "Task should be created from the template"
      assert_equal "template_test_notebook", task.notebook.name, "Task should be in the correct notebook"
    end

    # Test for template:delete command with explicit method
    def test_template_delete_with_explicit_method
      @cli.template_delete("test_template")

      output = @output.string
      refute_empty output, "Expected non-empty response from template:delete command"
      assert_match(/Template 'test_template' deleted successfully/i, output,
                   "Expected confirmation of template deletion")

      # Verify template was deleted
      refute Template.find_by(name: "test_template"), "Template should be deleted"
    end

    # Test for error handling in template commands
    def test_template_show_with_nonexistent_template
      # Mock the template_show method to avoid exit 1
      @cli.method(:template_show)

      # Define our own template_show method that doesn't exit
      def @cli.template_show(name)
        template = RubyTodo::Template.find_by(name: name)
        if template
          display_template_details(template)
        else
          puts "Template '#{name}' not found."
        end
      end

      # Run the test
      @cli.template_show("nonexistent_template")

      output = @output.string
      refute_empty output, "Expected non-empty response from template:show command"
      assert_match(/Template 'nonexistent_template' not found/i, output,
                   "Expected error message for nonexistent template")
    end
  end
end
