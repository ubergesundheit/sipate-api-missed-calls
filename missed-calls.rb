require "net/http"
require "active_support/core_ext/hash"
require "mandrill"
require "dotenv"
Dotenv.load

def extract_property(prop, arr)
  arr.select { |m| m["name"] == prop }[0]["value"]["string"]
end

uri = URI.parse("https://samurai.sipgate.net/RPC2")
time_before = 6 * 60

# This shit is way too verbose :O
# request_body = "<methodCall><methodName>samurai.HistoryGetByDate</methodName><params><param><value><struct><member><name>StatusList</name><value><array><data><value><string>missed</string></value></data></array></value></member><member><name>PeriodStart</name><value><string>#{(Time.now - time_before).strftime("%FT%T%:z")}</string></value></member></struct></value></param></params></methodCall>"
request_body = "<methodCall><methodName>samurai.HistoryGetByDate</methodName><params><param><value><struct><member><name>StatusList</name><value><array><data><value><string>missed</string></value></data></array></value></member></struct></value></param></params></methodCall>"

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

req = Net::HTTP::Post.new(uri.path)
req.body = request_body
req.content_type = "text/xml"
req.basic_auth(ENV["SIPGATE_USERNAME"],ENV["SIPGATE_PASSWORD"])

res = http.request(req)
puts res.body
parsed_response = Hash.from_xml(res.body)

# WTF xml..

calls = parsed_response["methodResponse"]["params"]["param"]["value"]["struct"]["member"].select { |h| h["name"] == "History" }[0]["value"]["array"]["data"]["value"].map do |struct|
  member = struct["struct"]["member"]
  {
    timestamp: extract_property("Timestamp", member),
    caller_id: extract_property("RemoteUri", member)[/\d+|anonymous/]
  }
end

unless calls.length == 0
  message = {
    subject: ENV["EMAIL_SUBJECT"],
    from_name: ENV["EMAIL_FROM_NAME"],
    text: calls.map { |e| e.values.join " " }.join("\n"),
    to: [{
      email: ENV["EMAIL_TO"],
      name: ENV["EMAIL_TO_NAME"]
    }],
    from_email: ENV["EMAIL_FROM"]
  }
  mandrill = Mandrill::API.new ENV["MANDRILL_APIKEY"]
  mandrill.messages.send message
end
