ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'rack/test'
require_relative '../main'
require 'sucker_punch/testing/inline'

reporter_options = { color: true, slow_count: 5 }
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(reporter_options)]

class AppTest < MiniTest::Test
  include Rack::Test::Methods

  i_suck_and_my_tests_are_order_dependent!

  def app
    Switcher
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
    Restforce::Tooling::Client.stub_any_instance(:query, [rf_response]) do
      post '/objectlist', environment: 'Redis Sandbox'
      assert last_response.ok?
      assert_includes last_response.body, 'Account'
      refute_includes last_response.body, 'Contact'
    end
  end

  def test_automation_list
    post '/automationlist', { selected_object: 'Account' }, 'rack.session' => { environment: 'Redis Sandbox' }
    assert last_response.ok?
    assert Job.count == 1
  end

  def test_automation_list_items
    job = Job.first
    get '/automationlistitems', {}, 'rack.session' => { environment: 'Redis Sandbox', fetch_job_id: job.id }
    assert last_response.ok?
  end
end
