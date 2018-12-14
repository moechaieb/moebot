class Bot
  attr_reader :username, :password, :agent
  attr_accessor :cookie, :data

  FOLLOWERS_THRESHOLD = 500

  def initialize(username: , password: , hashtags: , log_path:)
    @username = username
    @password = password
    @agent = Mechanize.new
    @agent.user_agent_alias = 'Mac Safari'
    @cookies = nil
    @log_path = log_path
    @hashtags = hashtags
    @likes_per_run = 10
    @follows_per_run = 10
    @unfollows_per_run = 0
    @login_counter = 0

    init_log
  end

  def self.daemon_run(**args)
    pid = fork do
      bot_instance = new(**args)
      bot_instance.check_login_status
      loop { bot_instance.work }
    end

    puts "Running instagram bot in process ID #{pid}"

    exit(0)
  end

  def work
    result_sets = search
    post_handles = result_sets.fetch(:post_handles)
    user_ids = result_sets.fetch(:user_ids)

    like(post_handles)
    follow(user_ids)
    # unfollow
  end

  def check_login_status
    log '[+] '.cyan + 'Checking login status'

    if @login_status
      log "Already logged in.".green
      return true
    else
      log "[-] [##{@login_counter}] ".cyan + "You're not logged in (or it is an error with the request)\t[TRYING AGAIN]".red.bold
      exit! if @login_counter == 3
      @login_counter += 1
      login
    end
  end

  def login
    log "Logging in..."
    resilient_get('https://www.instagram.com/accounts/login/?force_classic_login')
    agent.page.forms[0]['username'] = username
    agent.page.forms[0]['password'] = password
    response = agent.page.forms[0].submit
    cookies = agent.cookies

    if response.body.match(/logged-in/)
      log 'Logged in'.green
      @login_status = true
    else
      log 'Failed to log in'.red
      @login_status = false
    end
    set_mechanize_data
  end

  private

  def search
    log "Grabbing hashtags..."
    used_tags = []
    user_ids = []
    post_handles = []

    @hashtags.shuffle.take(10).each do |tag|
      log '[+] '.cyan + "Searching for posts and user_ids with hashtag [##{tag}]"
      url         = "https://www.instagram.com/explore/tags/#{tag}/?__a=1"
      response    = resilient_get(url)

      next if response == :failed

      unless response.code == '200'
        log "Request to get hashtag #{tag} failed. Skipping...".red
        next
      end

      data        = parse_response(response.body)
      owners      = data.deep_find_all('owner')

      #get handles
      media_codes = data.deep_find_all('shortcode')
      next if owners.nil? || media_codes.nil?
      owners.map { |id| user_ids << id['id'] if !id['id'].nil? }
      media_codes.map { |code| post_handles << code if !code.nil? }
      used_tags << tag
    end

    log "Done. Total grabbed user_ids(#{user_ids.size.to_s.yellow}) & Total grabbed posts(#{post_handles.size.to_s.yellow})"

    {
      post_handles: post_handles.shuffle.take(@likes_per_run),
      user_ids: user_ids.shuffle.take(@follows_per_run)
    }
  end

  def like(post_handles)
    log "Liking posts..."
    posts_liked = 0
    check_login_status

    post_handles.each do |handle|
      begin
        log "[+] ".magenta + "Trying to like post [#{handle}]..."

        post_id = handle_media_information_data(handle)[:id]
        like_url = "https://www.instagram.com/web/likes/#{post_id}/like/"

        response = agent.post(like_url, @params, @headers)

        if response.code == '200'
          posts_liked += 1
          log "Liked post #{post_id}".green
        else
          log "Failed to like post #{post_id}".red
        end
        wait_random(min: 3, max: 10)
      rescue => e
        log "Failed to like post #{post_id} due to #{e}".red
      end
    end

    log "Done. Liked #{posts_liked} posts."
  end

  def follow(user_ids)
    log "Following users..."
    number_of_users_followed = 0
    check_login_status
    users_followed = File.read('followed.log').scan(/INFO -- :\s(.*)$/).flatten

    user_ids.each do |user_id|
      begin
        log "[+] ".yellow + "Trying to follow user [#{user_id}]..."

        follow_url = "https://www.instagram.com/web/friendships/#{user_id}/follow/"
        user_response = resilient_get(follow_url)

        next if user_response == :failed

        username = user_response.uri.to_s.split('/')[3]
        number_of_followers = get_number_of_followers(username)

        if number_of_followers < FOLLOWERS_THRESHOLD
          log "#{username} only has #{number_of_followers} (less than #{FOLLOWERS_THRESHOLD}). Skipping...".red
          next
        end

        response = @agent.post(follow_url, @params, @headers)
        if response.code == '200'
          if users_followed.include?(username)
            log "Already followed #{username}. Skipping...".red
          else
            number_of_users_followed += 1
            log_follower(username)
            log "Followed user #{username} (#{number_of_followers} followers)".green
            log_to_unfollow(username, user_id)
          end
        else
          log "Failed to follow user #{username}".red
        end

      rescue => e
        log "Failed to follow user #{user_id} due to #{e}".red
      end
      wait_random
    end

    log "Done. Followed #{number_of_users_followed} users."
  end

  def unfollow
    log "Unfollowing users..."
    check_login_status
    to_unfollow = {}
    File.read('to_unfollow.log').scan(/INFO -- :\s([^,]*),?\s?(\d*)$/).take(@unfollows_per_run).each do |username, user_id|
      to_unfollow[username] = user_id
    end

    unfollowed = []

    to_unfollow.each do |username, user_id|
      begin
        if user_id.empty?
          user_id = get_user_id_from_username(username)
          log "Gonna unfollow #{username}, user_id: #{user_id}".yellow
        end

        log "Trying to unfollow a user id [#{user_id}]"
        unfollow_url = "https://www.instagram.com/web/friendships/#{user_id}/unfollow/"
        response = @agent.post(unfollow_url, @params, @headers)
        if response.code == '200'
          log "Unfollowed user #{username}".green
          unfollowed << username
        else
          log "Failed to unfollow user #{username}".red
        end

      rescue => e
        log "Failed to unfollow #{username} due to #{e}".red
      end
      wait_random
    end

    if unfollowed.empty?
      log "Didn't unfollow anyone."
    else
      log "Cleaning up to_unfollow.log..."
      strip_file_from_lines_containing(unfollowed, 'to_unfollow.log')
    end
    log "Done."
  end

  def get_user_id_from_username(username)
    get_media_information(parse_response(resilient_get("https://www.instagram.com/#{username}?__a=1").body))[:id]
  end

  def strip_file_from_lines_containing(usernames, file_path)
    lines = File.read(file_path).lines

    filtered_lines = lines - lines.select { |line| usernames.any? { |username| line.include?(username) } }

    File.open(file_path, 'w') do |f|
      f.write(filtered_lines.join)
    end
  end

  def set_mechanize_data(params = {})
    @cookies   = Hash[agent.cookies.map { |key, _value| [key.name, key.value] }]
    @params     = params
    @headers   = {
      'Cookie'           => "mid=#{@cookies['mid']}; csrftoken=#{@cookies['csrftoken']}; sessionid=#{@cookies['sessionid']}; ds_user_id=#{@cookies['ds_user_id']}; rur=#{@cookies['rur']}; s_network=#{@cookies['s_network']}; ig_pr= 1; ig_vw=1920",
      'X-CSRFToken'      => (@cookies['csrftoken']).to_s,
      'X-Requested-With' => 'XMLHttpRequest',
      'Content-Type'     => 'application/x-www-form-urlencoded',
      'X-Instagram-AJAX' => '1',
      'Accept'           => 'application/json, text/javascript, */*',
      'User-Agent'       => Mechanize::AGENT_ALIASES['Mac Safari'],
      'Accept-Encoding'  => 'gzip, deflate',
      'Accept-Language'  => 'ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4',
      'Connection'       => 'keep-alive',
      'Host'             => 'www.instagram.com',
      'Origin'           => 'https://www.instagram.com',
      'Referer'          => 'https://www.instagram.com/'
    }
  end

  def get_media_information(data)
    {
      id:                  data.deep_find('id'),
      full_name:           data.deep_find('full_name'),
      owner:               data.deep_find('owner')['username'],
      is_video:            data.deep_find('is_video'),
      comments_disabled:   data.deep_find('comments_disabled'),
      viewer_has_liked:    data.deep_find('viewer_has_liked'),
      has_blocked_viewer:  data.deep_find('has_blocked_viewer'),
      followed_by_viewer:  data.deep_find('followed_by_viewer'),
      is_private:          data.deep_find('is_private'),
      is_verified:         data.deep_find('is_verified'),
      requested_by_viewer: data.deep_find('requested_by_viewer'),
      text:                data.deep_find('text')
    }
  end

  def handle_media_information_data(handle)
    log '[+] '.cyan + "Trying to get media (https://www.instagram.com/p/#{handle}) information"
    response = resilient_get("https://www.instagram.com/p/#{handle}/?__a=1")
    data     = parse_response(response.body)

    get_media_information(data)
  end

  def get_user_information_data_by_user_id(user_id)
    log '[+] '.cyan + "Trying to get user (#{user_id}) information"
    user_page = "https://www.instagram.com/web/friendships/#{user_id}/follow/"
    response  = resilient_get(user_page)
    last_page = response.uri.to_s
    username  = last_page.split('/')[3]

    username
  end

  def get_number_of_followers(handle)
    log '[+] '.cyan + "Trying to get number of followers for #{handle}"
    response  = resilient_get("https://www.instagram.com/#{handle}?__a=1")

    unless response.code == '200'
      log "Retrieving number of followers failed... Skipping.".red
    end

    JSON.parse(response.body).dig('graphql', 'user', 'edge_followed_by', 'count')
  end

  def parse_response(body)
    data = JSON.parse(body)
    data.extend Hashie::Extensions::DeepFind
    data
  end

  def log(message)
    logger.info(message)
  end

  def log_follower(username)
    follow_logger.info(username)
  end

  def log_to_unfollow(username, user_id)
    unfollow_logger.info [username, user_id].join(", ")
  end

  def logger
    @logger ||= Logger.new(@log_path)
  end

  def follow_logger
    @follow_logger ||= Logger.new('followed.log')
  end

  def unfollow_logger
    @unfollow_logger ||= Logger.new('to_unfollow.log')
  end

  def init_log
    log ("-" * 75).light_red
    log "Initialized Instagram bot for #{@username}."
    log "User agent: #{@agent.user_agent}"
    log "Hashtags: #{@hashtags}"
    log "Like limit per iteration: #{@likes_per_run}, Follow limit per iteration: #{@follows_per_run}"
    log ("-" * 75).light_red
  end

  def wait_random(min: 10, max: 15)
    sleep_duration = (min + rand(max-min))
    log "Sleeping for #{sleep_duration}s...".light_black
    sleep sleep_duration
  end

  def resilient_get(url, retries: 3)
    retries.times do |i|
      log "Retrying GET #{url}..." unless i.zero?
      begin
        return @agent.get(url)
      rescue Mechanize::ResponseReadError, Mechanize::ResponseCodeError, Errno::EHOSTUNREACH, SocketError => e
        log "GET request to #{url} failed with #{e.class}".red
        wait_random(min: 10, max: 15)
      end
    end

    log "GET request to #{url} failed in #{retries} consecutive attempts. Skipping...".red

    :failed
  end
end
