# frozen_string_literal: true

module SimpleUniqueJobs
  class Lock
    TimeoutError = Class.new(StandardError)

    KEY_PREFIX = "unique"
    KEY_PATTERN = "%<prefix>s:%<type>s:%<key>s"

    def initialize(job, redis_pool)
      @job = job
      @redis_pool = redis_pool
    end

    def if_enqueueable
      return if queued_unique_for > 0 && !lock("q", queued_unique_for)

      yield
    end

    def unlock_enqueue
      unlock("q")
    end

    def if_runnable(&)
      return yield if running_unique_for == 0
      return unless lock("r", running_unique_for)

      begin
        with_timeout(&)
      ensure
        unlock("r")
      end
    end

    private

    def lock(type, timeout)
      @redis_pool.with do |redis|
        !!redis.set(key_for(type), "x", nx: true, px: (timeout * 1e3).to_i)
      end
    end

    def unlock(type)
      @redis_pool.with do |redis|
        redis.del(key_for(type))
      end
    end

    def with_timeout(&)
      return yield unless running_timeout

      Timeout::timeout(running_unique_for, TimeoutError, &)
    end

    def queued_unique_for
      @queued_unique_for ||= @job.dig("unique_for", "queued").to_f
    end

    def running_unique_for
      @running_unique_for ||= @job.dig("unique_for", "running").to_f
    end

    def running_timeout
      @running_timeout ||= @job.dig("unique_for", "timeout")
    end

    def key_for(type)
      format(KEY_PATTERN, prefix: KEY_PREFIX, type:, key: @job.fetch('unique_key'))
    end
  end
end
