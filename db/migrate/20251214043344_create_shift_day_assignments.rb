class CreateShiftDayAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_assignments do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :shift_kind, null: false

      t.timestamps
    end

    add_index :shift_day_assignments,
              [ :shift_month_id, :date, :shift_kind ],
              unique: true,
              name: "index_shift_day_assignments_unique_per_day_and_kind"
  end
end
