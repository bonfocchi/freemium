require File.dirname(__FILE__) + '/../test_helper'

class SubscriptionCouponTest < Test::Unit::TestCase
  fixtures :subscriptions, :credit_cards, :subscription_plans, :users
  
  def setup
    @subscription = subscriptions(:bobs_subscription)
    @original_price = @subscription.rate
    @coupon = Coupon.create(:description => "30% off", :discount_percentage => 30)
  end
  
  def test_apply
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
  end  

  def test_apply_using_coupon_accessor
    @subscription = build_subscription(:coupon => @coupon, :credit_card => CreditCard.sample)    
    @subscription.save!
    assert_not_nil @subscription.coupon
    assert_not_nil @subscription.subscription_coupons.first.coupon
    assert_not_nil @subscription.subscription_coupons.first.subscription
    assert !@subscription.subscription_coupons.empty?
    assert_equal (@subscription.subscription_plan.rate * 0.7).cents, @subscription.rate.cents
  end

  def test_apply_multiple
    @coupon = Coupon.new(:description => "10% off", :discount_percentage => 10)
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    
    @coupon = Coupon.new(:description => "30% off", :discount_percentage => 30)
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    
    @coupon = Coupon.new(:description => "20% off", :discount_percentage => 20)
    assert @subscription.subscription_coupons.create(:coupon => @coupon)

    # Should use the highest discounted coupon
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
  end  
  
  def test_destroy
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
    
    @coupon.destroy
    @subscription.reload
    assert @subscription.subscription_coupons.empty?
    assert_equal @original_price.cents, @subscription.rate.cents
  end
  
  def test_do_not_survive_plan_change
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
    
    assert @subscription.subscription_plan != subscription_plans(:premium)
    @subscription.subscription_plan = subscription_plans(:premium)
    @subscription.save!
    
    @subscription.reload
    assert @subscription.subscription_coupons.empty?
  end  
  
  def test_coupon_duration
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
    
    @coupon.duration_in_months = 3
    @coupon.save!
    
    safe_date = Date.today + 3.months - 1
    Date.stubs(:today).returns(safe_date)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
    
    safe_date = Date.today + 1
    Date.stubs(:today).returns(safe_date)
    assert_equal (@original_price * 0.7).cents, @subscription.rate.cents
    
    safe_date = Date.today + 1
    Date.stubs(:today).returns(safe_date)
    assert_equal @original_price.cents, @subscription.rate.cents
  end  
  
  def test_apply_complimentary
    @coupon.discount_percentage = 100
    assert @subscription.subscription_coupons.create(:coupon => @coupon)
    assert_equal 0, @subscription.rate.cents
    assert !@subscription.paid?
  end  
  
  ##
  ## Plan-specific coupons
  ##
  
  def test_apply_premium_only_coupon_on_new
    set_coupon_to_premium_only
    
    @subscription = build_subscription(:coupon => @coupon, :credit_card => CreditCard.sample, :subscription_plan => subscription_plans(:premium))
    
    assert @subscription.save
    assert_not_nil @subscription.coupon
  end

  def test_apply_premium_only_coupon_on_existing
    set_coupon_to_premium_only

    @subscription.coupon = @coupon    
    @subscription.subscription_plan = subscription_plans(:premium)
    
    assert @subscription.save
    assert_not_nil @subscription.coupon
  end  
  
  def test_invalid_apply_premium_only_coupon_on_new
    set_coupon_to_premium_only
    
    @subscription = build_subscription(:coupon => @coupon, :credit_card => CreditCard.sample, :subscription_plan => subscription_plans(:basic))
    
    assert !@subscription.save
    assert !@subscription.errors.on(:subscription_coupons).empty?
  end  
  
  def test_invalid_apply_premium_only_coupon_on_existing
    set_coupon_to_premium_only
    
    assert @subscription.subscription_plan != subscription_plans(:premium)
    @subscription.coupon = @coupon
    
    assert !@subscription.save
    assert !@subscription.errors.on(:subscription_coupons).empty?
  end  
  
  ##
  ## apply_coupon!
  ##
  
  def test_apply_coupon
    assert_nothing_raised do @subscription.apply_coupon!(@coupon) end
    assert_not_nil @subscription.coupon
  end

  def test_apply_invalid_coupon
    set_coupon_to_premium_only
    assert_raise ActiveRecord::RecordInvalid do
      @subscription.apply_coupon!(@coupon)
    end
  end
  
  protected
  
  def set_coupon_to_premium_only
    @coupon.subscription_plans << subscription_plans(:premium)
    @coupon.save!
  end


  public
  
  ##
  ## Validation Tests
  ##
  
  def test_invalid_no_coupon
    s = SubscriptionCoupon.new(:subscription => subscriptions(:bobs_subscription))
    assert !s.save
    assert !s.errors.on(:coupon).empty?
  end  



  def test_invalid_cannot_apply_to_unpaid_subscription
    assert !subscriptions(:sues_subscription).paid?
    s = SubscriptionCoupon.new(:subscription => subscriptions(:sues_subscription), :coupon => @coupon)
    assert !s.save
    assert !s.errors.on(:subscription).empty?
  end
  
  def test_invalid_cannot_apply_twice
    s = SubscriptionCoupon.new(:subscription => subscriptions(:bobs_subscription), :coupon => @coupon)
    assert s.save
    
    s = SubscriptionCoupon.new(:subscription => subscriptions(:bobs_subscription), :coupon => @coupon)
    assert !s.save
    assert !s.errors.on(:coupon_id).empty?    
  end
  
  def test_invalid_redemption_expired
    @coupon.redemption_expiration = Date.today-1
    @coupon.save!
    
    s = SubscriptionCoupon.new(:subscription => subscriptions(:bobs_subscription), :coupon => @coupon)
    assert !s.save
    assert !s.errors.on(:coupon).empty?    
  end
  
  def test_invalid_too_many_redemptions
    @coupon.redemption_limit = 1
    @coupon.save!
    
    s = SubscriptionCoupon.new(:subscription => subscriptions(:bobs_subscription), :coupon => @coupon)
    s.save!
    
    s = SubscriptionCoupon.new(:subscription => subscriptions(:steves_subscription), :coupon => @coupon)
    assert !s.save
    assert !s.errors.on(:coupon).empty?    
  end

  protected

  def build_subscription(options = {})
    Subscription.new({
      :subscription_plan => subscription_plans(:basic),
      :subscribable => users(:sue)
    }.merge(options))    
  end  
  
end