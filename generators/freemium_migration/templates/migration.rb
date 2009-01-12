class CreateSubscriptionAndPlan < ActiveRecord::Migration
  def self.up    
    create_table :freemium_subscription_plans, :force => true do |t|
      t.column :name, :string, :null => false
      t.column :key, :string, :null => false
      t.column :rate_cents, :integer, :null => false
      t.column :feature_set_id, :string, :null => false
    end

    create_table :freemium_subscriptions, :force => true do |t|
      t.column :subscribable_id, :integer, :null => false
      t.column :subscribable_type, :string, :null => false
      t.column :billing_key, :string, :null => true
      t.column :credit_card_id, :integer, :null => true
      t.column :subscription_plan_id, :integer, :null => false
      t.column :paid_through, :date, :null => true
      t.column :expire_on, :date, :null => true
      t.column :billing_key, :string, :null => true
      t.column :started_on, :date, :null => true
      t.column :last_transaction_at, :datetime, :null => true
    end

    create_table :freemium_credit_cards, :force => true do |t|
      t.column :display_number, :string, :null => false
      t.column :card_type, :string, :null => false
      t.column :expiration_date, :timestamp, :null => false
    end  

    create_table :freemium_coupons, :force => true do |t|  
      t.column :description, :string, :null => false
      t.column :discount_percentage, :integer, :null => false 
      t.column :redemption_limit, :integer, :null => true 
      t.column :redemption_expiration, :date, :null => true
      t.column :duration_in_months, :integer, :null => true
    end

    create_table :freemium_coupons_subscription_plans, :id => false, :force => true do |t|
      t.column :coupon_id, :integer, :null => false
      t.column :subscription_plan_id, :integer, :null => false
    end  

    create_table :freemium_coupon_redemptions, :force => true do |t|  
      t.column :subscription_id, :integer, :null => false
      t.column :coupon_id, :integer, :null => false 
      t.column :redeemed_on, :date, :null => false 
      t.column :expired_on, :date, :null => true
    end   

    # for applying transactions from automated recurring billing
    add_index :subscription_plans, :key
    
    # for polymorphic association queries
    add_index :subscriptions, :subscribable_id
    add_index :subscriptions, :subscribable_type
    
    # for finding due, pastdue, and expiring subscriptions
    add_index :subscriptions, :paid_through
    add_index :subscriptions, :expire_on

    # for applying transactions from automated recurring billing
    add_index :subscriptions, :billing_key    
    
    add_index :coupons_subscription_plans, :coupon_id
    add_index :coupons_subscription_plans, :subscription_plan_id
    
    add_index :coupon_redemptions, :subscription_id    
  end

  def self.down
    drop_table :freemium_subscription_plans
    drop_table :freemium_subscriptions
    drop_table :freemium_credit_cards
    drop_table :freemium_coupons
    drop_table :freemium_coupons_subscription_plans
    drop_table :freemium_coupon_redemptions
  end
end
