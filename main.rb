require 'active_support'
require 'active_support/core_ext'
require 'sucker_punch'
require 'sinatra/base'
require 'restforce'
require 'yaml'
require 'xmlsimple'
require 'cgi'
# require 'sqlite3'
require 'sequel'

class FetchWorkflowRuleWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, object)
    wruleids = client.query("select id from workflowrule where tableenumorid = '#{object}'")
    wrules = []
    wruleids.each do |wruleid|
      curr_rule = client.find('WorkflowRule', wruleid.Id)
      next unless curr_rule.Metadata['active']
      wrules.push(curr_rule)
      item = Item.new(type: 'WorkflowRule', job_id: job.id, sfdc_id: curr_rule.Id, created: DateTime.now,
                      name: curr_rule.Name, obj_hash: curr_rule.to_hash.to_json, status: 'active')
      item.save
    end
    job[:wr_status] = 'Complete'
    job.save
  end
end

class FetchValidationRuleWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, object)
    vruleids = client.query("select id from validationrule where entitydefinitionid = '#{object}'")
    vrules = []
    vruleids.each do |vruleid|
      curr_rule = client.find('ValidationRule', vruleid.Id)
      next unless curr_rule.Metadata['active']
      vrules.push(curr_rule)
      item = Item.new(type: 'ValidationRule', job_id: job.id, sfdc_id: curr_rule.Id, created: DateTime.now,
                      name: curr_rule.ValidationName, obj_hash: curr_rule.to_hash.to_json, status: 'active')
      item.save
    end
    job[:vr_status] = 'Complete'
    job.save
  end
end

class FetchProcessBuilderWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, object)
    active_flow_defs = client.query('select Id, ActiveVersionId from FlowDefinition where ActiveVersionId != null')
    process_builders = []
    active_flow_defs.each do |flow_def|
      curr_flow = client.find('Flow', flow_def.ActiveVersionId)
      next unless curr_flow.Metadata['processType'] == 'Workflow' && curr_flow.Metadata['processMetadataValues'].select { |x| x.name == 'ObjectType' }[0]['value']['stringValue'] == object
      process_builders.push(curr_flow) 
      item = Item.new(type: 'ProcessBuilder', job_id: job.id, sfdc_id: curr_flow.Id, created: DateTime.now,
                      name: curr_flow.Metadata['label'], obj_hash: curr_flow.to_hash.to_json, status: 'active')
      item.save
    end
    job[:pb_status] = 'Complete'
    job.save
  end
end

class UpdateWorkflowRuleWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, records, state)
    state_bool = state == 'active' ? true : false
    Item.where(sfdc_id: records).each do |item|
      wrule = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      result = client.update('WorkflowRule', Id: wrule.Id, Metadata: {  actions: wrule.Metadata['actions'],
                                                                        active: state_bool,
                                                                        booleanFilter: wrule.Metadata['booleanFilter'],
                                                                        criteriaItems: wrule.Metadata['criteriaItems'],
                                                                        description: wrule.Metadata['description'],
                                                                        formula: wrule.Metadata['formula'],
                                                                        fullName: wrule.Metadata['fullName'],
                                                                        triggerType: wrule.Metadata['triggerType'],
                                                                        workflowTimeTriggers: wrule.Metadata['workflowTimeTriggers'] })
      item.update(status: state) if result
    end
    job[:wr_status] = 'Complete'
    job.save
  end
end

class UpdateValidationRuleWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, records, state)
    state_bool = state == 'active' ? true : false
    Item.where(sfdc_id: records).each do |item|
      vrule = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      result = client.update!('ValidationRule', Id: vrule.Id, Metadata: { active: state_bool,
                                                description: vrule.Metadata['description'],
                                                errorConditionFormula: vrule.Metadata['errorConditionFormula'],
                                                errorDisplayField: vrule.Metadata['errorDisplayField'],
                                                errorMessage: vrule.Metadata['errorMessage'],
                                                fullName: vrule.Metadata['fullName'] })
      item.update(status: state) if result
    end
    job[:vr_status] = 'Complete'
    job.save
  end
end

class UpdateProcessBuilderWorker
  include SuckerPunch::Job
  autoload(:Item, './models/item.rb')

  def perform(job, client, records, state)
    Item.where(sfdc_id: records).each do |item|
      pb = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      avn = state == 'active' ? pb.VersionNumber : 0
      result = client.update!('FlowDefinition', Id: pb.DefinitionId, Metadata: { activeVersionNumber: avn })
      item.update(status: state) if result
    end
    job[:pb_status] = 'Complete'
    job.save
  end
end

class Switcher < Sinatra::Application
  autoload(:Job, './models/job.rb')
  autoload(:Item, './models/item.rb')

  def self.get_client(environment)
    config = YAML.load_file("/users/scottkostojohn/documents/source/training/switcher2/config/#{environment}.yaml")
    client = Restforce.tooling(username: config['username'],
                               password: config['password'],
                               security_token: config['securitytoken'],
                               client_id: config['clientid'],
                               client_secret: config['clientsecret'],
                               api_version: '41.0',
                               host: config['host'])
    client
  end

  configure do
    `rm jobs.db`
    # database = SQLite3::Database.new('jobs.db')
    # DB = Sequel.connect('sqlite://jobs.db')
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
    enable :sessions
  end

  get '/' do
    @environments = []
    Dir.glob('./config/*.yaml') do |file|
      @environments.push(file.scan(%r{/([a-z0-9\s]*)\.yaml$}i)[0][0])
    end
    erb :index
  end

  post '/objectlist' do
    session[:environment] = params[:environment]
    client = Switcher.get_client(params[:environment])
    @object_list = client.query('select masterlabel from entitydefinition where isworkflowenabled = true order by masterlabel')
    @curr_env = session[:environment]
    erb :objectlist
  end

  post '/automationlist' do
    @selected_object = params[:selected_object]
    job = Job.new(wr_status: 'New', vr_status: 'New', pb_status: 'New', created: DateTime.now)
    job.save
    session[:fetch_job_id] = job.id
    client = Switcher.get_client(session[:environment])
    FetchWorkflowRuleWorker.perform_async(job, client, @selected_object)
    FetchValidationRuleWorker.perform_async(job, client, @selected_object)
    FetchProcessBuilderWorker.perform_async(job, client, @selected_object)
    @curr_env = session[:environment]
    erb :automationlist
  end

  get '/automationlistitems' do
    job = Job[session[:fetch_job_id]]
    if job.wr_status == 'Complete' && job.vr_status == 'Complete' && job.pb_status == 'Complete'
      @workflow_rules = Item.where(type: 'WorkflowRule', job_id: job.id)
      @validation_rules = Item.where(type: 'ValidationRule', job_id: job.id)
      @process_builders = Item.where(type: 'ProcessBuilder', job_id: job.id)
    else halt 200
    end
    erb :automationlistitems, layout: false
  end

  post '/deactivated' do
    job = Job.new(wr_status: 'New', vr_status: 'New', pb_status: 'New', created: DateTime.now)
    job.save
    session[:deactivate_job_id] = job.id
    client = Switcher.get_client(session[:environment])
    wr_to_deactivate = params[:selected_wr]
    vr_to_deactivate = params[:selected_vr]
    pb_to_deactivate = params[:selected_pb]
    UpdateWorkflowRuleWorker.perform_async(job, client, wr_to_deactivate, 'inactive')
    UpdateValidationRuleWorker.perform_async(job, client, vr_to_deactivate, 'inactive')
    UpdateProcessBuilderWorker.perform_async(job, client, pb_to_deactivate, 'inactive')
    @curr_env = session[:environment]
    erb :deactivated
  end

  get '/deactivateditems' do
    fetch_job = Job[session[:fetch_job_id]]
    deactivate_job = Job[session[:deactivate_job_id]]
    if deactivate_job.wr_status == 'Complete' && deactivate_job.vr_status == 'Complete' && deactivate_job.pb_status == 'Complete'
      @workflow_rules = Item.where(type: 'WorkflowRule', status: 'inactive', job_id: fetch_job.id)
      @validation_rules = Item.where(type: 'ValidationRule', status: 'inactive', job_id: fetch_job.id)
      @process_builders = Item.where(type: 'ProcessBuilder', status: 'inactive', job_id: fetch_job.id)
    else halt 200
    end
    erb :deactivateditems, layout: false
  end

  post '/activated' do
    job = Job.new(wr_status: 'New', vr_status: 'New', pb_status: 'New', created: DateTime.now)
    job.save
    session[:activate_job_id] = job.id
    client = Switcher.get_client(session[:environment])
    wr_to_activate = params[:selected_wr]
    vr_to_activate = params[:selected_vr]
    pb_to_activate = params[:selected_pb]
    UpdateWorkflowRuleWorker.perform_async(job, client, wr_to_activate, 'active')
    UpdateValidationRuleWorker.perform_async(job, client, vr_to_activate, 'active')
    UpdateProcessBuilderWorker.perform_async(job, client, pb_to_activate, 'active')
    @curr_env = session[:environment]
    erb :activated
  end

  get '/activateditems' do
    fetch_job = Job[session[:fetch_job_id]]
    activate_job = Job[session[:activate_job_id]]
    if activate_job.wr_status == 'Complete' && activate_job.vr_status == 'Complete' && activate_job.pb_status == 'Complete'
      @workflow_rules = Item.where(type: 'WorkflowRule', job_id: fetch_job.id)
      @validation_rules = Item.where(type: 'ValidationRule', job_id: fetch_job.id)
      @process_builders = Item.where(type: 'ProcessBuilder', job_id: fetch_job.id)
    else halt 200
    end
    erb :activateditems, layout: false
  end

  run! if app_file == $PROGRAM_NAME
end
