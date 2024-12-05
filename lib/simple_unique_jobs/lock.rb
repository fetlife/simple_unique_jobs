# frozen_string_literal: true

require "murmurhash3"
module SimpleUniqueJobs
  class Lock
    KEY_PREFIX = "unique"
    KEY_PATTERN = "%<prefix>s:%<type>s:%<classname>s:%<hash>s"

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

    def if_runnable
      return yield if running_unique_for == 0
      return unless lock("r", running_unique_for)

      begin
        yield
      ensure
        unlock("r")
      end
    end

    private

    def lock(type, timeout)
      @redis_pool.with do |redis|
        !!redis.set(key_for(type), "x", nx: true, ex: timeout)
      end
    end

    def unlock(type)
      @redis_pool.with do |redis|
        redis.del(key_for(type))
      end
    end

    def queued_unique_for
      @queued_unique_for ||= @job.dig("unique_for", "queued").to_i
    end

    def running_unique_for
      @running_unique_for ||= @job.dig("unique_for", "running").to_i
    end

    def classname
      @job["class"]
    end

    def args
      @job["args"]
    end

    def key_for(type)
      format(KEY_PATTERN, prefix: KEY_PREFIX, type:, classname:, hash: args_hash)
    end

    def args_hash
      @args_hash ||= MurmurHash3::V128.str_hexdigest(args.to_s)
    end
  end
end
