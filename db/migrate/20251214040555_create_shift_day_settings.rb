class CreateShiftDaySettings < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_settings do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.date :date, null: false

      t.timestamps
    end

    add_index :shift_day_settings, [ :shift_month_id, :date ], unique: true
  end
end
