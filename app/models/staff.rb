class Staff < ApplicationRecord
  belongs_to :occupation
  belongs_to :user
  has_many :shift_day_assignments, dependent: :restrict_with_exception # 間違ってdestroyしてもRails側で止める
  has_many :staff_workable_wdays, dependent: :destroy
  has_many :shift_day_designations, dependent: :restrict_with_exception
  has_many :staff_unworkable_wdays, dependent: :destroy
  has_many :staff_day_time_options, -> { order(:position) }, dependent: :destroy
  has_one  :default_day_time_option,
         -> { where(is_default: true) },
         class_name: "StaffDayTimeOption"

  accepts_nested_attributes_for :staff_day_time_options,
                                allow_destroy: true,
                                reject_if: ->(attrs) do
                                  time_blank = attrs["time_text"].blank?
                                  active_on  = ActiveModel::Type::Boolean.new.cast(attrs["active"])
                                  default_on = ActiveModel::Type::Boolean.new.cast(attrs["is_default"])
                                  destroy_on = ActiveModel::Type::Boolean.new.cast(attrs["_destroy"])

                                  # 削除は通す（rejectしない）
                                  next false if destroy_on

                                  # 「時間空」かつ「active/default もOFF」の行だけ無視する
                                  time_blank && !active_on && !default_on
                                end

  enum :workday_constraint, { free: 0, fixed: 1, weekly: 2 }
  enum :assignment_policy, { candidate: 0, required: 1 }

  def ng_wday?(date)
    return false if date.nil?

    wday = ShiftMonth.ui_wday(date)
    staff_unworkable_wdays.where(wday: wday).exists?
  end

  scope :active, -> { where(active: true) }

  validates :last_name,     presence: true
  validates :first_name,    presence: true
  validates :last_name_kana,
            presence: true,
            format: {
              with: /\A[ぁ-んー]+\z/,
              message: "はひらがなで入力してください"
            }

  validates :first_name_kana,
            presence: true,
            format: {
              with: /\A[ぁ-んー]+\z/,
              message: "はひらがなで入力してください"
            }

  validates :weekly_workdays,
            presence: true,
            inclusion: { in: 1..7 },
            if: :weekly?
  validates :weekly_workdays,
            absence: true,
            unless: :weekly?

  validate :only_one_day_time_default_in_form
  validate :day_time_option_apply_wdays_must_not_overlap

  class << self
    def human_attribute_name(attr, options = {})
      key = attr.to_s

      # accepts_nested_attributes_for 経由のエラーで
      # "staff_day_time_options.time_text" のようなドット付きが来るので、
      # 翻訳が効く underscore 形式へ寄せる
      if key.start_with?("staff_day_time_options.")
        key = key.tr(".", "_") # staff_day_time_options_time_text へ
      end

      super(key, options)
    end
  end

  def only_one_day_time_default_in_form
    return unless staff_day_time_options.loaded? || staff_day_time_options.any?

    defaults =
      staff_day_time_options.reject(&:marked_for_destruction?)
                            .select { |o| ActiveModel::Type::Boolean.new.cast(o.is_default) }

    return if defaults.size <= 1

    errors.add(:base, "「デフォルト」は1つだけ選択してください")
  end

  def day_time_option_apply_wdays_must_not_overlap
    opts =
      staff_day_time_options
        .reject(&:marked_for_destruction?)
        .select { |o| Array(o.apply_wdays).reject(&:blank?).any? }

    return if opts.size <= 1

    used = {} # { wday_int => option_id }
    wday_labels = %w[月 火 水 木 金 土 日]

    opts.each do |opt|
      Array(opt.apply_wdays).reject(&:blank?).map(&:to_i).uniq.each do |w|
        next unless (0..6).include?(w)

        if used.key?(w)
          errors.add(:base, "日勤表示登録の曜日指定が重複しています（#{wday_labels[w]}）。曜日は1つの時間だけに設定してください。")
          return
        end

        used[w] = opt.id || :new
      end
    end
  end
end
