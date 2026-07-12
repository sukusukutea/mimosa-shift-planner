class CreateShiftDayRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_requirements do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.date :date
      t.integer :shift_kind
      t.integer :role
      t.integer :required_number

      t.timestamps
    end

    add_index :shift_day_requirements,
      [ :shift_month_id, :date, :shift_kind, :role ],
      unique: true,
      name: "idx_shift_day_requirements_unique"
  end
end
