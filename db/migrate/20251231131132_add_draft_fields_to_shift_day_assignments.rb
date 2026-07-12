class AddDraftFieldsToShiftDayAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_day_assignments, :source, :integer, null: false, default: 0
    add_column :shift_day_assignments, :draft_token, :string

    remove_index :shift_day_assignments, name: "index_shift_day_assignments_unique_per_day_and_kind"
    add_index :shift_day_assignments,
              [ :shift_month_id, :date, :shift_kind ],
              unique: true,
              where: "source = 1",
              name: "idx_sda_confirmed_unique"

    add_index :shift_day_assignments,
              [ :shift_month_id, :draft_token, :date, :shift_kind ],
              unique: true,
              where: "source = 0",
              name: "idx_sda_draft_unique"
  end
end
