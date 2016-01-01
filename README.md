== common-pool

First in first out (FIFO) object pooling mechanism with idle objects eviction check, similar with {Apache Common Pool}[link:http://jakarta.apache.org/commons/pool/].

It supports the following configuration parameters:
* min_idle
* max_idle
* max_idle_time
* max_active
* timeout
* validation_timeout
* idle_check_no_per_run
* idle_check_interval

Overwrite <code>CommonPool::PoolDataSource</code> to create object to be returned to the pool.

== Installation

  $ gem install common-pool

== Example

  require 'common_pool'    
  
  # Extend data source object
  class RandomNumberDataSource < CommonPool::PoolDataSource
    # Overwrite to return object to be stored in the pool.
    def create_object
      rand(1000)
    end
    
    # Overwrite to check if idle object in the pool is still valid.
    def valid?(object)
      true
    end
  end
  
  # Create a new object pool
  object_pool = ObjectPool.new(RandomNumberDataSource.new)
  
  # Borrow object from the pool
  object = object_pool.borrow_object

  # Return object to the pool
  object_pool.return_object(object)
  
  # Or invalidate object and remove it from the pool
  object_pool.invalidate_object(object)
  
  # Create object pool with idle objects eviction thread
  object_pool = ObjectPool.new(RandomNumberDataSource.new) do |config|
    config.min_idle = 5
    config.max_idle = 10
  
    # max 10 idle objects checked per run
    config.idle_check_no_per_run = 10

    # check idle objects every 10 minutes
    config.idle_check_interval = 10 * 60
  end

  # Return a hash of pool instance status variables, i.e.
  # active and idle lists size, and configuration options
  object_pool.status_info

== Source Codes
http://github.com/jugend/common-pool/tree/master

== Links
* http://www.pluitsolutions.com/common-pool
  
  
