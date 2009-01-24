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

require File.dirname(__FILE__) + '/../lib/common_pool'

class CommonPoolTest < Test::Unit::TestCase
  include CommonPool
  
  def test_get_and_release_session_pool
    # test get sessions from pool
    pool = create_pool
  
    session_a = pool.borrow_object
    session_b = pool.borrow_object
    
    assert_not_equal session_a, session_b
    assert_equal 2, pool.active_list.size
    assert_equal 0, pool.idle_list.size
    
    pool.return_object(session_a)
    pool.return_object(session_b)
    assert_equal 0, pool.active_list.size
    assert_equal 2, pool.idle_list.size
  end
  
  def test_first_in_first_out
    pool = create_pool
    session_a = pool.borrow_object
    session_b = pool.borrow_object
    
    pool.return_object(session_b)
    pool.return_object(session_a)
    
    session_new = pool.borrow_object
    assert_equal session_b, session_new
  end
  
  def test_max_active_reached
    pool = create_pool    
    until pool.active_list.size == pool.config.max_active
      obj = pool.borrow_object
    end
    
    begin
      # max active reached, relase object to retrieve a new one
      pool.return_object(obj)
      wait_obj = pool.borrow_object
      assert_equal obj, wait_obj
    end
  end
  
  def test_timeout_reached
    pool = create_pool do |config|
      config.timeout = 1
    end
    
    until pool.active_list.size == pool.config.max_active
      obj = pool.borrow_object
    end

    # max active reached wait till timeout
    assert_raise(CommonPoolError) do
      wait_obj = pool.borrow_object
    end
  end
  
  def test_invalidate
    pool = create_pool
    session_a = pool.borrow_object
    session_b = pool.borrow_object
    
    assert_equal 2, pool.active_list.size
    assert_equal 0, pool.idle_list.size
    
    pool.invalidate_object(session_a)
    assert_equal 1, pool.active_list.size
    assert_equal 0, pool.idle_list.size
    
    pool.return_object(session_b)
    assert_equal 0, pool.active_list.size
    assert_equal 1, pool.idle_list.size
    
    session_new = pool.borrow_object
    assert_equal session_new, session_b
  end
 
  
  def test_check_min_idle
    pool = create_pool do |config|
      config.min_idle = 2
      config.idle_check_interval = 60
    end
        
    # sleep to let the pool populate
    until pool.idle_check_status.match(/Sleeping/)
      sleep 2
    end
    
    assert_equal 2, pool.idle_list.size
  end
  
  def test_check_max_idle
    pool = create_pool do |config|
      config.min_idle = 0
      config.max_idle = 2
      config.idle_check_interval = 60
    end
    
    a = pool.borrow_object
    b = pool.borrow_object
    c = pool.borrow_object
    
    # idle will keep up to 2
    pool.return_object(a)
    pool.return_object(b)
    assert_equal 2, pool.idle_list.size
    
    # throw away no 3
    pool.return_object(c)
    assert_equal 2, pool.idle_list.size
  end  
  
#  def test_run
#    pool = create_pool do |config|
#      config.debug = true
#      config.min_idle = 2
#      config.max_active = 3
#      config.max_idle_time = 15
#      config.idle_check = true
#      config.idle_check_interval = 3
#    end
#    
#    pool.idle_check_thread.join
#  end
  
  protected
    class TestDataSource < PoolDataSource
      def create_object
        rand(1000)
      end
    end
  
    def create_pool(&proc)
      pool = ObjectPool.new(TestDataSource.new) do |config|
        config.logger = Logger.new(STDOUT)
        yield config if block_given?        
      end
    end
end