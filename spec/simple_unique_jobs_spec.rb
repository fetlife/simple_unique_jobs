# frozen_string_literal: true
require 'spec_helper'
require 'pry'
require 'sidekiq'
# require 'sidekiq/testing'

TimeoutError = Class.new(StandardError)

RSpec.describe SimpleUniqueJobs do
  it "has a version number" do
    expect(SimpleUniqueJobs::VERSION).not_to be nil
  end

  def client_config = Sidekiq.configure_client { |config| config }
  def server_config = Sidekiq.configure_server { |config| config }

  def wait_until(timeout: 5)
    start_time = Time.now
    until yield
      if (Time.now - start_time) > timeout
        raise TimeoutError, "Execution expired"
      end
      sleep 0.05
    end
  end

  after do
    # Reset Sidekiq state
    # $stderr.puts "Resetting Sidekiq state"
    Sidekiq.instance_eval do
      %i[@config @config_blocks @frozen].each do |var|
        remove_instance_variable(var) if instance_variable_defined?(var)
      end
    end
  end

  context 'in client mode' do
    it "sets up client middleware" do
      expect { SimpleUniqueJobs.setup }.to change { client_config.client_middleware.entries.count }.by(1)
    end
  end

  context 'in server mode' do
    before do
      allow(Sidekiq).to receive(:server?).and_return(true)
    end

    it "sets up client middleware" do
      expect { SimpleUniqueJobs.setup }.to change { server_config.client_middleware.entries.count }.by(1)
    end

    it "sets up server middleware" do
      expect { SimpleUniqueJobs.setup }.to change { server_config.server_middleware.entries.count }.by(1)
    end
  end

  context 'with a worker' do

    class TestWorker
      include Sidekiq::Worker
      @@worker_performed = []

      sidekiq_options queue: "test", unique_for: { queued: 10, running: 10 }

      def perform(arg)
        # $stderr.puts "TestWorker: #{arg}"
        @@worker_performed << arg
      end

      def self.performed
        @@worker_performed
      end
    end

    let(:embedded_sidekiq) {
      Sidekiq.configure_embed { |c|
        c.queues = ["test"]
        c.concurrency = 1
      }
    }

    before do
      TestWorker.performed.clear
      SimpleUniqueJobs.setup
      embedded_sidekiq.logger.level = Logger::ERROR
      embedded_sidekiq.run
    end

    after do
      embedded_sidekiq.stop
      Sidekiq.redis(&:flushdb)
    end

    it "runs a single job" do
      TestWorker.perform_async("foo")
      wait_until { TestWorker.performed.length > 0 }
      expect(TestWorker.performed).to eq(["foo"])
    end

    it 'does not run an already-enqueued job' do
      TestWorker.perform_in(5, "foo")
      TestWorker.perform_bulk([["foo"], ["bar"]])
      wait_until { TestWorker.performed.length > 0 }
      expect(TestWorker.performed).to eq(["bar"])
    end

    it 'runs identical jobs sequentially' do
      TestWorker.perform_async("foo")
      wait_until { TestWorker.performed.length == 1 }
      TestWorker.perform_async("foo")
      wait_until { TestWorker.performed.length == 2 }
      expect(TestWorker.performed).to eq(["foo", "foo"])
    end

    it 'runs distinct jobs in parallel' do
      TestWorker.perform_bulk([["foo"], ["bar"]])
      wait_until { TestWorker.performed.length == 2 }
      expect(TestWorker.performed).to eq(["foo", "bar"])
    end

    it 'runs only one of identical jobs in parallel' do
      TestWorker.perform_bulk([["foo"], ["foo"], ["bar"]])
      wait_until { TestWorker.performed.length == 2 }
      expect(TestWorker.performed).to eq(["foo", "bar"])
    end

    it 'runs a job if the enqueue lock expires' do
      TestWorker.perform_in(60, "foo")
      Sidekiq.redis { |r| r.del(*r.keys("unique:q:*")) }
      TestWorker.perform_async("foo")
      wait_until { TestWorker.performed.length > 0 }
      expect(TestWorker.performed).to eq(["foo"])
    end
  end
end