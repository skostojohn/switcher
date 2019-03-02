require 'sequel'
DB = Sequel.connect(adapter: :postgres, database: 'switcher', host: 'localhost', user: 'scottkostojohn')
DB.drop_table?(:items)
DB.drop_table?(:jobs)
DB.create_table :jobs do
  primary_key :id
  String :wr_status
  String :vr_status
  String :pb_status
  Timestamp :created
end
DB.create_table :items do
  primary_key :id
  String    :type
  String    :name
  String    :sfdc_id
  Text      :obj_hash
  Timestamp  :created
  String    :status
  foreign_key :job_id, :jobs
end
require_relative 'job'
require_relative 'item'