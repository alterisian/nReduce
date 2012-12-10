require 'spec_helper'

describe Response do
  before :each do
    @startup = FactoryGirl.create(:startup)
    @startup2 = FactoryGirl.create(:startup2)
    @user = FactoryGirl.create(:user, :startup => @startup)
    @user2 = FactoryGirl.create(:user2, :startup => @startup2)
    @account = Account.create_for_owner(@startup)
    @account.balance = 10
    @account.save
    @account2 = Account.create_for_owner(@startup2)
    @ui_ux_request = FactoryGirl.create(:ui_ux_request, :startup => @startup, :user => @user)

    @response = Response.new
    @response.request = @ui_ux_request
    @response.user = @user2
    @response_data = []
    @response.questions.each do
      @response_data << 'Sample Response'
    end
  end

  describe "responding to a request" do
    it "should allow you to respond to a request and reduce # of open slots on request" do
      prev_num = @ui_ux_request.num
      @response.save.should be_true
      @response.started?.should be_true
      @ui_ux_request.reload
      @ui_ux_request.num.should == prev_num - 1
    end

    it "should allow the responder to complete a request" do
      @response.save
      @response.data = @response_data
      @response.complete!.should be_true
      @response.status.should == [:completed]
    end

    it "should allow the responder to cancel a response" do
      @response.save
      @response.cancel!.should be_true
      @response.status.should == [:canceled]
      @response.canceled?.should be_true
    end

    it "should allow the requestor to approve a request and pay responder" do
      @account2.balance.should == 0
      @account.reload
      @account.escrow.should == 10
      @response.save
      prev_num = @ui_ux_request.reload.num

      # Complete & accept request
      @response.data = @response_data
      @response.complete!.should be_true
      @response.accept!.should be_true
      @response.status.should == [:accepted]

      # Number of people shouldn't change - already removed
      @ui_ux_request.reload
      @ui_ux_request.num.should == prev_num
      @account.reload
      @account2.reload

      # User should be paid
      @account.escrow.should == 5
      @account2.balance.should == 5
    end

    it "should allow the requestor to reject a request" do
      prev_num = @ui_ux_request.reload.num
      @response.save
      @response.data = @response_data
      @response.complete!.should be_true
      @response.reject!("I didn't see you actually load the website").should be_true
      @response.status.should == [:rejected]
      @ui_ux_request.reload
      @ui_ux_request.num.should == prev_num
    end

    it "should allow the system to expire an incompleted request" do
      prev_num = @ui_ux_request.num
      @response.save # start request but don't complete it
      @response.expire!.should be_true
      @response.status.should == [:expired]
      @ui_ux_request.reload
      @ui_ux_request.num.should == prev_num
    end

    it "shouldn't allow the system to expire a completed request" do
      @response.save
      @response.data = @response_data
      @response.complete!.should be_true
      @response.expire!.should be_false
      @response.status.should == [:completed]
      @response.expired_at.should be_nil
    end
  end
end