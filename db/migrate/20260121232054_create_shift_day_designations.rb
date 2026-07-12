class CreateShiftDayDesignations < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_designations do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :shift_kind, null: false
      t.timestamps
    end

    add_index :shift_day_designations,
              [ :shift_month_id, :date, :shift_kind ],
              unique: true,
              name: "idx_sdd_unique_per_month_date_kind"
  end
end
