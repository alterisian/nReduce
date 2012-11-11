class Call < ActiveRecord::Base
  #
  # idea: send calendar invite to mentor after scheduling
  #

  # attr_accessible :title, :body
  bitmask :status, :as => [:scheduled, :completed, :canceled, :from_ignored, :to_ignored]
  bitmask :scheduled_state, :as => [:asked, :day, :time, :completed, :declined]

  @queue = :calls

  def self.scheduled_call_states
    Call.values_for_scheduled_state
  end

  # Send sms message chain to user to get time
  def self.schedule_with_user(user)
    c = Call.new
    c.from_user = from_user
  end

  # Got a response from a user, need to identify what step they are at and send appropriate message/collect data
  def self.respond_to_message(phone, message)
    # First get their user state
    user = User.find_by_phone(phone)
    call = Call.current_call_for_user(user)

    resend = false
    # Save data if necessary
    case self.scheduled_state.first
    when :asked
      if message.downcase.include?('y')
        self.scheduled_state = :day
      elsif message.downcase.include?('n')
        self.scheduled_state = :declined
      else
        # didn't recognize the response, send message again
        resend = true
      end
    when :day
      if message.blank?
        resend = true
      else
        self.data = message.strip
        self.scheduled_state = :time
      end
    when :time
      if message.blank?
        resend = true
      else
        # set scheduled at
        if self.set_scheduled_at_from_string(self.data, self.message.strip) == false
          resend = true
        else
          self.scheduled_state = :completed
        end
      end
    when :completed
      # somehow got triggered again, just ignore
    else
      # unrecognized state
    end
    self.save
    self.send_message_for_state(resend)
  end

  # Gets the call if they are the 'from' user
  def self.current_call_for_user(user)
    Call.where(:user_id => user.id).order('created_at DESC').limit(1)
  end

  # Translates number to US int'l number if not already
  def self.intl(phone)
    return "+1#{phone}" if phone.size == 10
    return phone
  end

  # Sets the scheduled at time for this week from a string, ex: Th 500pm
  # Need to accomodate for user's time zone
  def set_scheduled_at_from_string(day, time)
    begin
      day_of_week = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'].index(day.downcase)
      tmp_time = "#{time[0..(time.size - 3)]} #{time.last(2)}"
      puts tmp_time
      beginning = Time.now.beginning_of_week
      tmp_time = Time.parse("#{beginning.year}-#{beginning.month}-#{beginning.day} #{tmp_time}")
      time = tmp_time + day_of_week.days
      return self.scheduled_at = time
    rescue
      #
    end
    false
  end

  # Schedule this call in the future
  def schedule_with(to_user, duration = 20)
    self.to_user = to_user
    self.duration = duration
    self.save
    self
  end

  # Sends a message to the user for this current state
  def send_message_for_state(resend = false)
    msg = case self.scheduled_state.first
      when :asked then 'What time would you like your call?'
      when :day then 'What day works for you? Enter one: Mo Tu We Th Fr Sa Su'
      when :time then 'What time works for you? ex: 800am or 330pm'
      when :completed then "Thanks! Your call has been scheduled at #{self.scheduled_at}"
      else
    end
    msg = "Sorry didn't catch that. #{msg}" if resend
    TwilioClient.account.sms.messages.create(:from => Settings.twilio.intl_phone, :to => Call.intl(user.phone), :body => msg)
  end

  # Send reminder to people receiving call
  def send_reminder
    msg = "Heads up your mentor call will begin in 10 minutes"
    TwilioClient.account.sms.messages.create(:from => Settings.twilio.phone, :to => self.from_user.intl_phone, :body => msg)
    TwilioClient.account.sms.messages.create(:from => Settings.twilio.phone, :to => self.to_user.intl_phone, :body => msg)
  end
end