class User < ApplicationRecord
  belongs_to :organization, optional: true # resource.vaild?でorganization_nameでチェックが走るのでoptinal:trueでOK
  has_many :staffs, dependent: :destroy
  has_many :shift_months, dependent: :destroy
  has_many :base_weekday_requirements, dependent: :destroy
  has_many :base_skill_requirements, dependent: :destroy

  attr_accessor :organization_name

  validates :name, presence: { message: "を入力してください"}
  validates :organization_name, presence: { message: "を入力してください"}, on: :create # フォーム用のエラーメッセージ
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable, :rememberable
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable, :confirmable, :lockable
end
