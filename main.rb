require 'active_support'
require 'active_support/core_ext'
require 'sucker_punch'
require 'sinatra/base'
require 'restforce'
require 'yaml'
require 'xmlsimple'
require 'cgi'
require_relative 'models/init'
require_relative 'workers'

class Switcher < Sinatra::Application

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
