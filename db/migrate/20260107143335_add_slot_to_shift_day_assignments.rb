class AddSlotToShiftDayAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_day_assignments, :slot, :integer, null: false, default: 0

    remove_index :shift_day_assignments, name: "idx_sda_draft_unique"
    remove_index :shift_day_assignments, name: "idx_sda_confirmed_unique"

    add_index :shift_day_assignments,
              [ :shift_month_id, :draft_token, :date, :shift_kind, :slot ],
              unique: true,
              where: "(source = 0)",
              name: "idx_sda_draft_unique"

    add_index :shift_day_assignments,
              [ :shift_month_id, :date, :shift_kind, :slot ],
              unique: true,
              where: "(source = 1)",
              name: "idx_sda_confirmed_unique"
  end
end
