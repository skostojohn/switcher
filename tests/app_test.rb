ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require_relative '../main'
require_relative 'stub_responses'
require 'sucker_punch/testing/inline'
require 'mocha/minitest'

reporter_options = { color: true, slow_count: 5 }
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(reporter_options)]

class AppTest < MiniTest::Test
  include Rack::Test::Methods

  def app
    Switcher
  end

  def setup
    DB[:items].truncate(cascade: true, restart: true)
    DB[:jobs].truncate(cascade: true, restart: true)
  end

  def test_index
    get '/'
    assert last_response.ok?
  end

  def test_objectlist
    rf_response = Object.new
    def rf_response.MasterLabel
      'Account'
    end
    Restforce::Tooling::Client.any_instance.stubs(:query).returns([rf_response])
    post '/objectlist', environment: 'Redis Sandbox'
    assert last_response.ok?
    assert_includes last_response.body, 'Account'
    refute_includes last_response.body, 'Contact'
  end

  def test_automation_list
    client = Switcher.get_client('Redis Sandbox')
    wrule_item = Restforce::SObject.build(JSON.parse(WRULE), client)
    vrule_item = Restforce::SObject.build(JSON.parse(VRULE), client)
    pb_item = Restforce::SObject.build(JSON.parse(PROCESS_BUILDER), client)
    FetchWorkflowRuleWorker.any_instance.stubs(:get_ids).returns(WRULEIDS)
    FetchWorkflowRuleWorker.any_instance.stubs(:get_item).returns(wrule_item)
    FetchValidationRuleWorker.any_instance.stubs(:get_ids).returns(VRULEIDS)
    FetchValidationRuleWorker.any_instance.stubs(:get_item).returns(vrule_item)
    FetchProcessBuilderWorker.any_instance.stubs(:get_ids).returns(ACTIVEFLOWDEFS)
    FetchProcessBuilderWorker.any_instance.stubs(:get_item).returns(pb_item)
    post '/automationlist', { selected_object: 'Account' }, 'rack.session' => { environment: 'Redis Sandbox' }
    assert last_response.ok?
    assert Job.count == 1
    assert Item.count == 3
  end

  def test_automation_list_items
    jobs = DB[:jobs]
    jobs.insert(wr_status: 'New', vr_status: 'New', pb_status: 'New', created: DateTime.now)
    job = Job.first
    get '/automationlistitems', {}, 'rack.session' => { environment: 'Redis Sandbox', fetch_job_id: job.id }
    assert last_response.ok?
  end

  def test_deactivated
    jobs = DB[:jobs]
    items = DB[:items]
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    job = Job.first
    items.insert(id: 1, type: 'WorkflowRule', name: 'Upgrade or Downgrade Customer', sfdc_id: '01QD0000000UTYQMA4', obj_hash: WRULE, created: DateTime.now, status: 'active', job_id: job.id)
    items.insert(id: 2, type: 'ValidationRule', name: 'Check_CompanyId_Value', sfdc_id: '03dD0000000k9fUIAQ', obj_hash: VRULE, created: DateTime.now, status: 'active', job_id: job.id)
    items.insert(id: 3, type: 'ProcessBuilder', name: 'Update Account Number of Employees', sfdc_id: '3010E000000PwqUQAS', obj_hash: PROCESS_BUILDER, created: DateTime.now, status: 'active', job_id: job.id)
    UpdateWorkflowRuleWorker.any_instance.stubs(:update_object).returns(true)
    UpdateValidationRuleWorker.any_instance.stubs(:update_object).returns(true)
    UpdateProcessBuilderWorker.any_instance.stubs(:update_object).returns(true)
    post '/deactivated', { selected_wr: ['01QD0000000UTYQMA4'], selected_vr: ['03dD0000000k9fUIAQ'],
                           selected_pb: ['3010E000000PwqUQAS'] }, 'rack.session' => { environment: 'Redis Sandbox' }
    assert last_response.ok?
    assert_includes last_response.body, 'The Switcher'
    assert Job.count == 2
    assert Item.where(status: 'inactive').count == 3
  end

  def test_deactivated_items
    jobs = DB[:jobs]
    items = DB[:items]
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    fetch_job = Job.first
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    deactivate_job = Job.last
    items.insert(id: 1, type: 'WorkflowRule', name: 'Upgrade or Downgrade Customer', sfdc_id: '01QD0000000UTYQMA4', obj_hash: WRULE, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    items.insert(id: 2, type: 'ValidationRule', name: 'Check_CompanyId_Value', sfdc_id: '03dD0000000k9fUIAQ', obj_hash: VRULE, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    items.insert(id: 3, type: 'ProcessBuilder', name: 'Update Account Number of Employees', sfdc_id: '3010E000000PwqUQAS', obj_hash: PROCESS_BUILDER, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    get '/deactivateditems', {}, 'rack.session' => { environment: 'Redis Sandbox', fetch_job_id: fetch_job.id,
                                                     deactivate_job_id: deactivate_job.id }
    assert last_response.ok?
    assert_includes last_response.body, 'Upgrade'
  end

  def test_activated
    jobs = DB[:jobs]
    items = DB[:items]
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    fetch_job = Job.first
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    deactivate_job = Job.last
    items.insert(id: 1, type: 'WorkflowRule', name: 'Upgrade or Downgrade Customer', sfdc_id: '01QD0000000UTYQMA4', obj_hash: WRULE, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    items.insert(id: 2, type: 'ValidationRule', name: 'Check_CompanyId_Value', sfdc_id: '03dD0000000k9fUIAQ', obj_hash: VRULE, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    items.insert(id: 3, type: 'ProcessBuilder', name: 'Update Account Number of Employees', sfdc_id: '3010E000000PwqUQAS', obj_hash: PROCESS_BUILDER, created: DateTime.now, status: 'inactive', job_id: fetch_job.id)
    UpdateWorkflowRuleWorker.any_instance.stubs(:update_object).returns(true)
    UpdateValidationRuleWorker.any_instance.stubs(:update_object).returns(true)
    UpdateProcessBuilderWorker.any_instance.stubs(:update_object).returns(true)
    post '/activated', { selected_wr: ['01QD0000000UTYQMA4'], selected_vr: ['03dD0000000k9fUIAQ'],
                         selected_pb: ['3010E000000PwqUQAS'] }, 'rack.session' => { environment: 'Redis Sandbox' }
    assert last_response.ok?
    assert_includes last_response.body, "The Switcher"
    assert Item.where(status: 'active').count == 3
    assert Job.count == 3
  end

  def test_activated_items
    jobs = DB[:jobs]
    items = DB[:items]
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    fetch_job = Job.first
    jobs.insert(wr_status: 'Complete', vr_status: 'Complete', pb_status: 'Complete', created: DateTime.now)
    activate_job = Job.last
    items.insert(id: 1, type: 'WorkflowRule', name: 'Upgrade or Downgrade Customer', sfdc_id: '01QD0000000UTYQMA4',
                 obj_hash: WRULE, created: DateTime.now, status: 'active', job_id: fetch_job.id)
    items.insert(id: 2, type: 'ValidationRule', name: 'Check_CompanyId_Value', sfdc_id: '03dD0000000k9fUIAQ',
                 obj_hash: VRULE, created: DateTime.now, status: 'active', job_id: fetch_job.id)
    items.insert(id: 3, type: 'ProcessBuilder', name: 'Update Account Number of Employees', sfdc_id: '3010E000000PwqUQAS',
                 obj_hash: PROCESS_BUILDER, created: DateTime.now, status: 'active', job_id: fetch_job.id)
    get '/activateditems', {}, 'rack.session' => { environment: 'Redis Sandbox', fetch_job_id: fetch_job.id,
                                                   activate_job_id: activate_job.id }
    assert last_response.ok?
    assert_includes last_response.body, 'Upgrade'
    assert_includes last_response.body, 'Check_CompanyId_Value'
    assert_includes last_response.body, 'Account Number'
  end
end
