class AddShiftMonthTimeOptionToShiftDayAssignments < ActiveRecord::Migration[8.1]
  def change
    add_reference :shift_day_assignments,
                  :shift_month_time_option,
                  null: true,
                  foreign_key: true
  end
end
