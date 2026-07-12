class ChangeShiftDayDesignationsUniqToStaffPerDay < ActiveRecord::Migration[8.1]
  def change
    remove_index :shift_day_designations, name: :idx_sdd_unique_per_month_date_kind
    add_index :shift_day_designations,
              [ :shift_month_id, :date, :staff_id ],
              unique: true,
              name: :idx_sdd_unique_per_month_date_staff
  end
end
