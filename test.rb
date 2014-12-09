# Copyright (c) 2008-2012 Phusion
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'bundler/setup'
require 'minitest/autorun'
require 'active_record'
require 'active_support/dependencies'

if ActiveSupport::VERSION::MAJOR < 4
  require 'active_support/core_ext/logger'
end

begin
  TestCaseClass = MiniTest::Test
rescue NameError
  TestCaseClass = MiniTest::Unit::TestCase
end

require 'default_value_for'

puts "\nTesting with Active Record version #{ActiveRecord::VERSION::STRING}\n\n"

if RUBY_PLATFORM == "java"
  database_adapter = "jdbcsqlite3"
else
  database_adapter = "sqlite3"
end
ActiveRecord::Base.default_timezone = :local
ActiveRecord::Base.logger = Logger.new(STDERR)
ActiveRecord::Base.logger.level = Logger::WARN
ActiveRecord::Base.establish_connection(
  :adapter  => database_adapter,
  :database => ':memory:'
)
ActiveRecord::Base.connection.create_table(:users, :force => true) do |t|
  t.string :username
  t.integer :default_number
end
ActiveRecord::Base.connection.create_table(:numbers, :force => true) do |t|
  t.string :type
  t.integer :number
  t.integer :count, :null => false, :default => 1
  t.integer :user_id
  t.timestamp :timestamp
  t.text :stuff
  t.boolean :flag
end

if defined?(Rails::Railtie)
  DefaultValueFor.initialize_railtie
  DefaultValueFor.initialize_active_record_extensions
end

class User < ActiveRecord::Base
  has_many :numbers, :class_name => 'TestClass'
end

class Number < ActiveRecord::Base
end

class DefaultValuePluginTest < TestCaseClass

  # SCREAMING RED HOT TODO: Fix this
  i_suck_and_my_tests_are_order_dependent!

  def setup
    Number.create(:number => 9876)
  end

  def teardown
    Number.delete_all
  end

  def define_model_class(name = "TestClass", parent_class_name = "ActiveRecord::Base", &block)
    Object.send(:remove_const, name) rescue nil
    eval("class #{name} < #{parent_class_name}; end", TOPLEVEL_BINDING)
    klass = eval(name, TOPLEVEL_BINDING)
    klass.class_eval do
      if respond_to?(:table_name=)
        self.table_name = 'numbers'
      else
        set_table_name 'numbers'
      end
    end
    klass.class_eval(&block) if block_given?
  end

  def test_default_value_on_attribute_methods
    define_model_class do
      serialize :stuff
      default_value_for :color, :green
      def color; (self.stuff || {})[:color]; end
      def color=(val)
        self.stuff ||= {}
        self.stuff[:color] = val
      end
    end
    object = TestClass.create
    assert_equal :green, object.color
  end

  def test_default_value_can_be_passed_as_argument
    define_model_class do
      default_value_for(:number, 1234)
    end
    object = TestClass.new
    assert_equal 1234, object.number
  end

  def test_default_value_can_be_passed_as_block
    define_model_class do
      default_value_for(:number) { 1234 }
    end
    object = TestClass.new
    assert_equal 1234, object.number
  end

  def test_works_with_create
    define_model_class do
      default_value_for :number, 1234
    end

    object = TestClass.create
    refute_nil TestClass.find_by_number(1234)

    # allows nil for existing records
    object.update_attribute(:number, nil)
    assert_nil TestClass.find_by_number(1234)
    assert_nil TestClass.find(object.id).number
  end

  def test_does_not_allow_nil_for_existing_record
    define_model_class do
      default_value_for(:number, :allows_nil => false) { 1234 }
    end

    object = TestClass.create

    # allows nil for existing records
    object.update_attribute(:number, nil)
    assert_nil TestClass.find_by_number(1234)
    assert_equal 1234, TestClass.find(object.id).number
  end

   def test_overwrites_db_default
    define_model_class do
      default_value_for :count, 1234
    end
    object = TestClass.new
    assert_equal 1234, object.count
  end

  def test_doesnt_overwrite_values_provided_by_mass_assignment
    define_model_class do
      default_value_for :number, 1234
    end
    object = TestClass.new(:number => 1, :count => 2)
    assert_equal 1, object.number
  end

  def test_doesnt_overwrite_values_provided_by_multiparameter_assignment
    define_model_class do
      default_value_for :timestamp, Time.mktime(2000, 1, 1)
    end
    timestamp = Time.mktime(2009, 1, 1)
    object = TestClass.new('timestamp(1i)' => '2009', 'timestamp(2i)' => '1', 'timestamp(3i)' => '1')
    assert_equal timestamp, object.timestamp
  end

  def test_doesnt_overwrite_values_provided_by_constructor_block
    define_model_class do
      default_value_for :number, 1234
    end
    object = TestClass.new do |x|
      x.number = 1
      x.count = 2
    end
    assert_equal 1, object.number
  end

  def test_doesnt_overwrite_explicitly_provided_nil_values_in_mass_assignment
    define_model_class do
      default_value_for :number, 1234
    end
    object = TestClass.new(:number => nil)
    assert_equal nil, object.number
  end

  def test_overwrites_explicitly_provided_nil_values_in_mass_assignment
    define_model_class do
      default_value_for :number, :value => 1234, :allows_nil => false
    end
    object = TestClass.new(:number => nil)
    assert_equal 1234, object.number
  end

  def test_default_values_are_inherited
    define_model_class("TestSuperClass") do
      default_value_for :number, 1234
    end
    define_model_class("TestClass", "TestSuperClass")
    object = TestClass.new
    assert_equal 1234, object.number
  end

  def test_default_values_in_superclass_are_saved_in_subclass
    define_model_class("TestSuperClass") do
      default_value_for :number, 1234
    end
    define_model_class("TestClass", "TestSuperClass") do
      default_value_for :flag, true
    end
    object = TestClass.create!
    assert_equal object.id, TestClass.find_by_number(1234).id
    assert_equal object.id, TestClass.find_by_flag(true).id
  end

  def test_default_values_in_subclass
    define_model_class("TestSuperClass") do
    end
    define_model_class("TestClass", "TestSuperClass") do
      default_value_for :number, 5678
    end

    object = TestClass.new
    assert_equal 5678, object.number

    object = TestSuperClass.new
    assert_nil object.number
  end

  def test_multiple_default_values_in_subclass_with_default_values_in_parent_class
    define_model_class("TestSuperClass") do
      default_value_for :other_number, nil
      attr_accessor :other_number
    end
    define_model_class("TestClass", "TestSuperClass") do
      default_value_for :number, 5678

      # Ensure second call in this class doesn't reset _default_attribute_values,
      # and also doesn't consider the parent class' _default_attribute_values when
      # making that check.
      default_value_for :user_id, 9999
    end

    object = TestClass.new
    assert_nil object.other_number
    assert_equal 5678, object.number
    assert_equal 9999, object.user_id
  end

  def test_override_default_values_in_subclass
    define_model_class("TestSuperClass") do
      default_value_for :number, 1234
    end
    define_model_class("TestClass", "TestSuperClass") do
      default_value_for :number, 5678
    end

    object = TestClass.new
    assert_equal 5678, object.number

    object = TestSuperClass.new
    assert_equal 1234, object.number
  end

  def test_default_values_in_subclass_do_not_affect_parent_class
    define_model_class("TestSuperClass") do
      default_value_for :number, 1234
    end
    define_model_class("TestClass", "TestSuperClass") do
      default_value_for :hello, "hi"
      attr_accessor :hello
    end

    assert TestSuperClass.new
    assert !TestSuperClass._default_attribute_values.include?(:hello)
  end

  def test_doesnt_set_default_on_saved_records
    define_model_class do
      default_value_for :number, 1234
    end
    assert_equal 9876, TestClass.first.number
  end

  def test_also_works_on_attributes_that_arent_database_columns
    define_model_class do
      default_value_for :hello, "hi"
      attr_accessor :hello
    end
    object = TestClass.new
    assert_equal 'hi', object.hello
  end

  if ActiveRecord::VERSION::MAJOR < 4
    def test_constructor_ignores_forbidden_mass_assignment_attributes
      define_model_class do
        default_value_for :number, 1234
        attr_protected :number
      end
      object = TestClass.new(:number => 5678, :count => 987)
      assert_equal 1234, object.number
      assert_equal 987, object.count
    end

    def test_constructor_respects_without_protection_option
      define_model_class do
        default_value_for :number, 1234
        attr_protected :number

        def respond_to_mass_assignment_options?
          respond_to? :mass_assignment_options
        end
      end

      if TestClass.new.respond_to_mass_assignment_options?
        # test without protection feature if available in current ActiveRecord version
        object = TestClass.create!({:number => 5678, :count => 987}, :without_protection => true)
        assert_equal 5678, object.number
        assert_equal 987, object.count
      end
    end
  end

  def test_doesnt_conflict_with_overrided_initialize_method_in_model_class
    define_model_class do
      def initialize(attrs = {})
        @initialized = true
        super(:count => 5678)
      end

      default_value_for :number, 1234
    end
    object = TestClass.new
    assert_equal 1234, object.number
    assert_equal 5678, object.count
    assert object.instance_variable_get('@initialized')
  end

  def test_model_instance_is_passed_to_the_given_block
    $instance = nil
    define_model_class do
      default_value_for :number do |n|
        $instance = n
      end
    end
    object = TestClass.new
    assert_same object, $instance
  end

  def test_can_specify_default_value_via_association
    user = User.create(:username => 'Kanako', :default_number => 123)
    define_model_class do
      belongs_to :user

      default_value_for :number do |n|
        n.user.default_number
      end
    end
    object = user.numbers.create
    assert_equal 123, object.number
  end

  def test_default_values
    define_model_class do
      default_values :type => "normal",
        :number => lambda { 10 + 5 },
        :timestamp => lambda {|_| Time.now }
    end

    object = TestClass.new
    assert_equal("normal", object.type)
    assert_equal(15, object.number)
  end

  def test_default_value_order
    define_model_class do
      default_value_for :count, 5
      default_value_for :number do |this|
        this.count * 2
      end
    end
    object = TestClass.new
    assert_equal(5, object.count)
    assert_equal(10, object.number)
  end

  def test_attributes_with_default_values_are_not_marked_as_changed
    define_model_class do
      default_value_for :count, 5
      default_value_for :number, 2
    end

    object = TestClass.new
    assert(!object.changed?)
    assert_equal([], object.changed)

    object.type = "foo"
    assert(object.changed?)
    assert_equal(["type"], object.changed)
  end

  def test_default_values_are_duplicated
    define_model_class do
      if respond_to?(:table_name=)
        self.table_name = "users"
      else
        set_table_name "users"
      end
      default_value_for :username, "hello"
    end
    user1 = TestClass.new
    user1.username << " world"
    user2 = TestClass.new
    assert_equal("hello", user2.username)
  end

  def test_default_values_are_shallow_copied
    define_model_class do
      if respond_to?(:table_name=)
        self.table_name = "users"
      else
        set_table_name "users"
      end
      attr_accessor :hash
      default_value_for :hash, { 1 => [] }
    end
    user1 = TestClass.new
    user1.hash[1] << 1
    user2 = TestClass.new
    assert_equal([1], user2.hash[1])
  end

  def test_constructor_does_not_affect_the_hash_passed_to_it
    define_model_class do
      default_value_for :count, 5
    end

    options = { :count => 5, :user_id => 1 }
    options_dup = options.dup
    object = TestClass.new(options)
    assert_equal(options_dup, options)
  end

  def test_subclass_find
    define_model_class do
      default_value_for :number, 5678
    end
    define_model_class("SpecialNumber", "TestClass")
    n = SpecialNumber.create
    assert SpecialNumber.find(n.id)
  end

  def test_does_not_see_false_as_blank_at_boolean_columns_for_existing_records
    define_model_class do
      default_value_for(:flag, :allows_nil => false) { true }
    end

    object = TestClass.create

    # allows nil for existing records
    object.update_attribute(:flag, false)
    assert_equal false, TestClass.find(object.id).flag
  end
end
