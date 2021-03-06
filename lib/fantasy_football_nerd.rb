require 'nokogiri'
require 'open-uri'
require 'hashie'

class FFNerd

  BASE_URL = "http://api.fantasyfootballnerd.com"

  FEEDS = {
    schedule:    'ffnScheduleXML.php',
    projections: 'ffnSitStartXML.php',
    injuries:    'ffnInjuriesXML.php',
    all_players: 'ffnPlayersXML.php',
    rankings:    'ffnRankingsXML.php',
    player:      'ffnPlayerDetailsXML.php'
  }

  #############################################################################
  # URL Generators
  # These methods generate the URLs that will be used for the API calls
  # feed_url() does most of the heavy lifting
  # the others are to make things easier on the developer
  #############################################################################

  def self.api_key
    @@api_key
  end

  def self.api_key=(api_key)
    @@api_key = api_key
  end

  def self.feed_url(feed, params = {} )
    raise 'api_key not set' if @@api_key.nil?
    url = "#{BASE_URL}/#{FEEDS[feed]}?apiKey=#{@@api_key}"
    params.each { |key, value| url += "&#{key}=#{value}" }
    url
  end

  def self.player_url(player_id)
    feed_url(:player, 'playerId' => player_id)
  end

  def self.projections_url(position, week)
    position = position.to_s.upcase
    url = feed_url(:projections, 'week' => week, 'position' => position)
  end

  def self.injuries_url(week)
    feed_url(:injuries, 'week' => week)
  end

  def self.player_list_url
    feed_url(:all_players)
  end


  #############################################################################
  # Resource retreiver
  # Connect to the API resource using the Url builders and Nokogiri
  #############################################################################

  def self.get_resource(url)
    Nokogiri::HTML(open(url))
  end

  #############################################################################
  # Player List
  # Grabs a list of all players
  #############################################################################


  def self.player_list
    players = []
    url     = player_list_url
    doc     = get_resource(url)
    doc.css('player').each do |data|
      player = Hashie::Mash.new
      player.id = data.attr('playerid').to_i
      player.name = data.attr('name')
      player.position = data.attr('position')
      player.team = data.attr('team')
      players << player
    end
    players
  end

  #############################################################################
  # Player Detail
  # grabs player detail and related news articles
  #############################################################################


  def self.player_detail(player_id)
    player = Hashie::Mash.new
    url = player_url(player_id)
    doc = get_resource(url)
    player.first_name = doc.css('playerdetails firstname').text
    player.last_name  = doc.css('playerdetails lastname').text
    player.team       = doc.css('playerdetails team').text
    player.position   = doc.css('playerdetails position').text
    player.articles   = []
    parse_articles(doc).each { |article| player.articles << article }
    player
  end

  #used by self.player to get articles
  def self.parse_articles(doc)
    articles = []
    doc.css('article').each do |data|
      article = Hashie::Mash.new
      article.title     = data.css('title').text
      article.source    = data.css('source').text
      article.published = Date.parse(data.css('published').text)
      articles << article
    end
    articles
  end

  #############################################################################
  # Projections
  # retrieves weekly projections
  #############################################################################

  def self.projections(week, position = :all)
    projections = []
    position    = position.to_s.upcase
    url         = projections_url(position, week)
    doc         = get_resource(url)
    doc.css('player').each do |data|
      player = Hashie::Mash.new
      player.name             = data.attr('name')
      player.projected_points = data.attr('projectedpoints').to_f
      player.team             = data.attr('team')
      player.position         = data.attr('position')
      player.id               = data.attr('playerid').to_i
      player.rank             = data.attr('rank').to_i

      #create and population player.projection
      player.projection       = Hashie::Mash.new
      player.projection.week  = data.attr('week').to_i
      projections_map.each do |attribute, xml|
        player.projection[attribute] = data.css("projections #{xml}").text.to_f
      end

      projections << player
    end
    projections
  end

  def self.projections_map
    {
      standard: 'standard',
      standard_low: 'standardlow',
      standard_high: 'standardhigh',
      ppr: 'ppr',
      ppr_low: 'pprlow',
      ppr_high: 'pprhigh'
    }
  end

  #############################################################################
  # Injuries
  # retrieves weekly injuries
  #############################################################################


  def self.injuries(week)
    players = []
    url = injuries_url(week)
    doc = get_resource(url)
    #puts doc.css('injury')
    doc.css('injury').each do |data|
      player = Hashie::Mash.new

      injury_player_data_map.each do |attribute, xml|
        player[attribute] = data.css(xml).text
      end

      player.injury = Hashie::Mash.new
      injury_data_map.each do |attribute, xml|
        player.injury[attribute] = data.css(xml).text
      end

      #convert to more appropriate data types
      player.id  = player.id.to_i
      player.injury.week  = player.injury.week.to_i
      player.injury.last_update = Date.parse(player.injury.last_update)

      players << player
    end
    players
  end


  def self.injury_data_map
    {
      week: 'week',
      injury_desc: 'injurydesc',
      practice_status_desc: 'practicestatusdesc',
      game_status_desc: 'gamestatusdesc',
      last_update: 'lastupdate'
    }
  end

  def self.injury_player_data_map
    {
      id: 'playerid',
      name: 'playername',
      team: 'team',
      position: 'position'
    }
  end

  #############################################################################
  # Schedule
  # Returns a Hashie of the schedule for a given week (or default whole season)
  #############################################################################
  def self.schedule_url
    url = feed_url(:schedule)
  end

  def self.schedule(week = :all)

    schedule  = []
    url = schedule_url
    doc = get_resource(url)
    doc.css('game').each do |data|
      game = Hashie::Mash.new
      game.id = data.attr('gameid').to_i
      game.week = data.attr('week').to_i
      game.date = DateTime.parse(data.attr('gamedate'))
      game.home = data.attr('hometeam')
      game.away = data.attr('awayteam')
      game.time = Time.new(data.attr('gametime'))
      schedule << game
    end
    if !week.eql? :all
      schedule = schedule.select {|game| game.week.eql? week}
    end
    schedule
  end


  def self.game_data_map
    {

    }

  end

  #############################################################################
  # Draft Rankings
  # Preseason draft rankings
  # Separate calls for standard and PPR.
  #############################################################################

  def self.rankings_url(position, limit, ppr, strength_of_sched)
    position = position.to_s.upcase
    strength_of_sched = (strength_of_sched ? 1 : 0)
    query_hash = {
      'position' => position,
      'sos' => strength_of_sched,
      'limit' => limit
    }
    if ppr
      query_hash['ppr'] = 1
    end
    feed_url(:rankings, query_hash)
  end

  def self.ppr_rankings(position = :all, limit = 20, strength_of_sched = true)
    rankings = []
    url = rankings_url(position, limit, false, strength_of_sched)
    doc = get_resource(url)
    doc.css('player').each  do |data|
      ranking = Hashie::Mash.new
      ranking.player_id = data.attr('playerid').to_i
      ranking.player_name = data.attr('name')
      ranking.player_team = data.attr('team')
      ranking.player_position = data.attr('position')
      rankings << ranking
    end
    rankings

  end

  def self.standard_rankings(position = :all, limit = 999, strength_of_sched = false)
    rankings = []
    url = rankings_url(position, limit, true, strength_of_sched)
    doc = get_resource(url)
    doc.css('player').each  do |data|
      ranking = Hashie::Mash.new
      ranking.player_id = data.attr('playerid').to_i
      ranking.player_name = data.attr('name')
      ranking.player_team = data.attr('team')
      ranking.player_position = data.attr('position')
      ranking.player_overall_rank = data.attr('overallrank')
      ranking.player_position_rank = data.attr('positionrank')
      ranking.player_bye = data.attr('byeweek')
      rankings << ranking
    end
    rankings
  end


  #############################################################################
  # players
  # The one method to rule them all
  #############################################################################

  def self.players(week, position = :all)
    players = {}

    FFNerd.projections(week).each do |player|
      player.injured = false
      players[player.id] = player
    end

    FFNerd.injuries(week).each do |player|
      raise if players[player.id].nil?
      players[player.id].injured = true
      players[player.id].injury = player.injury
    end

    players.values
  end


end
