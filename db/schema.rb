# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_05_093607) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "base_skill_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.integer "required_number", default: 0, null: false
    t.integer "skill"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "day_of_week", "skill"], name: "idx_base_skill_requirements_unique", unique: true
    t.index ["user_id"], name: "index_base_skill_requirements_on_user_id"
  end

  create_table "base_weekday_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.integer "required_number", default: 0, null: false
    t.integer "role", null: false
    t.integer "shift_kind", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "shift_kind", "day_of_week", "role"], name: "idx_base_weekday_requirements_unique", unique: true
    t.index ["user_id"], name: "index_base_weekday_requirements_on_user_id"
  end

  create_table "occupations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_organizations_on_name", unique: true
  end

  create_table "shift_day_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "draft_token"
    t.integer "shift_kind", null: false
    t.bigint "shift_month_id", null: false
    t.integer "slot", default: 0, null: false
    t.integer "source", default: 0, null: false
    t.bigint "staff_day_time_option_id"
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "date", "shift_kind", "slot"], name: "idx_sda_confirmed_unique", unique: true, where: "(source = 1)"
    t.index ["shift_month_id", "draft_token", "date", "shift_kind", "slot"], name: "idx_sda_draft_unique", unique: true, where: "(source = 0)"
    t.index ["shift_month_id"], name: "index_shift_day_assignments_on_shift_month_id"
    t.index ["staff_day_time_option_id"], name: "index_shift_day_assignments_on_staff_day_time_option_id"
    t.index ["staff_id"], name: "index_shift_day_assignments_on_staff_id"
  end

  create_table "shift_day_designations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "shift_kind", null: false
    t.bigint "shift_month_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "date", "staff_id"], name: "idx_sdd_unique_per_month_date_staff", unique: true
    t.index ["shift_month_id"], name: "index_shift_day_designations_on_shift_month_id"
    t.index ["staff_id"], name: "index_shift_day_designations_on_staff_id"
  end

  create_table "shift_day_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "required_number"
    t.integer "role"
    t.integer "shift_kind"
    t.bigint "shift_month_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "date", "shift_kind", "role"], name: "idx_shift_day_requirements_unique", unique: true
    t.index ["shift_month_id"], name: "index_shift_day_requirements_on_shift_month_id"
  end

  create_table "shift_day_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "late_slots", default: 1, null: false
    t.bigint "shift_month_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "date"], name: "index_shift_day_settings_on_shift_month_id_and_date", unique: true
    t.index ["shift_month_id"], name: "index_shift_day_settings_on_shift_month_id"
  end

  create_table "shift_day_skill_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "required_number", default: 0, null: false
    t.integer "shift_kind", null: false
    t.bigint "shift_month_id", null: false
    t.integer "skill", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "date", "shift_kind", "skill"], name: "idx_unique_day_skill_req", unique: true
    t.index ["shift_month_id"], name: "index_shift_day_skill_requirements_on_shift_month_id"
  end

  create_table "shift_day_styles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "shift_day_setting_id", null: false
    t.integer "shift_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_day_setting_id", "shift_kind"], name: "index_shift_day_styles_on_shift_day_setting_id_and_shift_kind", unique: true
    t.index ["shift_day_setting_id"], name: "index_shift_day_styles_on_shift_day_setting_id"
  end

  create_table "shift_month_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.integer "required_number", default: 0, null: false
    t.integer "role", null: false
    t.integer "shift_kind", default: 0, null: false
    t.bigint "shift_month_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "shift_kind", "day_of_week", "role"], name: "idx_shift_month_requirements_unique", unique: true
    t.index ["shift_month_id"], name: "index_shift_month_requirements_on_shift_month_id"
  end

  create_table "shift_month_skill_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.integer "required_number", default: 0, null: false
    t.bigint "shift_month_id", null: false
    t.integer "skill"
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "day_of_week", "skill"], name: "idx_shift_month_skill_requirements_unique", unique: true
    t.index ["shift_month_id"], name: "index_shift_month_skill_requirements_on_shift_month_id"
  end

  create_table "shift_months", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "holiday_days"
    t.integer "month", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", null: false
    t.index ["organization_id"], name: "index_shift_months_on_organization_id"
    t.index ["user_id", "year", "month"], name: "index_shift_months_on_user_id_and_year_and_month", unique: true
    t.index ["user_id"], name: "index_shift_months_on_user_id"
  end

  create_table "staff_day_time_options", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "apply_wdays", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.integer "position", default: 1, null: false
    t.bigint "staff_id", null: false
    t.string "time_text", null: false
    t.datetime "updated_at", null: false
    t.index ["apply_wdays"], name: "index_staff_day_time_options_on_apply_wdays", using: :gin
    t.index ["staff_id", "active", "position"], name: "idx_sdto_staff_active_position"
    t.index ["staff_id"], name: "idx_sdto_unique_default_per_staff", unique: true, where: "(is_default = true)"
    t.index ["staff_id"], name: "index_staff_day_time_options_on_staff_id"
  end

  create_table "staff_holiday_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "shift_month_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_month_id", "staff_id", "date"], name: "idx_staff_holiday_requests_unique", unique: true
    t.index ["shift_month_id"], name: "index_staff_holiday_requests_on_shift_month_id"
    t.index ["staff_id"], name: "index_staff_holiday_requests_on_staff_id"
  end

  create_table "staff_unworkable_wdays", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wday", null: false
    t.index ["staff_id", "wday"], name: "index_staff_unworkable_wdays_on_staff_id_and_wday", unique: true
    t.index ["staff_id"], name: "index_staff_unworkable_wdays_on_staff_id"
  end

  create_table "staff_workable_wdays", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wday", null: false
    t.index ["staff_id", "wday"], name: "index_staff_workable_wdays_on_staff_id_and_wday", unique: true
    t.index ["staff_id"], name: "index_staff_workable_wdays_on_staff_id"
  end

  create_table "staffs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "assignment_policy", default: 0, null: false
    t.boolean "can_cook", default: false, null: false
    t.boolean "can_day", default: false, null: false
    t.boolean "can_drive", default: false, null: false
    t.boolean "can_early", default: false, null: false
    t.boolean "can_late", default: false, null: false
    t.boolean "can_night", default: false, null: false
    t.boolean "can_visit", default: false, null: false
    t.datetime "created_at", null: false
    t.string "first_name", null: false
    t.string "first_name_kana", null: false
    t.string "last_name", null: false
    t.string "last_name_kana", null: false
    t.bigint "occupation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "weekly_workdays"
    t.integer "workday_constraint", default: 0, null: false
    t.index ["active"], name: "index_staffs_on_active"
    t.index ["assignment_policy"], name: "index_staffs_on_assignment_policy"
    t.index ["occupation_id"], name: "index_staffs_on_occupation_id"
    t.index ["user_id"], name: "index_staffs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unconfirmed_email"], name: "index_users_on_unconfirmed_email"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "base_skill_requirements", "users"
  add_foreign_key "base_weekday_requirements", "users"
  add_foreign_key "shift_day_assignments", "shift_months"
  add_foreign_key "shift_day_assignments", "staff_day_time_options"
  add_foreign_key "shift_day_assignments", "staffs"
  add_foreign_key "shift_day_designations", "shift_months"
  add_foreign_key "shift_day_designations", "staffs"
  add_foreign_key "shift_day_requirements", "shift_months"
  add_foreign_key "shift_day_settings", "shift_months"
  add_foreign_key "shift_day_skill_requirements", "shift_months"
  add_foreign_key "shift_day_styles", "shift_day_settings"
  add_foreign_key "shift_month_requirements", "shift_months"
  add_foreign_key "shift_month_skill_requirements", "shift_months"
  add_foreign_key "shift_months", "organizations"
  add_foreign_key "shift_months", "users"
  add_foreign_key "staff_day_time_options", "staffs"
  add_foreign_key "staff_holiday_requests", "shift_months"
  add_foreign_key "staff_holiday_requests", "staffs"
  add_foreign_key "staff_unworkable_wdays", "staffs"
  add_foreign_key "staff_workable_wdays", "staffs"
  add_foreign_key "staffs", "occupations"
  add_foreign_key "staffs", "users"
  add_foreign_key "users", "organizations"
end
