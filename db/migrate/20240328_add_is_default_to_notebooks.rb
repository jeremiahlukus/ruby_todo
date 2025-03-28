# frozen_string_literal: true

module RubyTodo
  class AddIsDefaultToNotebooks < ActiveRecord::Migration[7.2]
    def change
      add_column :notebooks, :is_default, :boolean, default: false
      add_index :notebooks, :is_default
    end
  end
end
