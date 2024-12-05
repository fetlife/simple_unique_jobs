# frozen_string_literal: true

require "spec_helper"
require "pry"
require "sidekiq"

TimeoutError = Class.new(StandardError)

class TestWorker
  include Sidekiq::Worker
  @@worker_performed = []
  @@worker_started = []

  sidekiq_options queue: "test",
                  unique_for: { queued: 10, running: 10 },
                  unique_on: lambda(&:first)

  def perform(key, options = {})
    @@worker_started << key
    sleep options['wait'] if options['wait']
  ensure
    @@worker_performed << key
  end

  def self.performed
    @@worker_performed
  end

  def self.started
    @@worker_started
  end

  def self.clear
    @@worker_performed.clear
    @@worker_started.clear
  end
end

RSpec.describe SimpleUniqueJobs do
  # We need to reach inside Sidekiq internals to reset its state
  after do
    Sidekiq.instance_eval do
      %i[@config @config_blocks @frozen].each do |var|
        remove_instance_variable(var) if instance_variable_defined?(var)
      end
    end
  end

  it "has a version number" do
    expect(SimpleUniqueJobs::VERSION).not_to be_nil
  end

  def client_config = Sidekiq.configure_client { |config| config }

  def server_config = Sidekiq.configure_server { |config| config }

  def wait_until(timeout: 5)
    start_time = Time.now
    until yield
      raise TimeoutError, "Execution expired" if (Time.now - start_time) > timeout

      sleep 0.05
    end
  end


  context "when in client mode" do
    it "sets up client middleware" do
      expect { described_class.setup }.to change { client_config.client_middleware.entries.count }.by(1)
    end
  end

  context "when in server mode" do
    before do
      allow(Sidekiq).to receive(:server?).and_return(true)
    end

    it "sets up client middleware" do
      expect { described_class.setup }.to change { server_config.client_middleware.entries.count }.by(1)
    end

    it "sets up server middleware" do
      expect { described_class.setup }.to change { server_config.server_middleware.entries.count }.by(1)
    end
  end

  context "with a real Sidekiq executor" do
    let(:embedded_sidekiq) do
      Sidekiq.configure_embed do |c|
        c.queues = ["test"]
        c.concurrency = 3
      end
    end

    before do
      TestWorker.clear
      described_class.setup
      embedded_sidekiq.logger.level = Logger::ERROR
      embedded_sidekiq.run
    end

    after do
      embedded_sidekiq.stop
      Sidekiq.redis(&:flushdb)
    end

    it "runs a single job" do
      TestWorker.perform_async("foo")
      wait_until { !TestWorker.performed.empty? }
      expect(TestWorker.performed).to eq(["foo"])
    end

    context 'with enqueue lock only' do
      before do
        TestWorker.sidekiq_options unique_for: { queued: 10 }
      end

      it "does not run an already-enqueued job" do
        TestWorker.perform_in(5, "foo")
        TestWorker.perform_bulk([["foo"], ["bar"]])
        wait_until { !TestWorker.performed.empty? }
        expect(TestWorker.performed).to eq(["bar"])
      end

      it "runs identical jobs sequentially" do
        TestWorker.perform_async("foo", "n" => 1)
        wait_until { TestWorker.performed.length == 1 }
        TestWorker.perform_async("foo", "n" => 2)
        wait_until { TestWorker.performed.length == 2 }
        expect(TestWorker.performed).to eq(%w[foo foo])
      end

      it "runs distinct jobs in parallel" do
        TestWorker.perform_bulk([["foo", { "n" => 1 }], ["bar", { "n" => 2 }]])
        wait_until { TestWorker.performed.length == 2 }
        expect(TestWorker.performed).to match_array(%w[foo bar])
      end

      it "runs only one of identical jobs in parallel" do
        TestWorker.perform_bulk([["foo", { "n" => 1 }], ["foo", { "n" => 2 }], ["bar", { "n" => 3 }]])
        wait_until { TestWorker.performed.length == 2 }
        expect(TestWorker.performed).to match_array(%w[foo bar])
      end

      it "runs a job if the enqueue lock expires" do
        TestWorker.perform_in(60, "foo")
        Sidekiq.redis { |r| r.del(*r.keys("unique:q:*")) }
        TestWorker.perform_async("foo")
        wait_until { !TestWorker.performed.empty? }
        expect(TestWorker.performed).to eq(["foo"])
      end
    end

    context 'with running lock only' do
      before { TestWorker.sidekiq_options unique_for: { running: 2 } }

      it "does not run an already-running job" do
        TestWorker.perform_async("foo", "n" => 1, "wait" => 1)
        wait_until { !TestWorker.started.empty? }
        TestWorker.perform_async("foo", "n" => 2, "wait" => 1)
        TestWorker.perform_async("bar")
        wait_until { TestWorker.performed.length == 2 }
        expect(TestWorker.performed).to match_array(%w[foo bar])
      end

      context 'when a job runs too long' do
        before { TestWorker.sidekiq_options unique_for: { running: 0.5 } }

        it 'runs jobs concurrently' do
          TestWorker.perform_async("foo", "n" => 1, "wait" => 2)
          wait_until { TestWorker.started.length > 0 }
          sleep 0.6
          TestWorker.perform_async("foo", "n" => 2, "wait" => 2)
          wait_until { TestWorker.performed.length == 2 }
          expect(TestWorker.performed).to match_array(%w[foo foo])
        end
      end
    end
  end
end
