ruleset com.twillio.sdk {
  meta {
    name "Testing Twillio Module"
    description <<
    Lab for connecting picos to AAPIs while keeping secrets secret
    >>
    author "Kyle Storey"
    configure using
      apiKey = "Nope"
      token = "Nope"
      account = "AC55aeb76f7b2fe32a2f4e3a57f83f9e38"
      serviceId = "MGddfbc5dfe11d2e19250860c2f949c93a"
    provides messages, send_message
  }

  global {
    messages = function(to=null, from=null, pageSize=5) {
      url = "https://api.twilio.com/2010-04-01/Accounts/"+ account + "/Messages.json"
      qsData = (to == null && from == null) => {"PageSize":pageSize}
             | (to != null && from == null) => {"PageSize":pageSize, "To": to}
             | (from != null && to == null) => {"PageSize":pageSize, "From": from}
             | {"PageSize":pageSize, "To": to, "From": from}
      auth = {"username": apiKey, "password": token}
      response = http:get(url, qs=qsData, auth=auth, parseJSON=true)
      return response
    }
    send_message = defaction(number, message) {
      url = "https://api.twilio.com/2010-04-01/Accounts/"+ account + "/Messages.json"
      formData = {"To": number, "MessagingServiceSid": serviceId, "Body": message}
      auth = {"username": apiKey, "password": token}
      http:post(url, form=formData, auth=auth) setting(response)
      return response
    }
  }

}
