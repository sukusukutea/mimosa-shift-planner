require "rails_helper"

RSpec.describe StaffDayTimeOption, type: :model do
  describe "factory" do
    it "staffがあれば有効" do
      option = described_class.new(
        staff: create(:staff),
        time_text: "8:30-17:30",
        active: true,
        is_default: true,
        position: 1,
        apply_wdays: []
      )

      expect(option).to be_valid
    end
  end

  describe "validations" do
    it "active時はtime_text必須" do
      option = described_class.new(
        staff: create(:staff),
        time_text: nil,
        active: true,
        is_default: false
      )

      expect(option).to be_invalid
      expect(option.errors[:time_text]).to be_present
    end

    it "time_text形式が不正だと無効" do
      option = described_class.new(
        staff: create(:staff),
        time_text: "abc",
        active: true
      )

      expect(option).to be_invalid
      expect(option.errors[:time_text]).to be_present
    end
  end

  describe "default制約" do
    it "defaultなのにactive=falseだと無効" do
      option = described_class.new(
        staff: create(:staff),
        time_text: "8:30-17:30",
        active: false,
        is_default: true
      )

      expect(option).to be_invalid
      expect(option.errors[:is_default]).to be_present
    end
  end

  describe "apply_wdays(曜日指定) バリデーション" do
    it "曜日が範囲外だと無効" do
      option = described_class.new(
        staff: create(:staff),
        time_text: "8:30-17:30",
        active: true,
        apply_wdays: [ 7 ]
      )

      expect(option).to be_invalid
      expect(option.errors[:apply_wdays]).to be_present
    end

    it "曜日が範囲内なら有効" do
      option = described_class.new(
        staff: create(:staff),
        time_text: "8:30-17:30",
        active: true,
        apply_wdays: [ 0, 1, 2 ]
      )

      expect(option).to be_valid
    end
  end
end
