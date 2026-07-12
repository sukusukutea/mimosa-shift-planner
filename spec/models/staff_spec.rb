require "rails_helper"

RSpec.describe Staff, type: :model do
  describe "factory" do
    it "has a valid factory" do
      staff = build(:staff)
      expect(staff).to be_valid
    end
  end

  describe "validations" do
    it "last_name がないと無効" do
      staff = build(:staff, last_name: nil)
      expect(staff).to be_invalid
      expect(staff.errors[:last_name]).to be_present
    end

    it "first_name がないと無効" do
      staff = build(:staff, first_name: nil)
      expect(staff).to be_invalid
      expect(staff.errors[:first_name]).to be_present
    end

    it "last_name_kana がないと無効" do
      staff = build(:staff, last_name_kana: nil)
      expect(staff).to be_invalid
      expect(staff.errors[:last_name_kana]).to be_present
    end

    it "first_name_kana がないと無効" do
      staff = build(:staff, first_name_kana: nil)
      expect(staff).to be_invalid
      expect(staff.errors[:first_name_kana]).to be_present
    end

    it "last_name_kana がひらがな以外だと無効" do
      staff = build(:staff, last_name_kana: "ヤマダ")
      expect(staff).to be_invalid
      expect(staff.errors[:last_name_kana]).to be_present
    end

    it "first_name_kana がひらがな以外だと無効" do
      staff = build(:staff, first_name_kana: "ハナコ")
      expect(staff).to be_invalid
      expect(staff.errors[:first_name_kana]).to be_present
    end

    it "weekly のとき weekly_workdays があれば有効" do
      staff = build(:staff, workday_constraint: :weekly, weekly_workdays: 3)
      expect(staff).to be_valid
    end

    it "weekly のときweekly_workdays がないと無効" do
      staff = build(:staff, workday_constraint: :weekly, weekly_workdays: nil)
      expect(staff).to be_invalid
      expect(staff.errors[:weekly_workdays]).to be_present
    end

    it "free のとき weekly_workdays があると無効" do
      staff = build(:staff, workday_constraint: :free, weekly_workdays: 3)
      expect(staff).to be_invalid
      expect(staff.errors[:weekly_workdays]).to be_present
    end
  end

  describe "日勤表示登録のバリデーション" do
    it " デフォルトが２つあると無効" do
      staff = build(:staff)

      staff.staff_day_time_options.build(
        time_text: "8:30-17:30",
        position: 1,
        active: true,
        is_default: true,
        apply_wdays: []
      )

      staff.staff_day_time_options.build(
        time_text: "7:30-16:30",
        position: 2,
        active: true,
        is_default: true,
        apply_wdays: []
      )

      expect(staff).to be_invalid
      expect(staff.errors[:base]).to include("「デフォルト」は1つだけ選択してください")
    end

    it "曜日指定が重複すると無効" do
      staff = build(:staff)

      staff.staff_day_time_options.build(
        time_text: "8:30-17:30",
        position: 1,
        active: true,
        is_default: true,
        apply_wdays: [ 0, 1 ]
      )

      staff.staff_day_time_options.build(
        time_text: "7:30-16:30",
        position: 2,
        active: true,
        is_default: false,
        apply_wdays: [ 1, 2 ]
      )

      expect(staff).to be_invalid
      expect(staff.errors[:base]).to include("日勤表示登録の曜日指定が重複しています（火）。曜日は1つの時間だけに設定してください。")
    end

    it "デフォルトが１つで曜日重複がなければ有効" do
      staff = build(:staff)

      staff.staff_day_time_options.build(
        time_text: "8:30-17:30",
        position: 1,
        active: true,
        is_default: true,
        apply_wdays: [ 0, 1 ]
      )

      staff.staff_day_time_options.build(
        time_text: "7:30-16:30",
        position: 2,
        active: true,
        is_default: false,
        apply_wdays: [ 2, 3 ]
      )

      expect(staff).to be_valid
    end
  end
end
