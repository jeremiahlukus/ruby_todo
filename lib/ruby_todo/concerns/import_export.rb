# frozen_string_literal: true

module RubyTodo
  module CsvExport
    private

    def export_multiple_notebooks_to_csv(data, csv)
      csv << ["Notebook", "Task ID", "Title", "Description", "Status", "Priority", "Tags", "Due Date",
              "Created At", "Updated At"]

      data["notebooks"].each do |notebook|
        notebook_name = notebook["name"]
        notebook["tasks"].each_with_index do |task, index|
          csv << [
            notebook_name,
            index + 1,
            task["title"],
            task["description"],
            task["status"],
            task["priority"],
            task["tags"],
            task["due_date"],
            task["created_at"],
            task["updated_at"]
          ]
        end
      end
    end

    def export_single_notebook_to_csv(data, csv)
      csv << ["Task ID", "Title", "Description", "Status", "Priority", "Tags", "Due Date", "Created At",
              "Updated At"]

      data["tasks"].each_with_index do |task, index|
        csv << [
          index + 1,
          task["title"],
          task["description"],
          task["status"],
          task["priority"],
          task["tags"],
          task["due_date"],
          task["created_at"],
          task["updated_at"]
        ]
      end
    end
  end

  module ImportExport
    include CsvExport

    def export_notebook(notebook)
      {
        "name" => notebook.name,
        "created_at" => notebook.created_at,
        "updated_at" => notebook.updated_at,
        "tasks" => notebook.tasks.map { |task| task_to_hash(task) }
      }
    end

    def export_all_notebooks(notebooks)
      {
        "notebooks" => notebooks.map { |notebook| export_notebook(notebook) }
      }
    end

    def task_to_hash(task)
      {
        "title" => task.title,
        "description" => task.description,
        "status" => task.status,
        "priority" => task.priority,
        "tags" => task.tags,
        "due_date" => task.due_date&.iso8601,
        "created_at" => task.created_at&.iso8601,
        "updated_at" => task.updated_at&.iso8601
      }
    end

    def export_to_json(data, filename)
      File.write(filename, JSON.pretty_generate(data))
    end

    def export_to_csv(data, filename)
      CSV.open(filename, "wb") do |csv|
        if data["notebooks"]
          export_multiple_notebooks_to_csv(data, csv)
        else
          export_single_notebook_to_csv(data, csv)
        end
      end
    end

    def import_tasks(notebook, tasks_data)
      count = 0

      tasks_data.each do |task_data|
        due_date = Time.parse(task_data["due_date"]) if task_data["due_date"]

        task = Task.create(
          notebook: notebook,
          title: task_data["title"],
          description: task_data["description"],
          status: task_data["status"] || "todo",
          priority: task_data["priority"],
          tags: task_data["tags"],
          due_date: due_date
        )

        count += 1 if task.persisted?
      end

      count
    end

    def import_all_notebooks(data)
      results = { notebooks: 0, tasks: 0 }

      data["notebooks"].each do |notebook_data|
        notebook_name = notebook_data["name"]
        notebook = Notebook.find_by(name: notebook_name)

        unless notebook
          notebook = Notebook.create(name: notebook_name)
          results[:notebooks] += 1 if notebook.persisted?
        end

        if notebook.persisted?
          tasks_count = import_tasks(notebook, notebook_data["tasks"])
          results[:tasks] += tasks_count
        end
      end

      results
    end
  end
end
