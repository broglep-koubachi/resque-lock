module Resque
  module Plugins
    # If you want only one instance of your job queued at a time,
    # extend it with this module.
    #
    # For example:
    #
    # require 'resque/plugins/lock'
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::Lock
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    # No other UpdateNetworkGraph jobs will be placed on the queue,
    # the QueueLock class will check Redis to see if any others are
    # queued with the same arguments before queueing. If another
    # is queued the enqueue will be aborted.
    #
    # If you want to define the key yourself you can override the
    # `lock` class method in your subclass, e.g.
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::Lock
    #
    #   # Run only one at a time, regardless of repo_id.
    #   def self.lock(repo_id)
    #     "network-graph"
    #   end
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    # The above modification will ensure only one job of class
    # UpdateNetworkGraph is running at a time, regardless of the
    # repo_id. Normally a job is locked using a combination of its
    # class name and arguments.
    # 
    # It is also possible to define locks which will get released
    # BEFORE performing a job by overriding the lock_running? class
    # method in your subclass. This is useful in cases where you need
    # to get a job queued even if another job on same queue is already
    # running, e.g.
    # 
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::Lock
    #
    #   # Do not lock a running job
    #   def self.lock_running?
    #     false
    #   end
    # end
    module Lock
      # Override in your job to control the lock key. It is
      # passed the same arguments as `perform`, that is, your job's
      # payload.
      def lock(*args)
        "#{name}-#{args.to_s}"
      end

      def namespaced_lock(*args)
        "lock:#{lock(*args)}"
      end

      def before_enqueue_lock(*args)
        lock_key = namespaced_lock(*args)
        s = Resque.redis.setnx(lock_key, true)
        Resque.redis.expire(lock_key, lock_expire) if s
        return s
      end

      def before_dequeue_lock(*args)
        Resque.redis.del(namespaced_lock(*args))
      end

      def lock_expire
        30
      end

      def lock_running?
        true
      end

      def around_perform_lock(*args)
        before_dequeue_lock(*args) unless lock_running?
        begin
          yield
        ensure
          # Always clear the lock when we're done, even if there is an
          # error.
          before_dequeue_lock(*args) if lock_running?
        end
      end

      def self.all_locks
        Resque.redis.keys('lock:*')
      end
      def self.clear_all_locks
        all_locks.collect { |x| Resque.redis.del(x) }.count
      end
    end
  end
end

