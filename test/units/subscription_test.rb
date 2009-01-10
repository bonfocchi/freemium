require File.dirname(__FILE__) + '/../test_helper'

class SubscriptionTest < Test::Unit::TestCase
  fixtures :users, :subscriptions, :subscription_plans, :credit_cards

  def test_associations
    assert_equal users(:bob), subscriptions(:bobs_subscription).subscribable
    assert_equal subscription_plans(:basic), subscriptions(:bobs_subscription).subscription_plan
  end

  def test_remaining_days
    assert_equal 20, subscriptions(:bobs_subscription).remaining_days
  end

  def test_remaining_value
    assert_equal Money.new(840), subscriptions(:bobs_subscription).remaining_value
  end

  ##
  ## Validations
  ##

  def test_creating_subscription
    subscription = build_subscription
    subscription.save!
    assert !subscription.new_record?, subscription.errors.full_messages.to_sentence
  end

  def test_missing_fields
    [:subscription_plan, :subscribable].each do |field|
      subscription = build_subscription(field => nil)
      subscription.save
      assert subscription.new_record?
      assert subscription.errors.on(field)
    end
  end

  ##
  ## Receiving payment
  ##

  def test_receive_monthly_payment
    subscription = subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.receive_payment!(subscription_plans(:basic).rate)
    assert_equal (paid_through >> 1).to_s, subscription.paid_through.to_s, "extended by one month"
  end

  def test_receive_quarterly_payment
    subscription = subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.receive_payment!(subscription_plans(:basic).rate * 3)
    assert_equal (paid_through >> 3).to_s, subscription.paid_through.to_s, "extended by three months"
  end

  def test_receive_partial_payment
    subscription = subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.receive_payment!(subscription_plans(:basic).rate * 0.5)
    assert_equal (paid_through + 15).to_s, subscription.paid_through.to_s, "extended by 15 days"
  end

  def test_receiving_payment_sends_invoice
    ActionMailer::Base.deliveries = []
    subscriptions(:bobs_subscription).receive_payment!(subscription_plans(:basic).rate)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  ##
  ## Requiring Credit Cards ...
  ##

  def test_requiring_credit_card_for_pay_plan
    subscription = build_subscription(:subscription_plan => subscription_plans(:premium))
    subscription.stubs(:credit_card).returns(nil)
    subscription.valid?
    assert subscription.errors.on(:credit_card)
  end

  def test_requiring_credit_card_for_free_plan
    subscription = build_subscription
    subscription.expects(:credit_card).never
    subscription.valid?
    assert !subscription.errors.on(:credit_card)
  end

  ##
  ## Expiration
  ##

  def test_instance_expire
    Freemium.expired_plan_key = :free
    Freemium.gateway.expects(:cancel).once.returns(nil)
    ActionMailer::Base.deliveries = []
    subscriptions(:bobs_subscription).expire!

    assert_equal 1, ActionMailer::Base.deliveries.size, "notice is sent to user"
    assert_equal subscription_plans(:free), subscriptions(:bobs_subscription).subscription_plan, "subscription is downgraded to free"
    assert_nil subscriptions(:bobs_subscription).billing_key, "billing key is thrown away"
    assert_nil subscriptions(:bobs_subscription).reload.billing_key, "billing key is thrown away"
  end

  def test_class_expire
    Freemium.expired_plan_key = :free
    subscriptions(:bobs_subscription).update_attributes(:paid_through => Date.today - 4, :expire_on => Date.today)
    ActionMailer::Base.deliveries = []
    assert_equal subscription_plans(:basic), subscriptions(:bobs_subscription).subscription_plan
    Subscription.expire
    assert_equal subscription_plans(:free), subscriptions(:bobs_subscription).reload.subscription_plan
    assert ActionMailer::Base.deliveries.size > 0
  end

  def test_expire_after_grace_sends_warning
    ActionMailer::Base.deliveries = []
    subscriptions(:bobs_subscription).expire_after_grace!
    assert_equal 1, ActionMailer::Base.deliveries.size
  end
  def test_expire_after_grace
    assert_nil subscriptions(:bobs_subscription).expire_on
    subscriptions(:bobs_subscription).paid_through = Date.today - 1
    subscriptions(:bobs_subscription).expire_after_grace!
    assert_equal Date.today + Freemium.days_grace, subscriptions(:bobs_subscription).reload.expire_on
  end

  def test_expire_after_grace_with_remaining_paid_period
    subscriptions(:bobs_subscription).paid_through = Date.today + 1
    subscriptions(:bobs_subscription).expire_after_grace!
    assert_equal Date.today + 1 + Freemium.days_grace, subscriptions(:bobs_subscription).reload.expire_on
  end

  def test_grace_and_expiration
    assert_equal 3, Freemium.days_grace, "test assumption"

    subscription = Subscription.new(:paid_through => Date.today + 5)
    assert !subscription.in_grace?
    assert !subscription.expired?

    # a subscription that's pastdue but hasn't been flagged to expire yet.
    # this could happen if a billing process skips, in which case the subscriber
    # should still get a full grace period beginning from the failed attempt at billing.
    # even so, the subscription is "in grace", even if the grace period hasn't officially started.
    subscription = Subscription.new(:paid_through => Date.today - 5)
    assert subscription.in_grace?
    assert !subscription.expired?

    # expires tomorrow
    subscription = Subscription.new(:paid_through => Date.today - 5, :expire_on => Date.today + 1)
    assert_equal 0, subscription.remaining_days_of_grace
    assert subscription.in_grace?
    assert !subscription.expired?

    # expires today
    subscription = Subscription.new(:paid_through => Date.today - 5, :expire_on => Date.today)
    assert_equal -1, subscription.remaining_days_of_grace
    assert !subscription.in_grace?
    assert subscription.expired?
  end

  ##
  ## Deleting (possibly from a cascading delete, such as User.find(5).delete)
  ##

  def test_deleting_cancels_in_gateway
    Freemium.gateway.expects(:cancel).once.returns(nil)
    subscriptions(:bobs_subscription).destroy
  end

  ##
  ## The Subscription#credit_card= shortcut
  ##
  def test_adding_a_credit_card
    subscription = build_subscription(:subscription_plan => subscription_plans(:premium))
    cc = CreditCard.example
    response = Freemium::Response.new(true)
    response.billing_key = "alphabravo"
    Freemium.gateway.expects(:store).with(cc).returns(response)

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_equal "alphabravo", subscription.billing_key
  end

  def test_updating_a_credit_card
    subscription = ::Subscription.find(:first, :conditions => "billing_key IS NOT NULL")
    cc = CreditCard.example
    response = Freemium::Response.new(true)
    response.billing_key = "new code"
    Freemium.gateway.expects(:update).with(subscription.billing_key, cc).returns(response)

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_equal "new code", subscription.billing_key, "catches any change to the billing key"
  end
  
  def test_updating_an_expired_credit_card
    subscription = ::Subscription.find(:first, :conditions => "billing_key IS NOT NULL")    
    cc = CreditCard.example
    response = Freemium::Response.new(true)
    Freemium.gateway.expects(:update).with(subscription.billing_key, cc).returns(response)

    subscription.expire_on = Time.now
    assert subscription.save
    assert_not_nil subscription.reload.expire_on

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_nil subscription.expire_on
    assert_nil subscription.reload.expire_on
  end  

  def test_failing_to_add_a_credit_card
    subscription = build_subscription(:subscription_plan => subscription_plans(:premium))
    cc = CreditCard.example
    response = Freemium::Response.new(false)
    Freemium.gateway.expects(:store).returns(response)
    
    subscription.credit_card = cc
    assert_raises Freemium::CreditCardStorageError do subscription.save! end
  end

  protected

  def build_subscription(options = {})
    Subscription.new({
      :subscription_plan => subscription_plans(:free),
      :subscribable => users(:sue)
    }.merge(options))    
  end
  
end