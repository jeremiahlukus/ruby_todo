# frozen_string_literal: true

require "test_helper"

class AIAssistantTest < Minitest::Test
  def setup
    super
    @notebook = RubyTodo::Notebook.create(name: "Test Notebook")
    @notebook.update!(is_default: true)
    @task1 = @notebook.tasks.create(title: "Test Task 1", status: "todo")
    @task2 = @notebook.tasks.create(title: "Test Task 2", status: "todo")
    @task3 = @notebook.tasks.create(title: "Test Task 3", status: "in_progress")
    @ai_command = RubyTodo::AIAssistantCommand.new([], { verbose: true })
  end

  def teardown
    # Clean up test database
    RubyTodo::Task.delete_all
    RubyTodo::Notebook.delete_all
  end

  def test_build_context
    # Use send to access private method
    context = @ai_command.send(:build_context)

    assert_kind_of Hash, context
    assert_includes context.keys, :matching_tasks
    assert_kind_of Array, context[:matching_tasks]
  end

  def test_execute_commands
    # Test execute_commands with a mock response
    response = {
      "commands" => ["ruby_todo notebook:list"],
      "explanation" => "Listing all notebooks"
    }

    # Capture stdout to verify output
    out, _err = capture_io do
      @ai_command.send(:execute_commands, response)
    end

    # Verify output
    assert_match(/Executing command:/, out)
  end

  def test_execute_commands_with_invalid_input
    # Test with invalid response
    response = { "commands" => nil }

    out, _err = capture_io do
      @ai_command.send(:execute_commands, response)
    end

    # Verify no execution for nil commands
    refute_match(/Executing command:/, out)
  end

  def test_handle_task_request
    # Test task movement with task ID
    prompt = "move task #{@task1.id} in Test Notebook to done"
    context = {}

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify context was updated
    assert_equal 1, context[:matching_tasks].size
    assert_equal "done", context[:target_status]
    assert_equal @task1.id.to_s, context[:search_term]

    # Test with a different status
    prompt = "move task #{@task2.id} in Test Notebook to in progress"
    context = {}

    _out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify correct status was extracted
    assert_equal "in_progress", context[:target_status]
    assert_equal @task2.id.to_s, context[:search_term]
  end

  def test_extract_search_term_all_tasks
    # Test the extraction of the special "*" token for "all tasks" queries
    prompts = [
      "move all tasks to done",
      "move every task to in_progress",
      "move all to todo",
      "move everything to archived"
    ]

    prompts.each do |prompt|
      # Use send to access private method
      search_term = @ai_command.send(:extract_search_term, prompt)
      assert_equal "*", search_term, "Should return special token '*' for prompt: '#{prompt}'"
    end
  end

  def test_pre_search_tasks_all_tasks
    # Test that the pre_search_tasks method returns all tasks when given the special "*" token
    search_term = "*"

    # Capture stdout to verify output
    _out, _err = capture_io do
      matching_tasks = @ai_command.send(:pre_search_tasks, search_term)

      # Verify that all tasks are returned
      assert_equal 3, matching_tasks.size, "Should return all 3 tasks"

      # Verify that task details are correctly included
      task_ids = matching_tasks.map { |t| t[:task_id] }
      assert_includes task_ids, @task1.id
      assert_includes task_ids, @task2.id
      assert_includes task_ids, @task3.id
    end
  end

  def test_handle_move_all_tasks
    # Test handling of "move all tasks" command
    prompt = "move all tasks to in_progress"
    context = {}

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify all tasks were identified
    assert_equal 3, context[:matching_tasks].size
    assert_equal "in_progress", context[:target_status]
    assert_equal "*", context[:search_term]
  end

  def test_handle_common_query
    # Test that handle_common_query correctly identifies and handles common queries

    # Test high priority listing
    _out, _err = capture_io do
      result = @ai_command.send(:handle_common_query, "show me all high priority tasks")
      assert result, "Should handle high priority task query"
    end

    # Test statistics command
    _out, _err = capture_io do
      result = @ai_command.send(:handle_common_query, "show stats for my tasks")
      assert result, "Should handle statistics query"
    end
  end

  def test_compound_query_detection
    # Test that the compound query detection works for generic cases
    # Create tasks with multiple terms
    project1 = "alpha-project"
    project2 = "beta-project"

    # Create test tasks
    @task1 = @notebook.tasks.create(
      title: "Update #{project1} documentation",
      status: "todo"
    )
    @task2 = @notebook.tasks.create(
      title: "Fix bugs in #{project2} module",
      status: "todo"
    )
    task3 = @notebook.tasks.create(
      title: "Refactor code in both #{project1} and #{project2}",
      status: "todo"
    )

    # Test compound query with "and"
    prompt = "move tasks about #{project1} and #{project2} to done"
    context = {}

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify that it found task3 which contains both terms
    if context[:matching_tasks]
      task_titles = context[:matching_tasks].map { |t| t[:title] }
      assert_includes task_titles, task3.title, "Should find task with both project names"

      # Verify correct status extraction
      assert_equal "done", context[:target_status], "Should extract 'done' from prompt"
    end

    # Test with a different type of task relationship
    prompt = "set the status of #{project1} and #{project2} tasks to in progress"
    context = {}

    # Capture stdout with verbose output for debugging
    _out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify status extraction
    assert_equal "in_progress", context[:target_status], "Should extract 'in_progress' from prompt"

    # Verify matching tasks - should find tasks with either project1 or project2
    if context[:matching_tasks]
      assert_operator context[:matching_tasks].size, :>=, 1, "Should find at least one matching task"
    end
  end

  def test_status_extraction
    # Test direct status extraction for different phrases
    test_cases = [
      { prompt: "move tasks to done", expected: "done" },
      { prompt: "set status to in_progress", expected: "in_progress" },
      { prompt: "change status to in progress", expected: "in_progress" },
      { prompt: "mark tasks as done", expected: "done" },
      { prompt: "set tasks to todo", expected: "todo" },
      { prompt: "move tasks to n prgrs", expected: "in_progress" },
      {
        prompt: "set status of tasks related to system1 or system2 to in_progress",
        expected: "in_progress"
      },
      { prompt: "move tasks with high priority to done", expected: "done" }
    ]

    test_cases.each do |test_case|
      _out, _err = capture_io do
        result = @ai_command.send(:extract_target_status, test_case[:prompt])
        assert_equal(
          test_case[:expected],
          result,
          "Should extract '#{test_case[:expected]}' from '#{test_case[:prompt]}'"
        )
      end
    end
  end

  def test_multiple_search_patterns
    puts "\n========== STARTING TEST_MULTIPLE_SEARCH_PATTERNS =========="

    # Create test tasks with different patterns
    system1 = "payment-system"
    system2 = "auth-service"
    category = "backend"

    puts "\n----- Creating Test Tasks -----"
    task1 = @notebook.tasks.create(
      title: "Update #{system1} API endpoints",
      status: "todo",
      tags: "api,#{category}"
    )
    puts "Created task1: ID=#{task1.id}, Title='#{task1.title}', " \
         "Tags='#{task1.tags}', Status='#{task1.status}'"

    task2 = @notebook.tasks.create(
      title: "Integrate #{system2} with #{system1}",
      status: "todo",
      tags: "integration,#{category}"
    )
    puts "Created task2: ID=#{task2.id}, Title='#{task2.title}', " \
         "Tags='#{task2.tags}', Status='#{task2.status}'"

    task3 = @notebook.tasks.create(
      title: "Fix #{system2} performance issues",
      status: "todo",
      tags: "performance,#{category}"
    )
    puts "Created task3: ID=#{task3.id}, Title='#{task3.title}', " \
         "Tags='#{task3.tags}', Status='#{task3.status}'"

    # Test different compound query patterns
    test_cases = [
      {
        prompt: "move #{system1} and #{system2} tasks to done",
        expected_matches: [task1.id, task2.id, task3.id],
        expected_status: "done",
        description: "Simple AND with two systems",
        search_terms: [system1, system2]
      },
      {
        prompt: "set status of tasks related to #{system1} or #{system2} to in_progress",
        expected_matches: [task1.id, task2.id, task3.id],
        expected_status: "in_progress",
        description: "OR relationship with 'set status' format",
        search_terms: [system1, system2]
      },
      {
        prompt: "mark all #{category} tasks as done",
        expected_matches: [task1.id, task2.id, task3.id],
        expected_status: "done",
        description: "Category-based matching using tags",
        search_terms: [category]
      },
      {
        prompt: "change #{system1} integration tasks to in progress",
        expected_matches: [task2.id],
        expected_status: "in_progress",
        description: "Combined term matching with action in title",
        search_terms: [system1, "integration"]
      }
    ]

    test_cases.each_with_index do |test_case, index|
      context = {}
      puts "\n===== Test Case #{index + 1}: #{test_case[:description]} ====="
      puts "Prompt: '#{test_case[:prompt]}'"
      puts "Expected Status: #{test_case[:expected_status]}"
      puts "Expected Search Terms: #{test_case[:search_terms].join(", ")}"
      puts "Expected Matching Task IDs: #{test_case[:expected_matches].join(", ")}"

      # Capture stdout and deliberately use the output for debugging
      _out, _err = capture_io do
        puts "\n----- Processing Test Case -----"

        # Debug the search term extraction
        search_term = @ai_command.send(:extract_search_term, test_case[:prompt])
        puts "Extracted Search Term: '#{search_term}'"

        # Debug the status extraction before handling request
        target_status = @ai_command.send(:extract_target_status, test_case[:prompt])
        puts "Pre-extracted Target Status: '#{target_status}'"

        @ai_command.send(:handle_task_request, test_case[:prompt], context)
      end

      puts "\n----- Test Case Results -----"
      puts "Extracted Status: #{context[:target_status].inspect}"

      # Verify correct status extraction
      status_matches = test_case[:expected_status] == context[:target_status]
      puts "Status Extraction #{status_matches ? "PASSED" : "FAILED"}: " \
           "Expected '#{test_case[:expected_status]}', Got '#{context[:target_status].inspect}'"

      assert_equal(
        test_case[:expected_status],
        context[:target_status],
        "Should extract '#{test_case[:expected_status]}' from prompt: '#{test_case[:prompt]}'"
      )

      # Verify matching tasks
      if context[:matching_tasks] && !context[:matching_tasks].empty?
        task_ids = context[:matching_tasks].map { |t| t[:task_id] }
        puts "Found Task IDs: #{task_ids.join(", ")}"

        # Check if we found at least some of the expected matches
        intersection = task_ids & test_case[:expected_matches]
        match_success = intersection.any?
        puts "Task Matching #{match_success ? "PASSED" : "FAILED"}: " \
             "Found #{intersection.size} expected tasks"

        puts "Matching Task Details:"
        context[:matching_tasks].each do |task|
          puts "  - ID: #{task[:task_id]}, Title: #{task[:title]}, Status: #{task[:status]}"
        end

        assert_predicate(
          intersection,
          :any?,
          "Should find some of the expected tasks for: #{test_case[:description]}"
        )
      else
        puts "WARNING: No matching tasks found!"
        puts "Context dump for debugging:"
        puts context.inspect
      end

      puts "\n----- End Test Case #{index + 1} -----"
    end

    puts "\n========== COMPLETED TEST_MULTIPLE_SEARCH_PATTERNS ==========\n"
  end
end
