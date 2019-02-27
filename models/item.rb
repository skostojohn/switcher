class Item < Sequel::Model
  many_to_one :job
end
