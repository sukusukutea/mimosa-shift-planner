class CreateStaffHolidayRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_holiday_requests do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :date, null: false

      t.timestamps
    end

    add_index :staff_holiday_requests,
              [ :shift_month_id, :staff_id, :date ],
              unique: true,
              name: "idx_staff_holiday_requests_unique"
  end
end
