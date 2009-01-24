#--
# Copyright (c) 2007 Herryanto Siatono, Pluit Solutions
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'timeout'
require 'thread'
require 'logger'

module CommonPool
  class CommonPoolError < StandardError; end;
  
  # Pool configuration.
  class Configuration
    # Minimum number of idle objects in the pool. Default: 0.
    attr_accessor :min_idle
    
    # Maximum number of idle objects in the pool. Default: 8.
    attr_accessor :max_idle
    
    # Maximum idle time in seconds, before an object can be evicted. Default: 1800.
    attr_accessor :max_idle_time    
   
    # Maximum number of active objects in the pool. Default: 8.
    attr_accessor :max_active
    
    # Request timeout when creating object for the pool, timeout in seconds. Default: 60.
    # If set to 0 or less, there will be no timeout.
    attr_accessor :timeout
    
    # Request timeout when validation idle object in the pool, timeout in seconds. Default: 30.
    # If set to 0 or less, there will be no timeout.
    attr_accessor :validation_timeout
    
    # Number of objects to check per eviction thread run. Default: 3. 
    # If set to 0 or less, all idle objects will be checked.
    attr_accessor :idle_check_no_per_run
    
    # Eviction thread interval in seconds. Default: 0. 
    # If set to 0 or less, the eviction thread will not run.
    attr_accessor :idle_check_interval
   
    # Assign a logger, to log pool debug/info messages, used this for debugging purpose.
    attr_accessor :logger    
    
    # The data source object to be extended, code>create_object</code> method need to be 
    # overridden
    attr_accessor :data_source
    
    # Initilize configuration with default settings.
    def initialize
      self.min_idle           = 0
      self.max_idle           = 8
      self.max_idle_time      = 30 * 60
      self.max_active         = 8
      self.idle_check_no_per_run = 3
      self.idle_check_interval= 0
      self.timeout            = 60
      self.validation_timeout = 30
    end
    
    # Convert configuration properties to hash object.
    def to_hash
      { :timeout => self.timeout,
        :validation_tmeout => self.validation_timeout,
        :min_idle => self.min_idle,
        :max_idle => self.max_idle,
        :max_idle_time => self.max_idle_time,
        :max_active => self.max_active,
        :idle_check_no_per_run => self.idle_check_no_per_run,
        :idle_check_interval => self.idle_check_interval}
    end
  end

  # Data source for objects to be stored in the pool.
  class PoolDataSource
    # Override to create an object to be stored in the pool.
    def create_object
      raise CommonPoolError, "Overwrite this method to create an object to be stored in the pool."
    end
    
    # Override to check the validity of your idle object, called when idle object eviction stread.
    def valid?(object)
      true
    end
  end
  
  # First in, first out object pooling implementation.
  class ObjectPool
    attr_reader :active_list, :idle_list, :idle_check_thread, :idle_check_status
    attr_accessor :config, :data_source
    
    # Initialize pool instance with default configuration options. Override config as a parameter passed to the block.
    def initialize(data_source = nil, &proc)
      raise ArgumentError, "Data source is required." unless data_source      
      self.config = Configuration.new
      self.data_source = data_source
      @active_list          = {}
      @idle_list          = []
      @idle_check_status  = "Not Running"
      @mutex              = Mutex.new
      @cond               = ConditionVariable.new
      
      yield self.config if block_given?
      self.start_check_idle_thread
    end

    # Configure pool instance after initialization.
    def configure(&proc)
      yield self.config 
      self.start_check_idle_thread
    end

    # Alias for <code>check_idle_thread</code>.
    def start
      start_check_idle_thread
    end
    
    # Borrow object from the pool. If max number of active objects reached, <code>CommonPoolErrror</code> will be thrown.
    def borrow_object
      @mutex.synchronize {
        if !@idle_list.empty?
          result = @idle_list.shift
          
        elsif @active_list.size < @config.max_active
          result = create_with_timestamp
          
        elsif @active_list.size >= @config.max_active
          raise CommonPoolError, "Max number of %d active objects reached." % @config.max_active
          
        else
          begin
            timeout(@config.timeout){ @cond.wait(@mutex) }
          rescue TimeoutError
            raise TimeoutError, "#{@config.timeout} seconds request timeout reached."
          end
          result = @idle_list.shift
        end
        @active_list.store(result[1].__id__, result)
        
        logger.debug("* Get #{result[1]}") if logger
        result[1]
      }
    end
    
    # Return object back to the pool.
    def return_object(object)
      logger.debug("* Return #{object}") if logger
      return if object.nil?
      if @active_list.delete(object.__id__)
        add_to_idle_list(object)
      else
        logger.debug("Session #{object} not returned, coz has been invalidated from used list.") if logger
      end
    end
    
    # Invalidate object
    def invalidate_object(object)
      @mutex.synchronize {
        logger.debug("* Invalidate #{object}") if logger
        @active_list.delete(object.__id__)
        nil
      }
    end
    
    # Clear object pool, set the idle list and used list to empty.
    def clear()
      @mutex.synchronize {
        @idle_list = []
        @active_list = {}
      }
    end
    
    # Reset the max active objects in the pool.
    def max_active=(size)
      @mutex.synchronize {
        if @idle_list.size + @active_list.size > size
          raise ArgumentError, "Cannot change max size to %d. There are objects over the size." % size
        end
        @config.max_active = size
      }
      size
    end
    
    # Start check idle objects thread, will only run if <code>idle_check_interval</code> is greater than 0.
    def start_check_idle_thread
      @mutex.synchronize {
        return unless @config.idle_check_interval > 0 and @idle_check_thread.nil?
        @idle_check_status = "Checking..."
        
        @idle_check_thread = Thread.new do
          loop do
            thread_id = @idle_check_thread.__id__ if @idle_check_thread
            
            begin
              logger.debug(">> Starting idle objects check (Object ID: #{self.__id__}, Thread ID: #{thread_id})") if logger
              logger.debug("Status: " + self.status_info.map {|k,v| "#{k}=#{v}"}.join(', ')) if logger
              @idle_check_status = "Checking..."
              
              check_idle
              
              @idle_check_status = "Check status: OK. Sleeping now..."
            rescue Exception => e
              @idle_check_status = "Check status: Error - #{e.to_s} \n#{e.backtrace.join("\n")}. Sleeping...\n"
            end
            
            logger.debug(@idle_check_status) if logger
            if @config.idle_check_interval > 0 
              logger.debug(">> Sleeping (Object ID: #{self.__id__}, Thread ID: #{thread_id}) #{@config.idle_check_interval} seconds ...\n\n") if logger
              sleep @config.idle_check_interval
            else
              logger.debug(">> Idle check interval is set 0 or less. Thus idle check thread will only be executed once.") if logger
            end
          end
        end
      }
    end
    
    # Stop idle check thread
    def stop_idle_check_thread
      if @idle_check_thread 
        logger.debug(">> Stopping idle objects check thread ...") if logger
        @idle_check_status = "Stopping..."
        @idle_check_thread.kill
        @idle_check_thread = nil
        @idle_check_status = "Not Running"
      end
    end
    
    # Restart idle check thread
    def restart_check_idle_thread
      stop_idle_check_thread
      start_idle_check_thread
    end
    
    # Return a hash of active and idle objects size with pool instance configuration options.
    def status_info
      {:active_objects => @active_list.size,
       :idle_objects => @idle_list.size,
       :idle_check_status => @idle_check_status}.merge(self.config.to_hash)
    end
    
    # Check if an idle object is valid, return false if <code>validation_timeout</code> period reached.
    def valid_idle_object?(object)
      begin
        timeout(self.config.validation_timeout) do 
          self.data_source.valid?(object)
        end
      rescue TimeoutError => e
        logger.debug("Timeout #{@config.validation_timeout} seconds validating object: #{object}") if logger
        false
      end
    end
    
    protected
    
    def logger
      self.config.logger
    end
    
    def create_with_timestamp
      [Time.new, self.data_source.create_object]
    end
    
    def add_to_idle_list(object)
      @mutex.synchronize {
        if (@config.max_idle > 0) and (@idle_list.size >= @config.max_idle)
          logger.debug("Not returned, max idle #{@config.max_idle} reached") if logger
          return
        end
        
        logger.debug("* Add #{object}") if logger
        @idle_list.push([Time.new, object])
        @cond.signal
      }
    end
    
    def check_min_idle
      logger.debug("Minimum idle objects: #{@config.min_idle}, current idle size: #{@idle_list.size}") if logger
      return if (@config.min_idle < 1) || (@idle_list.size >= @config.min_idle)
      
      objects_to_create = @config.min_idle - @idle_list.size
      logger.debug("Creating additional #{objects_to_create} object(s).") if logger
      objects_to_create.times do
        add_to_idle_list(self.data_source.create_object)
      end
    end
    
    def check_idle
      logger.debug("Checking idle objects list size: #{@idle_list.size}, min idle: #{@config.min_idle}") if logger
      
      counter = 0
      checked_obj = []
      @idle_list.size.times do 
        break if (@config.idle_check_no_per_run > 0) and (counter >= @config.idle_check_no_per_run)
        
        counter += 1
        result = @idle_list.shift
        logger.debug("Checking idle object: #{result.join('|')}") if logger
        if result
          if (within_max_idle_time?(result[0]) && valid_idle_object?(result[1]))
            checked_obj.push(result)
          else 
            invalidate(result[1])
          end
        else
          logger.debug("No more object available.") if logger
        end
      end
      
      checked_obj.each {|result| @idle_list.push(result)}
      check_min_idle
    end
    
    def within_max_idle_time?(objtime)
      return true if (@config.max_idle_time < 0)
      
      seconds_passed = Time.now - objtime
      exceed_time = seconds_passed > @config.max_idle_time
      
      if (@config.max_idle_time == 0) || (exceed_time)
        logger.debug("Idle for #{seconds_passed} seconds, exceeded #{seconds_passed - @config.max_idle_time} seconds") if logger
        return false
      else
        return true
      end
    end
    
    def idle_check_status=(s)
      @config.idle_check_status = s
    end
  end
end
