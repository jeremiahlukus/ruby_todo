# frozen_string_literal: true

module RubyTodo
  module AIAssistant
    # Module for parsing and processing AI responses
    module TaskResponseProcessor
      # Parse the OpenAI response for task details
      def parse_task_details_response(content, task_description)
        # Try to extract JSON from the response
        json_match = content.match(/```json\n(.+?)\n```/m) || content.match(/\{.+\}/m)
        if json_match
          json_str = json_match[0].gsub(/```json\n|```/, "")
          details = JSON.parse(json_str)
          normalize_priority(details)
        else
          extract_task_details_with_regex(content, task_description)
        end
      rescue JSON::ParserError
        extract_task_details_with_regex(content, task_description)
      end

      # Extract task details using regex as a fallback
      def extract_task_details_with_regex(content, task_description)
        title_match = content.match(/title["\s:]+([^"]+)["]/i)
        desc_match = content.match(/description["\s:]+([^"]+)["]/i)
        priority_match = content.match(/priority["\s:]+([^"]+)["]/i)
        tags_match = content.match(/tags["\s:]+([^"]+)["]/i)

        details = {
          "title" => title_match ? title_match[1] : "Task from #{task_description}",
          "description" => desc_match ? desc_match[1] : task_description,
          "priority" => priority_match ? priority_match[1] : "medium",
          "tags" => tags_match ? tags_match[1] : ""
        }

        normalize_priority(details)
      end

      # Normalize priority to ensure only valid values are used
      def normalize_priority(details)
        # Ensure priority is a valid value (high, medium, low)
        if details["priority"]
          # Convert 'normal' to 'medium'
          if details["priority"].downcase == "normal"
            puts "DEBUG: Normalizing 'normal' priority to 'medium'"
            details["priority"] = "medium"
          elsif !%w[high medium low].include?(details["priority"].downcase)
            puts "DEBUG: Invalid priority '#{details["priority"]}', defaulting to 'medium'"
            details["priority"] = "medium"
          else
            # Ensure lowercase for consistency
            details["priority"] = details["priority"].downcase
          end
        else
          # Default to medium if no priority specified
          details["priority"] = "medium"
        end

        details
      end
    end
  end
end
