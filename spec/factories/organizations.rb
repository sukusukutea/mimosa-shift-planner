FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "事業所#{n}" }
  end
end
