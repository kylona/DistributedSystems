ruleset twillio_test {
  meta {
    name "Testing Twillio Module"
    description <<
    Lab for connecting picos to AAPIs while keeping secrets secret
    >>
    author "Kyle Storey"
    use module com.twillio.sdk alias twillio
      with
        apiKey = meta:rulesetConfig{"apiKey"}
        token = meta:rulesetConfig{"token"}
    shares messages
  }

  global {
    messages = function(to=null, from=null, pageSize=5) {
      toOut = (to == "") => null | to
      fromOut = (from == "") => null | from
      pageSizeOut = (pageSize == "") => null | pageSize
      twillio:messages(toOut, fromOut, pageSizeOut)
    }
  }

  rule send_message {
    select when sms send
    pre {
      number = event:attrs{"number"} => event:attrs{"number"} | "+18019897113"
      message = event:attrs{"message"} => event:attrs{"message"} | "Default Message"
    }
    every {
      twillio:send_message(number, message) setting(response);
      send_directive("say", {"result": response});
    }
  }

}
